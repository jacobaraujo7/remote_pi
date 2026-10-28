//! Transporte: uma requisição por conexão, uma linha JSON em cada direção.
//!
//! Mesmo socket do hook, discriminado por `type` no wire (`"cmd"` aqui,
//! status no hook). POSIX usa socket Unix (`COCKPIT_STATUS_SOCK`); Windows usa
//! TCP no loopback (`COCKPIT_STATUS_PORT` + `COCKPIT_STATUS_TOKEN`), porque lá
//! não há UDS. O token só importa no TCP: o loopback é acessível por qualquer
//! processo local, enquanto no UDS a permissão do arquivo já protege.

use std::io::{Read, Write};
use std::time::Duration;

use serde_json::{json, Value};

use crate::util::{die, env_non_empty};

/// Conexão aberta com o app, abstraindo UDS x TCP.
enum Conn {
    #[cfg(unix)]
    Unix(std::os::unix::net::UnixStream),
    Tcp(std::net::TcpStream),
}

impl Conn {
    fn set_read_timeout(&self, dur: Duration) -> std::io::Result<()> {
        match self {
            #[cfg(unix)]
            Conn::Unix(s) => s.set_read_timeout(Some(dur)),
            Conn::Tcp(s) => s.set_read_timeout(Some(dur)),
        }
    }
}

impl Read for Conn {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            #[cfg(unix)]
            Conn::Unix(s) => s.read(buf),
            Conn::Tcp(s) => s.read(buf),
        }
    }
}

impl Write for Conn {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            #[cfg(unix)]
            Conn::Unix(s) => s.write(buf),
            Conn::Tcp(s) => s.write(buf),
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            #[cfg(unix)]
            Conn::Unix(s) => s.flush(),
            Conn::Tcp(s) => s.flush(),
        }
    }
}

/// Abre a conexão com o app pelo transporte da plataforma. `Ok(None)` = as envs
/// não estão setadas (não estamos dentro de um terminal do Cockpit).
/// Flavor assado no binário pelo build (ver `build.rs`). `Some("debug")` no
/// build de desenvolvimento.
const FLAVOR: Option<&str> = option_env!("COCKPIT_FLAVOR");

/// Sockets a tentar, em ordem: o do ambiente (injetado pelo app na PTY da aba)
/// e, como fallback, os caminhos bem conhecidos.
///
/// O fallback é o que permite usar a CLI **de fora** de um terminal do Cockpit
/// (ex.: uma ferramenta de ditado chamando `cockpit send --focused`), onde não
/// existe env nenhuma herdada.
///
/// Release e debug têm sockets separados de propósito (um Cockpit de dev e um
/// instalado rodam lado a lado), então a ordem importa: **o socket do próprio
/// flavor vem primeiro**. Com os dois apps abertos, a CLI de dev era atendida
/// pelo app instalado, que pode ser bem mais velho — deu "tab @focused does not
/// exist" porque aquele app nem conhecia o sentinela. O outro flavor continua
/// como fallback: melhor falar com o app errado do que não falar com nenhum.
fn transport_home_from(isolated: Option<String>, home: Option<String>) -> Option<String> {
    match isolated {
        Some(root) => {
            let root = root.trim();
            std::path::Path::new(root)
                .is_absolute()
                .then(|| root.to_owned())
        }
        None => home,
    }
}

fn transport_home() -> Option<String> {
    transport_home_from(
        env_non_empty("COCKPIT_ISOLATED_ROOT"),
        crate::util::home_dir(),
    )
}

#[cfg(unix)]
fn candidate_sockets() -> Vec<String> {
    let mut out = Vec::new();
    if let Some(path) = env_non_empty("COCKPIT_STATUS_SOCK") {
        out.push(path);
    }
    if let Some(home) = transport_home() {
        let release = format!("{home}/.cockpit/status.sock");
        let debug = format!("{home}/.cockpit/status-debug.sock");
        if FLAVOR == Some("debug") {
            out.push(debug);
            out.push(release);
        } else {
            out.push(release);
            out.push(debug);
        }
    }
    out
}

/// Windows: `{port, tok}` que o app grava em `~/.cockpit/status[-debug].json`
/// ao subir — o equivalente do caminho bem conhecido do socket Unix, pra CLI
/// rodada de FORA de uma aba (sem env herdada). Mesma ordem de flavor do POSIX.
#[cfg(windows)]
fn endpoint_from_file() -> Option<(u16, Option<String>)> {
    let home = transport_home()?;
    let mut names = vec!["status.json", "status-debug.json"];
    if FLAVOR == Some("debug") {
        names.reverse();
    }
    for name in names {
        let path = format!("{home}\\.cockpit\\{name}");
        let Ok(raw) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Ok(v) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        let Some(port) = v.get("port").and_then(Value::as_u64) else {
            continue;
        };
        let tok = v.get("tok").and_then(Value::as_str).map(str::to_string);
        return Some((port as u16, tok));
    }
    None
}

