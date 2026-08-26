//! Os verbos da CLI. Porte fiel do `tool/cockpit_cli.dart`: mesmos comandos de
//! wire, mesmas mensagens de erro, mesmos exit codes e mesmo layout de saída.

use std::time::Duration;

use base64::Engine as _;
use serde_json::{json, Map, Value};

use crate::flags::Flags;
use crate::keys;
use crate::transport::{self, fail_with, is_ok};
use crate::util::{basename, die, pad, resolve_path, self_tab_id};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
/// Timeout folgado: o app corta a query em 30s; a folga cobre fila + IO.
const DB_TIMEOUT: Duration = Duration::from_secs(60);

fn b64() -> base64::engine::general_purpose::GeneralPurpose {
    base64::engine::general_purpose::STANDARD
}

/// Anexa `tabId` na requisição quando há alvo (flag ou tab emissora).
fn with_tab_id(req: &mut Value, tab_id: Option<String>) {
    if let Some(id) = tab_id {
        if !id.is_empty() {
            req["tabId"] = json!(id);
        }
    }
}

// ---- send / send-key / write ------------------------------------------------

pub fn send(args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    let text = parsed.positionals.join(" ");
    if text.is_empty() {
        die("cockpit send: missing text to send", 2);
    }
    let tab_id = resolve_target(parsed.effective_tab_id());
    write_once(&tab_id, &text);
    // `--enter` manda o Enter numa SEGUNDA escrita, não um `\r` colado no fim do
    // texto. É de propósito: TUIs (o claude entre elas) distinguem "digitou e
    // submeteu" de "colou um bloco com quebra de linha", e um write único com o
    // CR embutido cai no segundo caso. Duas escritas é exatamente o que a gente
    // já fazia à mão com `send` + `send-key Enter` — a flag só evita a segunda
    // chamada. A resposta da primeira é aguardada antes da segunda, então a
    // ordem é garantida.
    if parsed.enter {
        write_once(&tab_id, "\r");
    }
    std::process::exit(0)
}

pub fn send_key(args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    if parsed.positionals.is_empty() {
        die("cockpit send-key: missing key (e.g. Enter, C-c, Escape)", 2);
    }
    let mut buf = String::new();
    for name in &parsed.positionals {
        match keys::resolve(name) {
            Some(seq) => buf.push_str(&seq),
            None => die(&format!("cockpit send-key: unknown key \"{name}\""), 2),
        }
    }
    write_to_tab(parsed.effective_tab_id(), &buf)
}

fn write_to_tab(tab_id: Option<String>, text: &str) -> ! {
    let tab_id = resolve_target(tab_id);
    write_once(&tab_id, text);
    std::process::exit(0)
}

/// Alvo efetivo, ou encerra explicando. Nunca chuta uma aba: sem `--tab-id` e
/// fora de um terminal do Cockpit (onde o app injeta `COCKPIT_TAB_ID`), digitar
/// num pane arbitrário seria pior que falhar.
fn resolve_target(tab_id: Option<String>) -> String {
    match tab_id {
        Some(id) if !id.is_empty() => id,
        _ => die(
            "cockpit: no target — pass --tab-id <id> or run inside a Cockpit \
terminal (COCKPIT_TAB_ID is unset). Use `cockpit list-tabs`.",
            2,
        ),
    }
}

/// Uma escrita na PTY da aba. Encerra com exit 1 se o app recusar.
fn write_once(tab_id: &str, text: &str) {
    let resp = transport::request(
        json!({
            "cmd": "write",
            "tabId": tab_id,
            "args": {"data": b64().encode(text.as_bytes())},
        }),
        DEFAULT_TIMEOUT,
    );
    if !is_ok(&resp) {
        fail_with(&resp);
    }
}

// ---- open -------------------------------------------------------------------

pub fn open(args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    if parsed.positionals.is_empty() {
        die("cockpit open: missing file path", 2);
    }
    // O app tem cwd próprio — resolve pro caminho absoluto no cwd desta tab
    // (onde a CLI está rodando) antes de mandar.
    let abs = resolve_path(&parsed.positionals[0]);
    let mut req = json!({"cmd": "open", "args": {"path": abs}});
    with_tab_id(&mut req, parsed.effective_tab_id());
    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    std::process::exit(0)
}

// ---- new-tab ----------------------------------------------------------------

const NEW_TAB_HELP: &str = "cockpit new-tab [--cwd <dir>] [--title <name>] [--split h|v]
  --cwd    working directory (default: current directory)
  --title  stable tab label (read-tab/send can target it)
  --split  h|right = side by side, v|down = stacked; omit = new tab
           in the same pane
  Prints the new tab id (e.g. t12).";

