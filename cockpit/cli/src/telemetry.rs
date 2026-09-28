//! `cockpit telemetry` (plano 66): verbos de consulta da Caixa Preta e o
//! wrapper que observa um processo (`cockpit telemetry <cmd>`).
//!
//! O wrapper é burro de propósito: sobe o filho (PTY aninhado quando há TTY,
//! pipes quando não há), repassa os bytes intocados pra tela e, em paralelo,
//! manda as linhas pro app em lotes. Quem interpreta é o parser do app.

use std::io::{IsTerminal, Read, Write};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Map, Value};

use crate::transport::{self, is_ok};
use crate::util::{die, self_tab_id};

const HELP: &str = include_str!("../text/telemetry_help.txt");
const QUERY_TIMEOUT: Duration = Duration::from_secs(60);
const WAIT_TIMEOUT: Duration = Duration::from_secs(11 * 60);
const BATCH_LINES: usize = 200;
const BATCH_DELAY: Duration = Duration::from_millis(100);

const QUERY_VERBS: [&str; 13] = [
    "errors", "logs", "events", "runs", "show", "wait", "mark", "resolve", "ignore", "reopen",
    "clear", "probes", "perf",
];
const BOOL_FLAGS: [&str; 9] = [
    "--app",
    "--since-edit",
    "--since-run",
    "--new",
    "--include-ignored",
    "--include-resolved",
    "--live",
    "--any-new",
    "--json",
];

pub fn telemetry(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        if args.is_empty() {
            eprint!("{HELP}");
            std::process::exit(2);
        }
        print!("{HELP}");
        std::process::exit(0);
    }
    if QUERY_VERBS.contains(&args[0].as_str()) {
        query(&args[0], &args[1..]);
    }
    wrap(args);
}

fn fail(kind: &str, message: &str) -> ! {
    println!("{}", json!({"error": {"kind": kind, "message": message}}));
    std::process::exit(1)
}

// ---- consulta ---------------------------------------------------------------

fn query(verb: &str, rest: &[String]) -> ! {
    let mut a = Map::new();
    let mut positionals: Vec<String> = Vec::new();
    let mut tab_id: Option<String> = None;
    let mut i = 0;
    while i < rest.len() {
        let tok = &rest[i];
        if BOOL_FLAGS.contains(&tok.as_str()) {
            a.insert(key_of(tok), json!(true));
        } else if let Some(stripped) = tok.strip_prefix("--") {
            let (k, v) = match stripped.split_once('=') {
                Some((k, v)) => (k.to_string(), v.to_string()),
                None => {
                    i += 1;
                    let v = rest
                        .get(i)
                        .cloned()
                        .unwrap_or_else(|| fail("error", &format!("missing value for {tok}")));
                    (stripped.to_string(), v)
                }
            };
            if k == "tab-id" {
                tab_id = Some(v);
            } else {
                a.insert(k.replace('-', "_"), json!(v));
            }
        } else {
            positionals.push(tok.clone());
        }
        i += 1;
    }

    let wire = match verb {
        "errors" | "logs" | "events" | "runs" | "probes" | "perf" => format!("telemetry-{verb}"),
        "show" => {
            let id = positionals
                .first()
                .cloned()
                .unwrap_or_else(|| fail("error", "missing id (e_xxxx | ev_xxxx | r_xx)"));
            a.insert("id".into(), json!(id));
            "telemetry-show".into()
        }
        "wait" => "telemetry-wait".into(),
        "mark" => {
            if positionals.len() < 2 || !(positionals[0] == "start" || positionals[0] == "end") {
                fail("error", "usage: cockpit telemetry mark start|end <name>");
            }
            a.insert("action".into(), json!(positionals[0]));
            a.insert("name".into(), json!(positionals[1]));
            "telemetry-mark".into()
        }
        "resolve" | "ignore" | "reopen" => {
            let id = positionals
                .first()
                .cloned()
                .unwrap_or_else(|| fail("error", "missing case id (e_xxxx)"));
            a.insert("id".into(), json!(id));
            a.insert("status".into(), json!(verb));
            "telemetry-triage".into()
        }
        "clear" => "telemetry-clear".into(),
        "replay" => "telemetry-replay".into(),
        _ => unreachable!(),
    };
    let timeout = if verb == "wait" {
        WAIT_TIMEOUT
    } else {
        QUERY_TIMEOUT
    };
    let mut req = json!({"cmd": wire, "args": Value::Object(a)});
    if let Some(id) = tab_id.or_else(self_tab_id) {
        req["tabId"] = json!(id);
    }
    let resp = transport::request(req, timeout);
    if is_ok(&resp) {
        let data = resp.get("data").cloned().unwrap_or(Value::Null);
        println!("{}", json!({"ok": data}));
        std::process::exit(0);
    }
    let raw = transport::error_text(&resp);
    match raw.split_once(": ") {
        Some((kind, msg)) if !kind.contains(' ') => fail(kind, msg),
        _ => fail("error", &raw),
    }
}