#[cfg(not(windows))]
fn endpoint_from_file() -> Option<(u16, Option<String>)> {
    None
}

fn connect() -> Result<Option<Conn>, String> {
    let mut port = env_non_empty("COCKPIT_STATUS_PORT").and_then(|p| p.parse::<u16>().ok());
    if port.is_none() {
        port = endpoint_from_file().map(|(p, _)| p);
    }

    #[cfg(unix)]
    {
        let candidates = candidate_sockets();
        let mut last_err: Option<String> = None;
        for path in &candidates {
            // Socket órfão (app fechado sem limpar) existe no disco mas recusa
            // conexão — por isso quem decide é o connect, não o exists.
            match std::os::unix::net::UnixStream::connect(path) {
                Ok(s) => return Ok(Some(Conn::Unix(s))),
                Err(e) => last_err = Some(e.to_string()),
            }
        }
        if port.is_none() {
            return match last_err {
                Some(e) => Err(e),
                None => Ok(None),
            };
        }
    }

    if let Some(port) = port {
        return std::net::TcpStream::connect(("127.0.0.1", port))
            .map(|s| Some(Conn::Tcp(s)))
            .map_err(|e| e.to_string());
    }
    Ok(None)
}

/// `true` quando há algum caminho possível até o app (env de socket, porta, ou
/// um socket bem conhecido no disco).
pub fn transport_configured() -> bool {
    if env_non_empty("COCKPIT_STATUS_SOCK").is_some()
        || env_non_empty("COCKPIT_STATUS_PORT")
            .and_then(|p| p.parse::<u16>().ok())
            .is_some()
    {
        return true;
    }
    #[cfg(unix)]
    {
        candidate_sockets()
            .iter()
            .any(|p| std::path::Path::new(p).exists())
    }
    #[cfg(not(unix))]
    endpoint_from_file().is_some()
}

/// Native Windows forwarding runs before a Flutter engine exists. Unlike a
/// terminal command it must ignore inherited caller/socket env and never try
/// another flavor or another user's live instance.
pub fn forward_native_open(flavor: &str, arguments: &[String]) -> bool {
    let suffix = match flavor {
        "debug" => "-debug",
        "release" => "",
        _ => return false,
    };
    let Some(home) = transport_home() else {
        return false;
    };
    let endpoint = std::path::Path::new(&home)
        .join(".cockpit")
        .join(format!("status{suffix}.json"));
    let Ok(cwd) = std::env::current_dir() else {
        return false;
    };
    let files: Vec<String> = arguments
        .iter()
        .filter_map(|raw| {
            if raw.is_empty() || raw.starts_with('-') {
                return None;
            }
            let path = cwd.join(raw);
            (path.is_file() || path.is_dir()).then(|| path.to_string_lossy().into_owned())
        })
        .collect();
    if files.is_empty() {
        return false;
    }
    forward_native_open_at(&endpoint, &files)
}

fn forward_native_open_at(endpoint: &std::path::Path, files: &[String]) -> bool {
    use std::net::{Ipv4Addr, SocketAddr, TcpStream};
    use std::time::Instant;
    let attempt = || -> Option<bool> {
        let mut raw = String::new();
        std::fs::File::open(endpoint)
            .ok()?
            .take(64 * 1024)
            .read_to_string(&mut raw)
            .ok()?;
        let metadata: Value = serde_json::from_str(&raw).ok()?;
        let port = u16::try_from(metadata.get("port")?.as_u64()?).ok()?;
        let token = metadata.get("tok")?.as_str()?;
        if port == 0 || token.is_empty() || files.is_empty() {
            return None;
        }
        let address = SocketAddr::new(Ipv4Addr::LOCALHOST.into(), port);
        let mut stream = TcpStream::connect_timeout(&address, Duration::from_secs(2)).ok()?;
        stream
            .set_write_timeout(Some(Duration::from_secs(2)))
            .ok()?;
        let request = json!({"type":"cmd", "cmd":"open-document", "tok":token,
            "args":{"paths":files}});
        writeln!(stream, "{request}").ok()?;
        stream.flush().ok()?;
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut response = Vec::new();
        let mut chunk = [0_u8; 4096];
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return None;
            }
            stream.set_read_timeout(Some(remaining)).ok()?;
            let count = stream.read(&mut chunk).ok()?;
            if count == 0 {
                return None;
            }
            response.extend_from_slice(&chunk[..count]);
            if response.len() > 64 * 1024 {
                return None;
            }
            if let Some(end) = response.iter().position(|byte| *byte == b'\n') {
                let result: Value = serde_json::from_slice(&response[..end]).ok()?;
                return Some(result.get("ok") == Some(&Value::Bool(true)));
            }
        }
    };
    attempt().unwrap_or(false)
}