pub fn new_tab(args: &[String]) -> ! {
    let mut cwd: Option<String> = None;
    let mut title: Option<String> = None;
    let mut split: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut as_json = false;

    let mut i = 0usize;
    while i < args.len() {
        let a = args[i].as_str();
        if a == "--help" || a == "-h" {
            println!("{NEW_TAB_HELP}");
            std::process::exit(0);
        }
        if a == "--json" {
            as_json = true;
            i += 1;
            continue;
        }
        if let Some((flag, value)) =
            take(args, &mut i, &["--cwd", "--title", "--split", "--tab-id"])
        {
            match flag {
                "--cwd" => cwd = value,
                "--title" => title = value,
                "--split" => split = value,
                _ => tab_id = value,
            }
        }
        i += 1;
    }

    let wire_split = match split.as_deref().map(|s| s.to_lowercase()) {
        None => None,
        Some(ref s) if s == "h" || s == "horizontal" || s == "right" => Some("right"),
        Some(ref s) if s == "v" || s == "vertical" || s == "down" => Some("down"),
        Some(_) => die(
            &format!(
                "cockpit new-tab: invalid --split \"{}\" (use h|right or v|down)",
                split.unwrap_or_default()
            ),
            2,
        ),
    };

    let cwd = resolve_path(&cwd.unwrap_or_else(|| {
        std::env::current_dir()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|_| ".".to_string())
    }));
    let mut cmd_args = Map::new();
    cmd_args.insert("cwd".into(), json!(cwd));
    if let Some(t) = title.filter(|t| !t.is_empty()) {
        cmd_args.insert("title".into(), json!(t));
    }
    if let Some(s) = wire_split {
        cmd_args.insert("split".into(), json!(s));
    }

    let mut req = json!({"cmd": "new-tab", "args": Value::Object(cmd_args)});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    let data = resp.get("data").cloned().unwrap_or_else(|| json!({}));
    if as_json {
        println!("{}", data);
    } else {
        let id = data.get("tabId").and_then(|v| v.as_str()).unwrap_or("");
        println!("{id}");
    }
    std::process::exit(0)
}

// ---- browse -----------------------------------------------------------------

const BROWSE_HELP: &str = "cockpit browse <url> [--json]
  Opens the built-in browser tab at <url> (reuses a browser tab already
  open on the same host:port). On platforms without an inline webview
  (Linux) the app opens the URL in the system browser instead.
  --tab-id <id>  route to another tab's workspace (default: this tab)";

pub fn browse_url(args: &[String]) -> ! {
    let mut url: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut as_json = false;

    let mut i = 0usize;
    while i < args.len() {
        let a = args[i].as_str();
        if a == "--help" || a == "-h" {
            println!("{BROWSE_HELP}");
            std::process::exit(0);
        }
        if a == "--json" {
            as_json = true;
            i += 1;
            continue;
        }
        if let Some((_, value)) = take(args, &mut i, &["--tab-id"]) {
            tab_id = value;
        } else if url.is_none() {
            url = Some(a.to_string());
        }
        i += 1;
    }

    let Some(url) = url.filter(|u| !u.is_empty()) else {
        die(&format!("cockpit browse: missing <url>\n\n{BROWSE_HELP}"), 2)
    };

    let mut cmd_args = Map::new();
    cmd_args.insert("url".into(), json!(url));
    let mut req = json!({"cmd": "browse", "args": Value::Object(cmd_args)});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    let data = resp.get("data").cloned().unwrap_or_else(|| json!({}));
    if as_json {
        println!("{}", data);
    } else {
        println!("ok");
    }
    std::process::exit(0)
}

// ---- browser (plano 61) ------------------------------------------------------

/// Kinds estáveis dos erros de `browser *` — mesma reconstrução do
/// `{"error":{kind,message}}` que [DB_ERROR_KINDS] faz pra `db`/`redis`/`mongo`.
const BROWSER_ERROR_KINDS: [&str; 5] = [
    "no_browser_tab",
    "tab_closed",
    "stale_element_id",
    "eval_failed",
    "ambiguous_browser_tab",
];