fn key_of(flag: &str) -> String {
    flag.trim_start_matches("--").replace('-', "_")
}

// ---- wrapper ----------------------------------------------------------------

struct WrapOpts {
    name: Option<String>,
    quiet: bool,
    argv: Vec<String>,
}

fn parse_wrap(args: &[String]) -> WrapOpts {
    let mut name = None;
    let mut quiet = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--" => {
                i += 1;
                break;
            }
            "-q" | "--quiet" => quiet = true,
            "--name" => {
                i += 1;
                name = args.get(i).cloned();
                if name.is_none() {
                    die("cockpit telemetry: missing value for --name", 2);
                }
            }
            s if s.starts_with("--name=") => name = Some(s["--name=".len()..].to_string()),
            _ => break,
        }
        i += 1;
    }
    let argv: Vec<String> = args[i..].to_vec();
    if argv.is_empty() {
        die("cockpit telemetry: missing command to run (see --help)", 2);
    }
    WrapOpts { name, quiet, argv }
}

/// Mensagem enviada pela thread de IO pra thread que fala com o app.
enum Msg {
    Lines(&'static str, Vec<String>),
    Done,
}

fn wrap(args: &[String]) -> ! {
    let opts = parse_wrap(args);
    let cwd = std::env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();
    let command = opts.argv.join(" ");

    // Sem app pra falar: roda o comando normalmente, avisa uma vez.
    if !transport::transport_configured() {
        eprintln!("telemetry: not inside Cockpit, running without capture");
        let code = passthrough(&opts.argv);
        std::process::exit(code);
    }

    let mut open = json!({"cmd": "telemetry-open", "args": {
        "cwd": cwd, "command": command, "name": opts.name, "pid": std::process::id(),
    }});
    if let Some(id) = self_tab_id() {
        open["tabId"] = json!(id);
    }
    let resp = transport::request(open, QUERY_TIMEOUT);
    if !is_ok(&resp) {
        eprintln!(
            "telemetry: {} (running without capture)",
            transport::error_text(&resp)
        );
        let code = passthrough(&opts.argv);
        std::process::exit(code);
    }
    let run_id = resp["data"]["run"].as_str().unwrap_or("").to_string();
    let mut env: Vec<(String, String)> = Vec::new();
    if let Some(m) = resp["data"]["env"].as_object() {
        for (k, v) in m {
            if let Some(s) = v.as_str() {
                env.push((k.clone(), s.to_string()));
            }
        }
    }

    // Thread que fala com o app: recebe lotes de linhas e manda `telemetry-ingest`.
    let (tx, rx) = mpsc::channel::<Msg>();
    let tab = self_tab_id();
    let run_for_sender = run_id.clone();
    let sender = thread::spawn(move || {
        let mut pending: Vec<(&'static str, Vec<String>)> = Vec::new();
        let mut last = Instant::now();
        let flush = |pending: &mut Vec<(&'static str, Vec<String>)>| {
            for (stream, lines) in pending.drain(..) {
                let mut req = json!({"cmd": "telemetry-ingest", "args": {
                    "run": run_for_sender, "stream": stream, "lines": lines,
                }});
                if let Some(id) = &tab {
                    req["tabId"] = json!(id);
                }
                let _ = transport::request(req, QUERY_TIMEOUT);
            }
        };
        loop {
            match rx.recv_timeout(BATCH_DELAY) {
                Ok(Msg::Lines(stream, lines)) => {
                    match pending.last_mut() {
                        Some((s, l)) if *s == stream => l.extend(lines),
                        _ => pending.push((stream, lines)),
                    }
                    let total: usize = pending.iter().map(|(_, l)| l.len()).sum();
                    if total >= BATCH_LINES || last.elapsed() >= BATCH_DELAY {
                        flush(&mut pending);
                        last = Instant::now();
                    }
                }
                Ok(Msg::Done) => {
                    flush(&mut pending);
                    return;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if !pending.is_empty() {
                        flush(&mut pending);
                        last = Instant::now();
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    flush(&mut pending);
                    return;
                }
            }
        }
    });

    let interactive = std::io::stdin().is_terminal() && std::io::stdout().is_terminal();
    let code = if interactive {
        run_pty(&opts.argv, &env, &tx)
    } else {
        run_pipes(&opts.argv, &env, &tx)
    };
    let _ = tx.send(Msg::Done);
    let _ = sender.join();

    let mut close = json!({"cmd": "telemetry-close", "args": {"run": run_id, "exit_code": code}});
    if let Some(id) = self_tab_id() {
        close["tabId"] = json!(id);
    }
    let resp = transport::request(close, QUERY_TIMEOUT);
    if !opts.quiet {
        let errors = resp["data"]["errors"].as_u64().unwrap_or(0);
        let warnings = resp["data"]["warnings"].as_u64().unwrap_or(0);
        eprintln!(
            "telemetry: run {run_id} · {errors} errors · {warnings} warnings · cockpit telemetry errors --run {run_id}"
        );
    }
    std::process::exit(code);
}

/// Sem captura: só executa e devolve o exit code.
fn passthrough(argv: &[String]) -> i32 {
    match std::process::Command::new(&argv[0])
        .args(&argv[1..])
        .status()
    {
        Ok(st) => exit_code_of(&st),
        Err(e) => {
            eprintln!("cockpit telemetry: {}: {e}", argv[0]);
            127
        }
    }
}

fn exit_code_of(st: &std::process::ExitStatus) -> i32 {
    if let Some(c) = st.code() {
        return c;
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(sig) = st.signal() {
            return 128 + sig;
        }
    }
    1
}

/// Separa linhas de um fluxo de bytes; o resto fica pra próxima chamada.
struct LineSplitter {
    stream: &'static str,
    partial: Vec<u8>,
}

impl LineSplitter {
    fn new(stream: &'static str) -> Self {
        Self {
            stream,
            partial: Vec::new(),
        }
    }

    fn push(&mut self, data: &[u8], tx: &mpsc::Sender<Msg>) {
        self.partial.extend_from_slice(data);
        let mut lines = Vec::new();
        let mut start = 0;
        for (i, b) in self.partial.iter().enumerate() {
            if *b == b'\n' {
                let mut end = i;
                if end > start && self.partial[end - 1] == b'\r' {
                    end -= 1;
                }
                lines.push(String::from_utf8_lossy(&self.partial[start..end]).to_string());
                start = i + 1;
            }
        }
        if start > 0 {
            self.partial.drain(..start);
        }
        if !lines.is_empty() {
            let _ = tx.send(Msg::Lines(self.stream, lines));
        }
    }

    fn finish(&mut self, tx: &mpsc::Sender<Msg>) {
        if !self.partial.is_empty() {
            let rest = String::from_utf8_lossy(&self.partial).to_string();
            self.partial.clear();
            if !rest.trim().is_empty() {
                let _ = tx.send(Msg::Lines(self.stream, vec![rest]));
            }
        }
    }
}

/// Sem TTY (Bash do agente, pipe): stdout e stderr separados, cada um ecoado
/// no fd correspondente e capturado.
fn run_pipes(argv: &[String], env: &[(String, String)], tx: &mpsc::Sender<Msg>) -> i32 {
    use std::process::{Command, Stdio};
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..])
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("cockpit telemetry: {}: {e}", argv[0]);
            return 127;
        }
    };
    let out = child.stdout.take();
    let err = child.stderr.take();
    let tx_out = tx.clone();
    let t_out = thread::spawn(move || pump(out, "out", tx_out, false));
    let tx_err = tx.clone();
    let t_err = thread::spawn(move || pump(err, "err", tx_err, true));
    let status = child.wait();
    let _ = t_out.join();
    let _ = t_err.join();
    match status {
        Ok(st) => exit_code_of(&st),
        Err(_) => 1,
    }
}