/// Envia uma requisição e devolve a resposta decodificada.
///
/// Fora de um terminal do Cockpit, encerra com exit 3 (mesma mensagem da CLI
/// Dart). Falha de rede também é exit 3; resposta ausente/malformada vira um
/// `{"ok": false, "error": …}` pro chamador tratar como erro de aplicação.
pub fn request(mut req: Value, timeout: Duration) -> Value {
    if !transport_configured() {
        die(
            "cockpit: no Cockpit app to talk to (COCKPIT_STATUS_SOCK is unset and \
no socket found in ~/.cockpit). Is the app running?",
            3,
        );
    }
    req["type"] = json!("cmd");
    if let Some(caller) = crate::util::self_tab_id() {
        req["callerTabId"] = json!(caller);
    }
    if let Ok(tok) = std::env::var("COCKPIT_STATUS_TOKEN") {
        req["tok"] = json!(tok);
    } else if let Some((_, Some(tok))) = endpoint_from_file() {
        req["tok"] = json!(tok);
    }

    let mut conn = match connect() {
        Ok(Some(c)) => c,
        Ok(None) => die(
            "cockpit: not inside a Cockpit terminal (COCKPIT_STATUS_SOCK is unset)",
            3,
        ),
        Err(e) => die(&format!("cockpit: could not connect to app: {e}"), 3),
    };
    let _ = conn.set_read_timeout(timeout);

    let mut payload = req.to_string();
    payload.push('\n');
    if let Err(e) = conn
        .write_all(payload.as_bytes())
        .and_then(|_| conn.flush())
    {
        die(&format!("cockpit: could not connect to app: {e}"), 3);
    }

    // O servidor responde UMA linha e fecha. Lemos até a primeira quebra (ou
    // até o EOF), o que também nos protege se ele mantiver a conexão aberta.
    let mut buf: Vec<u8> = Vec::with_capacity(4096);
    let mut chunk = [0u8; 4096];
    loop {
        match conn.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                if buf.contains(&b'\n') {
                    break;
                }
            }
            Err(_) => break, // timeout ou erro: trata como resposta ausente
        }
    }

    let raw = String::from_utf8_lossy(&buf);
    let line = raw.trim();
    if line.is_empty() {
        return json!({"ok": false, "error": "no response from app"});
    }
    match serde_json::from_str::<Value>(line) {
        Ok(v) if v.is_object() => v,
        Ok(_) => json!({"ok": false, "error": "malformed response"}),
        Err(_) => json!({"ok": false, "error": "malformed response"}),
    }
}

/// `resp["ok"] == true`. Emite no **stderr** o aviso que a resposta trouxer.
///
/// Aviso vai pro stderr de propósito: o stdout dos comandos de banco é uma
/// linha JSON que agentes parseiam, e sujá-la quebraria o contrato. Hoje o
/// único caso é `--workspace` mirando outra máquina — a execução está certa,
/// mas o resultado tem cara de ser da máquina onde o comando foi digitado.
pub fn is_ok(resp: &Value) -> bool {
    if let Some(Value::String(w)) = resp.get("warning") {
        eprintln!("cockpit: {w}");
    }
    resp.get("ok") == Some(&Value::Bool(true))
}

/// Mensagem de erro da resposta, com o mesmo fallback da CLI Dart.
pub fn error_text(resp: &Value) -> String {
    match resp.get("error") {
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
        None => "failed".to_string(),
    }
}

/// Encerra com o erro da resposta (exit 1) — padrão dos comandos "simples".
pub fn fail_with(resp: &Value) -> ! {
    die(&format!("cockpit: {}", error_text(resp)), 1)
}

#[cfg(test)]
mod runtime_namespace_tests {
    use super::transport_home_from;
    #[test]
    fn invalid_isolated_root_never_falls_back_to_user_home() {
        assert_eq!(
            transport_home_from(Some("relative/path".into()), Some("real-home".into())),
            None
        );
    }
    #[test]
    fn absent_isolation_preserves_the_normal_home() {
        assert_eq!(
            transport_home_from(None, Some("real-home".into())),
            Some("real-home".into())
        );
    }
    #[test]
    fn absolute_isolated_root_replaces_only_transport_discovery() {
        let root = std::env::temp_dir().to_string_lossy().to_string();
        assert_eq!(
            transport_home_from(Some(format!("  {root}  ")), Some("real-home".into())),
            Some(root)
        );
    }
}