const BROWSER_HELP: &str = "cockpit browser <read|click|type|screenshot|eval> [args...]
  Controls the inline browser tab via injected JS (no OS-level click/type —
  synthetic events are NOT `isTrusted`). Targets the workspace's single open
  browser tab by default; pass --tab-id <id> (from `cockpit list-tabs`, kind
  \"browser\") to address a specific one when more than one is open.

cockpit browser read [--full] [--tab-id <id>] [--workspace <id|path>]
  Lists visible interactive elements: [{id, role, text, rect}, ...].
  --full  also include hidden/off-screen elements (debug).
  Element ids are ephemeral — valid only against the most recent `read` of
  that tab; a new `read` (or a page navigation) invalidates old ids.

cockpit browser click <id> [--tab-id <id>] [--workspace <id|path>]
  Dispatches a synthetic click on the element from the last `read`.

cockpit browser type <id> <text> [--tab-id <id>] [--workspace <id|path>]
  Focuses the element and sets its value/textContent (input+change fired).
  Works on input/textarea/contenteditable.

cockpit browser screenshot [--out <path>] [--tab-id <id>] [--workspace <id|path>]
  Without --out, prints the PNG as base64. With --out, writes the PNG to
  <path> (resolved from the CLI's cwd) and prints the path.

cockpit browser eval <js> [--tab-id <id>] [--workspace <id|path>]
  Escape hatch: runs <js> and returns the serializable result. Last resort —
  read/click/type cover the common case without hand-written selectors.

Output: one JSON line `{\"ok\": <data>}` on success, or
`{\"error\":{\"kind\",\"message\"}}` (exit 1) — kinds: no_browser_tab,
tab_closed, stale_element_id, eval_failed, ambiguous_browser_tab.";

pub fn browser(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        if args.is_empty() {
            eprintln!("{BROWSER_HELP}");
            std::process::exit(2);
        }
        println!("{BROWSER_HELP}");
        std::process::exit(0);
    }
    let sub = args[0].clone();
    let rest = &args[1..];

    let mut tab_id: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut full = false;
    let mut out: Option<String> = None;
    let mut positionals: Vec<String> = Vec::new();
    let mut pending: Option<String> = None;

    const VALUE_FLAGS: [&str; 3] = ["--tab-id", "--workspace", "--out"];

    for a in rest {
        if let Some(flag) = pending.take() {
            match flag.as_str() {
                "--tab-id" => tab_id = Some(a.clone()),
                "--workspace" => workspace = Some(a.clone()),
                "--out" => out = Some(a.clone()),
                _ => {}
            }
            continue;
        }
        if a == "--full" {
            full = true;
            continue;
        }
        if VALUE_FLAGS.contains(&a.as_str()) {
            pending = Some(a.clone());
            continue;
        }
        if let Some(eq) = a.find('=') {
            if a.starts_with("--") && eq > 0 {
                let (key, value) = a.split_at(eq);
                let value = value[1..].to_string();
                match key {
                    "--tab-id" => tab_id = Some(value),
                    "--workspace" => workspace = Some(value),
                    "--out" => out = Some(value),
                    _ => db_fail(
                        "error",
                        &format!("unknown flag \"{key}\" (see `cockpit browser --help`)"),
                    ),
                }
                continue;
            }
        }
        positionals.push(a.clone());
    }
    if let Some(flag) = pending {
        db_fail("error", &format!("missing value for {flag}"));
    }

    let mut cmd_args = Map::new();
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    let wire = match sub.as_str() {
        "read" => {
            cmd_args.insert("full".into(), json!(full));
            "browser-read"
        }
        "click" => {
            if positionals.is_empty() {
                db_fail("error", "missing <id> (see `cockpit browser read`)");
            }
            cmd_args.insert("id".into(), json!(positionals[0]));
            "browser-click"
        }
        "type" => {
            if positionals.is_empty() {
                db_fail("error", "missing <id> (see `cockpit browser read`)");
            }
            let id = positionals[0].clone();
            let text = positionals[1..].join(" ");
            cmd_args.insert("id".into(), json!(id));
            cmd_args.insert("text".into(), json!(text));
            "browser-type"
        }
        "screenshot" => {
            if let Some(p) = out {
                cmd_args.insert("out".into(), json!(resolve_path(&p)));
            }
            "browser-screenshot"
        }
        "eval" => {
            if positionals.is_empty() {
                db_fail("error", "missing <js>");
            }
            cmd_args.insert("js".into(), json!(positionals.join(" ")));
            "browser-eval"
        }
        other => db_fail(
            "error",
            &format!("unknown subcommand \"{other}\" (see `cockpit browser --help`)"),
        ),
    };

    browser_request(wire, cmd_args, tab_id)
}

/// Envia um comando de navegador e imprime `{"ok": …}` / `{"error": …}`
/// (mesmo contrato do [nosql_request], kinds diferentes).
fn browser_request(wire: &str, cmd_args: Map<String, Value>, tab_id: Option<String>) -> ! {
    let mut req = json!({"cmd": wire, "args": Value::Object(cmd_args)});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DB_TIMEOUT);
    if is_ok(&resp) {
        let data = resp.get("data").cloned().unwrap_or(Value::Null);
        println!("{}", json!({"ok": data}));
        std::process::exit(0);
    }
    let raw = transport::error_text(&resp);
    if let Some(sep) = raw.find(": ") {
        if sep > 0 {
            let kind = &raw[..sep];
            if BROWSER_ERROR_KINDS.contains(&kind) {
                db_fail(kind, &raw[sep + 2..]);
            }
        }
    }
    db_fail("error", &raw)
}

// ---- orchestrate ------------------------------------------------------------

const ORCHESTRATE_HELP: &str = "cockpit orchestrate <file.ckp> [--json]
  Applies a .ckp pane layout to the current workspace.
  Panes whose name already exists as a tab label are skipped.";

pub fn orchestrate(args: &[String]) -> ! {
    let mut file: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut as_json = false;

    let mut i = 0usize;
    while i < args.len() {
        let a = args[i].as_str();
        if a == "--help" || a == "-h" {
            println!("{ORCHESTRATE_HELP}");
            std::process::exit(0);
        }
        if a == "--json" {
            as_json = true;
        } else if a == "--tab-id" {
            i += 1;
            tab_id = args.get(i).cloned();
        } else if let Some(v) = a.strip_prefix("--tab-id=") {
            tab_id = Some(v.to_string());
        } else if !a.starts_with('-') {
            file = Some(a.to_string());
        }
        i += 1;
    }

    let file = match file {
        Some(f) if !f.is_empty() => f,
        _ => die("cockpit orchestrate: missing <file.ckp>", 2),
    };
    let mut req = json!({"cmd": "orchestrate", "args": {"path": resolve_path(&file)}});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    let data = resp.get("data").cloned().unwrap_or_else(|| json!({}));
    if as_json {
        println!("{}", data);
    } else {
        let created = join_list(&data, "created");
        let skipped = join_list(&data, "skipped");
        println!(
            "created: {}",
            if created.is_empty() {
                "(none)"
            } else {
                &created
            }
        );
        if !skipped.is_empty() {
            println!("skipped: {skipped}");
        }
    }
    std::process::exit(0)
}