fn pump<R: Read>(src: Option<R>, stream: &'static str, tx: mpsc::Sender<Msg>, to_stderr: bool) {
    let Some(mut src) = src else { return };
    let mut split = LineSplitter::new(stream);
    let mut buf = [0u8; 8192];
    loop {
        match src.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                if to_stderr {
                    let mut e = std::io::stderr().lock();
                    let _ = e.write_all(&buf[..n]);
                    let _ = e.flush();
                } else {
                    let mut o = std::io::stdout().lock();
                    let _ = o.write_all(&buf[..n]);
                    let _ = o.flush();
                }
                split.push(&buf[..n], &tx);
            }
        }
    }
    split.finish(&tx);
}

/// Com TTY: PTY aninhado (forkpty) pra cores, teclas e resize continuarem
/// funcionando. stdout e stderr chegam misturados (é um PTY), como hoje.
#[cfg(unix)]
fn run_pty(argv: &[String], env: &[(String, String)], tx: &mpsc::Sender<Msg>) -> i32 {
    use std::ffi::CString;
    use std::os::unix::io::{AsRawFd, FromRawFd};

    let stdin_fd = std::io::stdin().as_raw_fd();
    // termios/winsize atuais do terminal externo: o filho nasce igual.
    let mut orig: libc::termios = unsafe { std::mem::zeroed() };
    if unsafe { libc::tcgetattr(stdin_fd, &mut orig) } != 0 {
        return run_pipes(argv, env, tx);
    }
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    unsafe { libc::ioctl(stdin_fd, libc::TIOCGWINSZ, &mut ws) };

    let cargv: Vec<CString> = argv
        .iter()
        .map(|a| CString::new(a.as_str()).unwrap_or_default())
        .collect();
    let cenv: Vec<(CString, CString)> = env
        .iter()
        .map(|(k, v)| {
            (
                CString::new(k.as_str()).unwrap_or_default(),
                CString::new(v.as_str()).unwrap_or_default(),
            )
        })
        .collect();

    let mut master: libc::c_int = -1;
    let pid = unsafe {
        libc::forkpty(
            &mut master,
            std::ptr::null_mut(),
            &mut orig as *mut libc::termios as _,
            &mut ws as *mut libc::winsize as _,
        )
    };
    if pid < 0 {
        return run_pipes(argv, env, tx);
    }
    if pid == 0 {
        // Filho: env + exec. Nada de alocação além do necessário.
        for (k, v) in &cenv {
            unsafe { libc::setenv(k.as_ptr(), v.as_ptr(), 1) };
        }
        let mut ptrs: Vec<*const libc::c_char> = cargv.iter().map(|c| c.as_ptr()).collect();
        ptrs.push(std::ptr::null());
        unsafe { libc::execvp(cargv[0].as_ptr(), ptrs.as_ptr()) };
        unsafe { libc::_exit(127) };
    }

    // Pai: terminal externo em raw (o filho é quem ecoa), restaurado no fim.
    let mut raw = orig;
    unsafe { libc::cfmakeraw(&mut raw) };
    unsafe { libc::tcsetattr(stdin_fd, libc::TCSANOW, &raw) };

    // stdin → master numa thread (bloqueante, sem poll no fd 0).
    let master_w = unsafe { std::fs::File::from_raw_fd(libc::dup(master)) };
    thread::spawn(move || {
        let mut master_w = master_w;
        let mut stdin = std::io::stdin().lock();
        let mut buf = [0u8; 1024];
        loop {
            match stdin.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if master_w.write_all(&buf[..n]).is_err() {
                        break;
                    }
                }
            }
        }
    });

    // master → stdout + captura; resize propagado por comparação periódica.
    let mut split = LineSplitter::new("out");
    let mut buf = [0u8; 8192];
    let mut last_ws = (ws.ws_row, ws.ws_col);
    let mut pfd = libc::pollfd {
        fd: master,
        events: libc::POLLIN,
        revents: 0,
    };
    loop {
        pfd.revents = 0;
        let r = unsafe { libc::poll(&mut pfd, 1, 100) };
        if r < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            break;
        }
        // resize?
        let mut cur: libc::winsize = unsafe { std::mem::zeroed() };
        if unsafe { libc::ioctl(stdin_fd, libc::TIOCGWINSZ, &mut cur) } == 0
            && (cur.ws_row, cur.ws_col) != last_ws
        {
            last_ws = (cur.ws_row, cur.ws_col);
            unsafe { libc::ioctl(master, libc::TIOCSWINSZ, &cur) };
        }
        if r == 0 {
            continue;
        }
        if pfd.revents & (libc::POLLIN) != 0 {
            let n = unsafe { libc::read(master, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };
            if n <= 0 {
                break; // EOF/EIO: filho fechou o PTY
            }
            let n = n as usize;
            let mut o = std::io::stdout().lock();
            let _ = o.write_all(&buf[..n]);
            let _ = o.flush();
            split.push(&buf[..n], tx);
        } else if pfd.revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0 {
            break;
        }
    }
    split.finish(tx);

    let mut status: libc::c_int = 0;
    unsafe { libc::waitpid(pid, &mut status, 0) };
    unsafe { libc::tcsetattr(stdin_fd, libc::TCSANOW, &orig) };
    unsafe { libc::close(master) };
    if libc::WIFEXITED(status) {
        libc::WEXITSTATUS(status)
    } else if libc::WIFSIGNALED(status) {
        128 + libc::WTERMSIG(status)
    } else {
        1
    }
}

/// Windows: ConPTY fica pra depois (plano 66, risco listado); com TTY usamos
/// pipes, o que perde cores/teclas interativas mas mantém a captura.
#[cfg(not(unix))]
fn run_pty(argv: &[String], env: &[(String, String)], tx: &mpsc::Sender<Msg>) -> i32 {
    run_pipes(argv, env, tx)
}