fn join_list(data: &Value, key: &str) -> String {
    match data.get(key).and_then(|v| v.as_array()) {
        Some(items) => items
            .iter()
            .map(value_to_display)
            .collect::<Vec<_>>()
            .join(", "),
        None => String::new(),
    }
}

// ---- list-* -----------------------------------------------------------------

pub fn list(cmd: &str, args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    let mut req = json!({"cmd": cmd});
    // `list-tasks` lista as tasks do workspace da tab emissora (ou da
    // `--tab-id` passada); os outros list-* ignoram o campo — mandar sempre é
    // inofensivo.
    with_tab_id(&mut req, parsed.effective_tab_id());
    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    let empty: Vec<Value> = Vec::new();
    let data = resp
        .get("data")
        .and_then(|v| v.as_array())
        .unwrap_or(&empty)
        .clone();

    if parsed.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&Value::Array(data)).unwrap_or_else(|_| "[]".into())
        );
        std::process::exit(0);
    }
    if data.is_empty() {
        println!("(none)");
        std::process::exit(0);
    }
    for line in format_list(cmd, &data) {
        println!("{line}");
    }
    std::process::exit(0)
}

/// Formata a lista pro olho humano. Separado do IO pra ser testável.
pub fn format_list(cmd: &str, data: &[Value]) -> Vec<String> {
    let mut out = Vec::with_capacity(data.len());
    for e in data {
        if !e.is_object() {
            continue;
        }
        match cmd {
            // (comando de wire estável; a superfície é `list-tabs`)
            "list-panes" => {
                let flag = if e.get("working") == Some(&Value::Bool(true)) {
                    "●"
                } else {
                    " "
                };
                // Rótulo manual (nome estável) vence o título dinâmico; `⚲`
                // sinaliza que está travado. Sem rótulo, mostra o título
                // automático.
                let label = e.get("label").and_then(|v| v.as_str()).unwrap_or("");
                let name = if !label.is_empty() {
                    format!("⚲ {label}")
                } else {
                    field(e, "title")
                };
                // Workspace: basename do path (legível) — o `workspaceId` virou
                // UUID opaco. `workspacePath` ausente = app antigo → mostra o id.
                let ws_path = field(e, "workspacePath");
                let ws = if !ws_path.is_empty() {
                    basename(&ws_path)
                } else {
                    field(e, "workspaceId")
                };
                out.push(format!(
                    "{flag} {} {} {} {name}",
                    pad(&field(e, "id"), 6),
                    pad(&field(e, "kind"), 9),
                    pad(&ws, 14)
                ));
            }
            "list-tasks" => {
                let flag = if e.get("running") == Some(&Value::Bool(true)) {
                    "●"
                } else {
                    " "
                };
                // `[output]` = já rodou neste boot → `read-task <id>` tem o que ler.
                let has_output = if e.get("hasOutput") == Some(&Value::Bool(true)) {
                    "  [output]"
                } else {
                    ""
                };
                out.push(format!(
                    "{flag} {} {} {}{has_output}",
                    pad(&field(e, "id"), 16),
                    pad(&field(e, "source"), 9),
                    field(e, "label")
                ));
            }
            _ => {
                // `tabs` é o campo novo; `panes` fica como fallback (app antigo).
                let n = e
                    .get("tabs")
                    .or_else(|| e.get("panes"))
                    .map(value_to_display)
                    .unwrap_or_else(|| "0".to_string());
                // Nome + path (o `id` virou UUID opaco e não é endereçável pela
                // CLI — no JSON ele continua íntegro pra quem precisar).
                out.push(format!(
                    "{} {} {}",
                    pad(&field(e, "name"), 18),
                    pad(&format!("{n} tabs"), 9),
                    field(e, "path")
                ));
            }
        }
    }
    out
}

/// Campo do objeto como texto, com `""` quando ausente/nulo (igual ao
/// `(x ?? '').toString()` do Dart).
fn field(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::Null) | None => String::new(),
        Some(x) => value_to_display(x),
    }
}

/// Representação textual de um valor JSON como o Dart faria em `toString()`
/// (string sem aspas; número/bool crus).
fn value_to_display(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

// ---- read-tab / read-task ---------------------------------------------------

pub fn read(cmd: &str, args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    let target = parsed.positionals.first().cloned().unwrap_or_default();
    if cmd == "read-task" && target.is_empty() {
        die("cockpit read-task: missing task id", 2);
    }
    let mut cmd_args = Map::new();
    if !target.is_empty() {
        cmd_args.insert("target".into(), json!(target));
    }
    if let Some(n) = parsed.lines {
        cmd_args.insert("lines".into(), json!(n));
    }
    if let Some(n) = parsed.offset {
        cmd_args.insert("offset".into(), json!(n));
    }
    if parsed.from_start {
        cmd_args.insert("fromStart".into(), json!(true));
    }
    let mut req = json!({"cmd": cmd, "args": Value::Object(cmd_args)});
    // Sem alvo posicional, o server cai na própria tab ($COCKPIT_TAB_ID).
    with_tab_id(&mut req, parsed.effective_tab_id());

    let resp = transport::request(req, DEFAULT_TIMEOUT);
    if !is_ok(&resp) {
        fail_with(&resp);
    }
    let data = resp.get("data").cloned().unwrap_or_else(|| json!({}));
    let encoded = field(&data, "text");
    let text = match b64().decode(encoded.as_bytes()) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(s) => s,
            Err(_) => die("cockpit: malformed payload", 1),
        },
        Err(_) => die("cockpit: malformed payload", 1),
    };
    if !text.is_empty() {
        println!("{text}");
    }
    if data.get("truncated") == Some(&Value::Bool(true)) {
        eprintln!("cockpit: output truncated (server cap 2000 lines/read — page with --offset)");
    }
    std::process::exit(0)
}

// ---- db (plano 51) ----------------------------------------------------------

/// Kinds estáveis que o app devolve prefixados em `fail("<kind>: <msg>")` —
/// reconstruímos o JSON `{"error":{kind,message}}` do contrato da CLI.
const DB_ERROR_KINDS: [&str; 7] = [
    "connection_failed",
    "query_failed",
    "timeout",
    "unsupported_engine",
    "unknown_connection",
    "password_required",
    "read_only_connection",
];

const DB_HELP: &str = include_str!("../text/db_help.txt");

/// Encerra com o contrato de erro da CLI: uma linha JSON no **stdout**, exit 1.
pub fn db_fail(kind: &str, message: &str) -> ! {
    println!("{}", json!({"error": {"kind": kind, "message": message}}));
    std::process::exit(1)
}

pub fn db(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        if args.is_empty() {
            eprint!("{DB_HELP}");
            std::process::exit(2);
        }
        print!("{DB_HELP}");
        std::process::exit(0);
    }
    let sub = args[0].clone();
    let rest = &args[1..];

    let mut db_name: Option<String> = None;
    let mut sql: Option<String> = None;
    let mut limit: Option<String> = None;
    let mut table: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut positionals: Vec<String> = Vec::new();
    let mut pending: Option<String> = None;

    const VALUE_FLAGS: [&str; 6] = [
        "--db",
        "--sql",
        "--limit",
        "--table",
        "--workspace",
        "--tab-id",
    ];

    for a in rest {
        if let Some(flag) = pending.take() {
            match flag.as_str() {
                "--db" => db_name = Some(a.clone()),
                "--sql" => sql = Some(a.clone()),
                "--limit" => limit = Some(a.clone()),
                "--table" => table = Some(a.clone()),
                "--workspace" => workspace = Some(a.clone()),
                "--tab-id" => tab_id = Some(a.clone()),
                _ => {}
            }
            continue;
        }
        if VALUE_FLAGS.contains(&a.as_str()) {
            pending = Some(a.clone());
            continue;
        }
        if let Some(eq) = a.find('=') {
            if a.starts_with("--") && eq > 0 {
                let (key, value) = a.split_at(eq);
                let value = value[1..].to_string();
                match key {
                    "--db" => db_name = Some(value),
                    "--sql" => sql = Some(value),
                    "--limit" => limit = Some(value),
                    "--table" => table = Some(value),
                    "--workspace" => workspace = Some(value),
                    "--tab-id" => tab_id = Some(value),
                    _ => db_fail(
                        "error",
                        &format!("unknown flag \"{key}\" (see `cockpit db --help`)"),
                    ),
                }
                continue;
            }
        }
        positionals.push(a.clone());
    }
    if let Some(flag) = pending {
        db_fail("error", &format!("missing value for {flag}"));
    }

    let mut cmd_args = Map::new();
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    let wire = match sub.as_str() {
        "list" => "db-list",
        "schema" => {
            let name = db_name
                .clone()
                .unwrap_or_else(|| db_fail("error", "missing --db <name>"));
            cmd_args.insert("db".into(), json!(name));
            let t = table.or_else(|| positionals.first().cloned());
            if let Some(t) = t {
                cmd_args.insert("table".into(), json!(t));
            }
            "db-schema"
        }
        "query" | "execute" => {
            let name = db_name
                .clone()
                .unwrap_or_else(|| db_fail("error", "missing --db <name>"));
            let statement = sql.clone().unwrap_or_else(|| positionals.join(" "));
            if statement.trim().is_empty() {
                db_fail("error", "missing --sql \"<statement>\"");
            }
            cmd_args.insert("db".into(), json!(name));
            cmd_args.insert("sql".into(), json!(statement));
            if let Some(l) = limit {
                cmd_args.insert("limit".into(), json!(l));
            }
            if sub == "query" {
                "db-query"
            } else {
                "db-execute"
            }
        }
        "run" => {
            if positionals.is_empty() {
                db_fail("error", "missing <file.dbq>");
            }
            cmd_args.insert("path".into(), json!(resolve_path(&positionals[0])));
            "db-run"
        }
        other => db_fail(
            "error",
            &format!("unknown subcommand \"{other}\" (see `cockpit db --help`)"),
        ),
    };

    nosql_request(wire, cmd_args, tab_id)
}

// ---- http -------------------------------------------------------------------

/// Kinds estáveis que o app devolve prefixados em `fail("<kind>: <msg>")`.
const HTTP_ERROR_KINDS: [&str; 7] = [
    "no_request",
    "invalid_url",
    "unresolved_variable",
    "body_file_unreadable",
    "connection_failed",
    "timeout",
    "response_too_large",
];

const HTTP_HELP: &str = include_str!("../text/http_help.txt");

pub fn http(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        if args.is_empty() {
            eprint!("{HTTP_HELP}");
            std::process::exit(2);
        }
        print!("{HTTP_HELP}");
        std::process::exit(0);
    }
    let sub = args[0].clone();
    let rest = &args[1..];

    let mut request: Option<String> = None;
    let mut timeout: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut positionals: Vec<String> = Vec::new();
    let mut pending: Option<String> = None;

    const VALUE_FLAGS: [&str; 4] = ["--request", "--timeout", "--workspace", "--tab-id"];

    for a in rest {
        if let Some(flag) = pending.take() {
            match flag.as_str() {
                "--request" => request = Some(a.clone()),
                "--timeout" => timeout = Some(a.clone()),
                "--workspace" => workspace = Some(a.clone()),
                "--tab-id" => tab_id = Some(a.clone()),
                _ => {}
            }
            continue;
        }
        if VALUE_FLAGS.contains(&a.as_str()) {
            pending = Some(a.clone());
            continue;
        }
        if let Some(eq) = a.find('=') {
            if a.starts_with("--") && eq > 0 {
                let (key, value) = a.split_at(eq);
                let value = value[1..].to_string();
                match key {
                    "--request" => request = Some(value),
                    "--timeout" => timeout = Some(value),
                    "--workspace" => workspace = Some(value),
                    "--tab-id" => tab_id = Some(value),
                    _ => db_fail(
                        "error",
                        &format!("unknown flag \"{key}\" (see `cockpit http --help`)"),
                    ),
                }
                continue;
            }
        }
        positionals.push(a.clone());
    }
    if let Some(flag) = pending {
        db_fail("error", &format!("missing value for {flag}"));
    }

    let mut cmd_args = Map::new();
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    if positionals.is_empty() {
        db_fail("error", "missing <file.http>");
    }
    cmd_args.insert("path".into(), json!(resolve_path(&positionals[0])));

    let wire = match sub.as_str() {
        "list" => "http-list",
        "run" => {
            if let Some(r) = request {
                cmd_args.insert("request".into(), json!(r));
            }
            if let Some(t) = timeout {
                cmd_args.insert("timeout".into(), json!(t));
            }
            "http-run"
        }
        other => db_fail(
            "error",
            &format!("unknown subcommand \"{other}\" (see `cockpit http --help`)"),
        ),
    };

    http_request(wire, cmd_args, tab_id)
}

/// Igual ao [`nosql_request`], com a lista de kinds do http.
fn http_request(wire: &str, cmd_args: Map<String, Value>, tab_id: Option<String>) -> ! {
    let mut req = json!({"cmd": wire, "args": Value::Object(cmd_args)});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DB_TIMEOUT);
    if is_ok(&resp) {
        let data = resp.get("data").cloned().unwrap_or(Value::Null);
        println!("{}", json!({"ok": data}));
        std::process::exit(0);
    }
    let raw = transport::error_text(&resp);
    if let Some(sep) = raw.find(": ") {
        if sep > 0 {
            let kind = &raw[..sep];
            if HTTP_ERROR_KINDS.contains(&kind) {
                db_fail(kind, &raw[sep + 2..]);
            }
        }
    }
    db_fail("error", &raw)
}

// ---- redis / mongo ----------------------------------------------------------

const REDIS_HELP: &str = "cockpit redis --db <conn> <COMMAND> [args...]
  e.g. cockpit redis --db cache GET session:42
  Output: one JSON line. Connection registered in the Database panel.
cockpit redis browse --db <conn> [--pattern 'user:*']
  Opens the key table in the app, pre-filtered. Opens a view — returns no data.";

pub fn redis(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        println!("{REDIS_HELP}");
        std::process::exit(if args.is_empty() { 2 } else { 0 });
    }
    if args[0] == "browse" {
        browse("redis-browse", &args[1..]);
    }
    let mut db_name: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut parts: Vec<String> = Vec::new();

    let mut i = 0usize;
    while i < args.len() {
        let a = args[i].as_str();
        if a == "--db" {
            i += 1;
            db_name = args.get(i).cloned();
        } else if let Some(v) = a.strip_prefix("--db=") {
            db_name = Some(v.to_string());
        } else if a == "--workspace" {
            i += 1;
            workspace = args.get(i).cloned();
        } else if let Some(v) = a.strip_prefix("--workspace=") {
            workspace = Some(v.to_string());
        } else if a == "--tab-id" {
            i += 1;
            tab_id = args.get(i).cloned();
        } else {
            parts.push(a.to_string());
        }
        i += 1;
    }
    let db_name = db_name.unwrap_or_else(|| db_fail("error", "missing --db <conn>"));
    if parts.is_empty() {
        db_fail("error", "missing Redis command");
    }
    let mut cmd_args = Map::new();
    cmd_args.insert("db".into(), json!(db_name));
    cmd_args.insert("parts".into(), json!(parts));
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    nosql_request("redis-cmd", cmd_args, tab_id)
}

const MONGO_HELP: &str = concat!(
    "cockpit mongo --db <conn> [--database <name>] --command '<json>'\n",
    "  e.g. cockpit mongo --db app --command '{\"find\":\"users\",\"filter\":{}}'\n",
    "  The command is a MongoDB runCommand document. Output: one JSON line.\n",
    "  --database <name>  which database to run against, for this call only.\n",
    "                     Needed when the connection URL has no database in\n",
    "                     its path (typical of Atlas, mongodb+srv://…/?…).\n",
    "                     Omitted, the database picked in the app panel is\n",
    "                     used; if none was ever picked, the command fails\n",
    "                     and lists the databases available.\n",
    "                     List them anytime with --command '{\"listDatabases\":1}'.\n",
    "cockpit mongo browse --db <conn> [--database <name>] <collection> [--filter '<json>']\n",
    "  Opens the collection browser in the app, pre-filtered. Opens a view — returns no documents.\n",
    "  Here --database also becomes the connection's current database (the tab is what the human sees)."
);

pub fn mongo(args: &[String]) -> ! {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        println!("{MONGO_HELP}");
        std::process::exit(if args.is_empty() { 2 } else { 0 });
    }
    if args[0] == "browse" {
        browse("mongo-browse", &args[1..]);
    }
    let mut db_name: Option<String> = None;
    let mut database: Option<String> = None;
    let mut command: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut tab_id: Option<String> = None;

    let mut i = 0usize;
    while i < args.len() {
        if let Some((flag, value)) = take(
            args,
            &mut i,
            &["--db", "--database", "--command", "--workspace", "--tab-id"],
        ) {
            match flag {
                "--db" => db_name = value,
                "--database" => database = value,
                "--command" => command = value,
                "--workspace" => workspace = value,
                _ => tab_id = value,
            }
        }
        i += 1;
    }
    let db_name = db_name.unwrap_or_else(|| db_fail("error", "missing --db <conn>"));
    let command = match command {
        Some(c) if !c.trim().is_empty() => c,
        _ => db_fail("error", "missing --command '<json>'"),
    };
    let mut cmd_args = Map::new();
    cmd_args.insert("db".into(), json!(db_name));
    cmd_args.insert("command".into(), json!(command));
    if let Some(d) = database {
        cmd_args.insert("database".into(), json!(d));
    }
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    nosql_request("mongo-cmd", cmd_args, tab_id)
}

/// `… browse` (plano 53): abre a view de browse no app. [wire] =
/// `redis-browse` (`--pattern`) ou `mongo-browse` (posicional `<collection>` +
/// `--filter`).
fn browse(wire: &str, args: &[String]) -> ! {
    let mut db_name: Option<String> = None;
    let mut database: Option<String> = None;
    let mut workspace: Option<String> = None;
    let mut tab_id: Option<String> = None;
    let mut pattern: Option<String> = None;
    let mut filter: Option<String> = None;
    let mut positionals: Vec<String> = Vec::new();

    let mut i = 0usize;
    while i < args.len() {
        let a = args[i].clone();
        if a == "--help" || a == "-h" {
            println!(
                "{}",
                if wire == "redis-browse" {
                    "cockpit redis browse --db <conn> [--pattern 'user:*']"
                } else {
                    "cockpit mongo browse --db <conn> [--database <name>] <collection> [--filter '<json>']"
                }
            );
            std::process::exit(0);
        }
        if let Some((flag, value)) = take(
            args,
            &mut i,
            &[
                "--db",
                "--database",
                "--workspace",
                "--tab-id",
                "--pattern",
                "--filter",
            ],
        ) {
            match flag {
                "--db" => db_name = value,
                "--database" => database = value,
                "--workspace" => workspace = value,
                "--tab-id" => tab_id = value,
                "--pattern" => pattern = value,
                _ => filter = value,
            }
        }
        if !a.starts_with("--") {
            positionals.push(a);
        }
        i += 1;
    }

    let db_name = db_name.unwrap_or_else(|| db_fail("error", "missing --db <conn>"));
    let mut cmd_args = Map::new();
    cmd_args.insert("db".into(), json!(db_name));
    if let Some(ws) = workspace {
        cmd_args.insert("workspace".into(), json!(ws));
    }
    if wire == "mongo-browse" {
        if positionals.is_empty() {
            db_fail("error", "missing <collection>");
        }
        cmd_args.insert("collection".into(), json!(positionals[0]));
        if let Some(f) = filter {
            cmd_args.insert("filter".into(), json!(f));
        }
        if let Some(d) = database {
            cmd_args.insert("database".into(), json!(d));
        }
    } else if let Some(p) = pattern {
        cmd_args.insert("pattern".into(), json!(p));
    }
    nosql_request(wire, cmd_args, tab_id)
}

/// Envia um comando de banco e imprime `{"ok": …}` / `{"error": …}`.
fn nosql_request(wire: &str, cmd_args: Map<String, Value>, tab_id: Option<String>) -> ! {
    let mut req = json!({"cmd": wire, "args": Value::Object(cmd_args)});
    with_tab_id(&mut req, tab_id.or_else(self_tab_id));
    let resp = transport::request(req, DB_TIMEOUT);
    if is_ok(&resp) {
        let data = resp.get("data").cloned().unwrap_or(Value::Null);
        println!("{}", json!({"ok": data}));
        std::process::exit(0);
    }
    let raw = transport::error_text(&resp);
    if let Some(sep) = raw.find(": ") {
        if sep > 0 {
            let kind = &raw[..sep];
            if DB_ERROR_KINDS.contains(&kind) {
                db_fail(kind, &raw[sep + 2..]);
            }
        }
    }
    db_fail("error", &raw)
}

// ---- install-skill ----------------------------------------------------------

const SKILL_MARKDOWN: &str = include_str!("../text/skill.md");

pub fn install_skill(args: &[String]) -> ! {
    let parsed = Flags::parse(args);
    let home = match crate::util::home_dir() {
        Some(h) => h,
        None => die("cockpit: HOME not resolved", 1),
    };
    let dir = format!("{home}/.claude/skills/cockpit-cli");
    let path = format!("{dir}/SKILL.md");
    if !parsed.force {
        if let Ok(current) = std::fs::read_to_string(&path) {
            if current == SKILL_MARKDOWN {
                println!("cockpit: skill already installed ({path})");
                std::process::exit(0);
            }
        }
    }
    if let Err(e) = std::fs::create_dir_all(&dir) {
        die(&format!("cockpit: {e}"), 1);
    }
    if let Err(e) = std::fs::write(&path, SKILL_MARKDOWN) {
        die(&format!("cockpit: {e}"), 1);
    }
    println!("cockpit: skill installed at {path}");
    std::process::exit(0)
}

// ---- helpers de parsing -----------------------------------------------------

/// Lê `--flag valor` ou `--flag=valor` na posição atual, avançando o índice
/// quando consome o valor separado. Devolve `(flag, valor)` quando casa.
fn take<'a>(
    args: &[String],
    i: &mut usize,
    flags: &[&'a str],
) -> Option<(&'a str, Option<String>)> {
    let a = args[*i].as_str();
    for flag in flags {
        if a == *flag {
            *i += 1;
            return Some((flag, args.get(*i).cloned()));
        }
        let prefix = format!("{flag}=");
        if let Some(v) = a.strip_prefix(&prefix) {
            return Some((flag, Some(v.to_string())));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formata_list_tabs() {
        let data = vec![json!({
            "id": "t1",
            "kind": "terminal",
            "title": "zsh",
            "workspacePath": "/Users/x/Projects/remote_pi",
            "working": true,
        })];
        let lines = format_list("list-panes", &data);
        assert_eq!(lines.len(), 1);
        assert!(lines[0].starts_with("● t1    "), "{}", lines[0]);
        assert!(lines[0].contains("remote_pi"), "{}", lines[0]);
        assert!(lines[0].ends_with("zsh"), "{}", lines[0]);
    }

    #[test]
    fn label_manual_vence_titulo() {
        let data = vec![json!({"id": "t2", "label": "Cockpit", "title": "zsh"})];
        let lines = format_list("list-panes", &data);
        assert!(lines[0].ends_with("⚲ Cockpit"), "{}", lines[0]);
    }

    #[test]
    fn workspace_sem_path_cai_no_id() {
        let data = vec![json!({"id": "t3", "workspaceId": "uuid-123"})];
        let lines = format_list("list-panes", &data);
        assert!(lines[0].contains("uuid-123"), "{}", lines[0]);
    }

    #[test]
    fn formata_tasks_com_marcador_de_output() {
        let data = vec![json!({
            "id": "npm:dev", "source": "package", "label": "dev server",
            "running": true, "hasOutput": true,
        })];
        let lines = format_list("list-tasks", &data);
        assert!(lines[0].starts_with("● npm:dev"), "{}", lines[0]);
        assert!(lines[0].ends_with("dev server  [output]"), "{}", lines[0]);
    }

    #[test]
    fn formata_workspaces_com_fallback_de_panes() {
        let novo = vec![json!({"name": "remote_pi", "tabs": 3, "path": "/p"})];
        assert!(format_list("list-workspaces", &novo)[0].contains("3 tabs"));
        let antigo = vec![json!({"name": "old", "panes": 2, "path": "/q"})];
        assert!(format_list("list-workspaces", &antigo)[0].contains("2 tabs"));
        let vazio = vec![json!({"name": "none", "path": "/r"})];
        assert!(format_list("list-workspaces", &vazio)[0].contains("0 tabs"));
    }

    #[test]
    fn take_aceita_as_duas_formas() {
        let args: Vec<String> = ["--db", "cache", "--limit=10"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let mut i = 0;
        assert_eq!(
            take(&args, &mut i, &["--db", "--limit"]),
            Some(("--db", Some("cache".into())))
        );
        i += 1;
        assert_eq!(
            take(&args, &mut i, &["--db", "--limit"]),
            Some(("--limit", Some("10".into())))
        );
    }
}
