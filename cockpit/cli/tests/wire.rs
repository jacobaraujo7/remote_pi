//! Testes de integração do **wire**: sobem um servidor de socket falso, rodam o
//! binário de verdade contra ele e conferem a requisição que chega e a saída
//! que sai.
//!
//! É o contrato que o app do outro lado enxerga. Antes deste port ele não
//! existia em lugar nenhum (a CLI Dart não tinha teste), então qualquer
//! divergência de campo passava batido até alguém notar no uso.

#![cfg(unix)]

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::process::Command;

use serde_json::Value;
use std::sync::atomic::{AtomicU64, Ordering};

/// Diretório temporário exclusivo. O contador é o que garante unicidade entre
/// os testes, que o cargo roda em paralelo: só PID + timestamp colidia (dois
/// casos podem cair no mesmo nanossegundo) e o `bind` falhava com EEXIST.
fn unique_dir(prefix: &str) -> std::path::PathBuf {
    static SEQ: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "{prefix}-{}-{}",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ))
}

/// Sobe um listener num caminho temporário, roda `cockpit <args>` apontado pra
/// ele e devolve `(requisição recebida, stdout, stderr, exit code)`.
fn run_against_fake_app(args: &[&str], response: &str) -> (Value, String, String, i32) {
    let dir = unique_dir("cockpit-wire");
    std::fs::create_dir_all(&dir).unwrap();
    let sock_path = dir.join("status.sock");
    let listener = UnixListener::bind(&sock_path).unwrap();

    let response = response.to_string();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let mut stream = reader.into_inner();
        stream.write_all(response.as_bytes()).unwrap();
        stream.write_all(b"\n").unwrap();
        stream.flush().unwrap();
        drop(stream); // fecha → o cliente vê EOF
        line
    });

    let out = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .args(args)
        .env("COCKPIT_STATUS_SOCK", &sock_path)
        .env("COCKPIT_TAB_ID", "t7")
        .env_remove("COCKPIT_STATUS_PORT")
        .env_remove("COCKPIT_STATUS_TOKEN")
        .output()
        .unwrap();

    let request_line = server.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    (
        serde_json::from_str(&request_line).expect("requisição não é JSON"),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
        out.status.code().unwrap_or(-1),
    )
}

#[test]
fn send_manda_texto_em_base64_com_type_cmd() {
    let (req, _, _, code) = run_against_fake_app(&["send", "olá", "mundo"], r#"{"ok":true}"#);
    assert_eq!(req["type"], "cmd");
    assert_eq!(req["cmd"], "write");
    assert_eq!(
        req["tabId"], "t7",
        "cai no COCKPIT_TAB_ID quando não passam --tab-id"
    );
    // "olá mundo" em base64
    assert_eq!(req["args"]["data"], "b2zDoSBtdW5kbw==");
    assert_eq!(code, 0);
}

#[test]
fn send_key_resolve_teclas_nomeadas() {
    let (req, _, _, code) = run_against_fake_app(&["send-key", "C-c", "Enter"], r#"{"ok":true}"#);
    // \x03\r
    assert_eq!(req["args"]["data"], "Aw0=");
    assert_eq!(code, 0);
}

#[test]
fn tab_id_explicito_vence_o_ambiente() {
    let (req, _, _, _) = run_against_fake_app(&["send", "--tab-id", "t99", "oi"], r#"{"ok":true}"#);
    assert_eq!(req["tabId"], "t99");
}

#[test]
fn list_tabs_usa_o_comando_de_wire_legado_e_formata() {
    let resp = r#"{"ok":true,"data":[
        {"id":"t1","kind":"terminal","title":"zsh","workspacePath":"/x/remote_pi","working":true}
    ]}"#;
    let (req, stdout, _, code) = run_against_fake_app(&["list-tabs"], resp);
    assert_eq!(req["cmd"], "list-panes", "o verbo mudou, o wire não");
    assert!(stdout.starts_with("● t1"), "{stdout}");
    assert!(stdout.contains("remote_pi"), "{stdout}");
    assert_eq!(code, 0);
}

#[test]
fn list_vazia_imprime_none() {
    let (_, stdout, _, code) = run_against_fake_app(&["list-tabs"], r#"{"ok":true,"data":[]}"#);
    assert_eq!(stdout, "(none)\n");
    assert_eq!(code, 0);
}

#[test]
fn read_tab_decodifica_base64_e_avisa_truncamento() {
    // "linha1\nlinha2" em base64
    let resp = r#"{"ok":true,"data":{"text":"bGluaGExCmxpbmhhMg==","truncated":true}}"#;
    let (req, stdout, stderr, code) = run_against_fake_app(&["read-tab", "--lines", "5"], resp);
    assert_eq!(req["cmd"], "read-pane");
    assert_eq!(req["args"]["lines"], 5);
    assert_eq!(stdout, "linha1\nlinha2\n");
    assert!(stderr.contains("output truncated"), "{stderr}");
    assert_eq!(code, 0);
}

#[test]
fn erro_do_app_vira_exit_1_no_stderr() {
    let (_, stdout, stderr, code) =
        run_against_fake_app(&["list-tabs"], r#"{"ok":false,"error":"boom"}"#);
    assert_eq!(stdout, "");
    assert_eq!(stderr, "cockpit: boom\n");
    assert_eq!(code, 1);
}

#[test]
fn db_query_monta_args_e_imprime_contrato_json() {
    let resp = r#"{"ok":true,"data":{"rowCount":1}}"#;
    let (req, stdout, _, code) = run_against_fake_app(
        &[
            "db", "query", "--db", "dev", "--sql", "SELECT 1", "--limit", "10",
        ],
        resp,
    );
    assert_eq!(req["cmd"], "db-query");
    assert_eq!(req["args"]["db"], "dev");
    assert_eq!(req["args"]["sql"], "SELECT 1");
    assert_eq!(req["args"]["limit"], "10");
    assert_eq!(stdout, "{\"ok\":{\"rowCount\":1}}\n");
    assert_eq!(code, 0);
}

#[test]
fn db_erro_conhecido_vira_kind_estruturado() {
    let resp = r#"{"ok":false,"error":"read_only_connection: agents are read-only here"}"#;
    let (_, stdout, _, code) = run_against_fake_app(&["db", "list"], resp);
    let parsed: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(parsed["error"]["kind"], "read_only_connection");
    assert_eq!(parsed["error"]["message"], "agents are read-only here");
    assert_eq!(code, 1, "erro de db também sai por stdout, mas com exit 1");
}

#[test]
fn db_erro_desconhecido_cai_no_kind_generico() {
    let resp = r#"{"ok":false,"error":"algo inesperado"}"#;
    let (_, stdout, _, code) = run_against_fake_app(&["db", "list"], resp);
    let parsed: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(parsed["error"]["kind"], "error");
    assert_eq!(parsed["error"]["message"], "algo inesperado");
    assert_eq!(code, 1);
}

#[test]
fn redis_manda_as_partes_do_comando() {
    let (req, _, _, _) = run_against_fake_app(
        &["redis", "--db", "cache", "GET", "session:42"],
        r#"{"ok":true,"data":"v"}"#,
    );
    assert_eq!(req["cmd"], "redis-cmd");
    assert_eq!(req["args"]["db"], "cache");
    assert_eq!(req["args"]["parts"][0], "GET");
    assert_eq!(req["args"]["parts"][1], "session:42");
}

#[test]
fn mongo_browse_leva_collection_e_database() {
    let (req, _, _, _) = run_against_fake_app(
        &[
            "mongo",
            "browse",
            "--db",
            "app",
            "--database",
            "prod",
            "users",
            "--filter",
            "{}",
        ],
        r#"{"ok":true,"data":null}"#,
    );
    assert_eq!(req["cmd"], "mongo-browse");
    assert_eq!(req["args"]["collection"], "users");
    assert_eq!(req["args"]["database"], "prod");
    assert_eq!(req["args"]["filter"], "{}");
}

#[test]
fn browse_manda_a_url_no_wire() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["browse", "http://localhost:3000"],
        r#"{"ok":true,"data":{"mode":"inline","url":"http://localhost:3000"}}"#,
    );
    assert_eq!(req["cmd"], "browse");
    assert_eq!(req["args"]["url"], "http://localhost:3000");
    assert_eq!(stdout, "ok\n");
    assert_eq!(code, 0);
}

#[test]
fn browse_json_ecoa_o_data() {
    let (_, stdout, _, _) = run_against_fake_app(
        &["browse", "--json", "http://localhost:3000"],
        r#"{"ok":true,"data":{"mode":"system","url":"http://localhost:3000"}}"#,
    );
    let parsed: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(parsed["mode"], "system");
}

#[test]
fn close_tab_sem_alvo_nao_manda_target() {
    // Sem posicional o app cai na própria tab ($COCKPIT_TAB_ID) — mandar
    // `target` vazio faria o app tentar resolvê-lo como label.
    let (req, stdout, _, code) =
        run_against_fake_app(&["close-tab"], r#"{"ok":true,"data":{"tabId":"t7"}}"#);
    assert_eq!(req["cmd"], "close-tab");
    assert!(req["args"].get("target").is_none(), "{:?}", req["args"]);
    assert_eq!(stdout, "t7\n");
    assert_eq!(code, 0);
}

#[test]
fn close_tab_aceita_label_ou_id_posicional() {
    let (req, _, _, _) = run_against_fake_app(
        &["close-tab", "Extension"],
        r#"{"ok":true,"data":{"tabId":"t3"}}"#,
    );
    assert_eq!(req["cmd"], "close-tab");
    assert_eq!(req["args"]["target"], "Extension");
}

#[test]
fn close_tab_json_ecoa_o_data() {
    let (_, stdout, _, _) = run_against_fake_app(
        &["close-tab", "--json", "t3"],
        r#"{"ok":true,"data":{"tabId":"t3"}}"#,
    );
    let parsed: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(parsed["tabId"], "t3");
}

#[test]
fn close_tab_propaga_erro_do_app() {
    let (_, _, stderr, code) = run_against_fake_app(
        &["close-tab", "nope"],
        r#"{"ok":false,"error":"no tab with id or label \"nope\""}"#,
    );
    assert_eq!(code, 1);
    assert!(stderr.contains("nope"), "{stderr}");
}

#[test]
fn open_resolve_caminho_relativo_para_absoluto() {
    let (req, _, _, _) = run_against_fake_app(&["open", "arquivo.txt"], r#"{"ok":true}"#);
    assert_eq!(req["cmd"], "open");
    let path = req["args"]["path"].as_str().unwrap();
    assert!(path.starts_with('/'), "esperava absoluto, veio {path}");
    assert!(path.ends_with("/arquivo.txt"), "{path}");
}

#[test]
fn arquivo_solto_e_atalho_de_open() {
    let (req, _, _, _) = run_against_fake_app(&["/tmp/nota.md"], r#"{"ok":true}"#);
    assert_eq!(req["cmd"], "open");
    assert_eq!(req["args"]["path"], "/tmp/nota.md");
}

#[test]
fn hook_reporta_status_pelo_mesmo_socket() {
    // O hook lê o evento do stdin; aqui exercitamos o caminho completo.
    let dir = unique_dir("cockpit-hook");
    std::fs::create_dir_all(&dir).unwrap();
    let sock_path = dir.join("status.sock");
    let listener = UnixListener::bind(&sock_path).unwrap();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        line
    });

    let mut child = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .arg("hook")
        .env("COCKPIT_STATUS_SOCK", &sock_path)
        .env("COCKPIT_PANE_ID", "t3")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(br#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        .unwrap();
    let out = child.wait_with_output().unwrap();

    let line = server.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let req: Value = serde_json::from_str(&line).unwrap();
    assert_eq!(req["paneId"], "t3");
    assert_eq!(req["st"], "idle");
    assert_eq!(req["ev"], "Stop");
    assert_eq!(req["sid"], "s1");
    assert!(req.get("type").is_none(), "hook não manda type:cmd");
    assert!(out.stdout.is_empty(), "hook nunca escreve no stdout");
    assert_eq!(out.status.code(), Some(0));
}

#[test]
fn hook_fora_do_cockpit_e_noop_silencioso() {
    let out = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .arg("hook")
        .env_remove("COCKPIT_PANE_ID")
        .env_remove("COCKPIT_STATUS_SOCK")
        .env_remove("COCKPIT_STATUS_PORT")
        .stdin(std::process::Stdio::null())
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert!(out.stdout.is_empty());
    assert!(out.stderr.is_empty());
}

#[test]
fn send_com_enter_manda_o_retorno_numa_segunda_escrita() {
    // O Enter vai numa escrita SEPARADA de propósito: TUIs distinguem "digitou e
    // submeteu" de "colou um bloco com \r no meio". Este teste é o que trava
    // essa decisão — se alguém "otimizar" pra um write só, ele quebra.
    let dir = unique_dir("cockpit-enter");
    std::fs::create_dir_all(&dir).unwrap();
    let sock_path = dir.join("status.sock");
    let listener = UnixListener::bind(&sock_path).unwrap();

    let server = std::thread::spawn(move || {
        let mut requests = Vec::new();
        for _ in 0..2 {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            let mut stream = reader.into_inner();
            stream.write_all(b"{\"ok\":true}\n").unwrap();
            stream.flush().unwrap();
            drop(stream);
            requests.push(line);
        }
        requests
    });

    let out = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .args(["send", "--tab-id", "t4", "--enter", "npm", "test"])
        .env("COCKPIT_STATUS_SOCK", &sock_path)
        .output()
        .unwrap();

    let requests = server.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(
        requests.len(),
        2,
        "esperava texto e Enter em escritas separadas"
    );

    let texto: Value = serde_json::from_str(&requests[0]).unwrap();
    assert_eq!(texto["cmd"], "write");
    assert_eq!(texto["tabId"], "t4");
    // "npm test" (a flag não vaza pro texto digitado)
    assert_eq!(texto["args"]["data"], "bnBtIHRlc3Q=");

    let enter: Value = serde_json::from_str(&requests[1]).unwrap();
    assert_eq!(enter["tabId"], "t4", "o Enter vai pra MESMA aba");
    assert_eq!(enter["args"]["data"], "DQ==", "\\r isolado");
    assert_eq!(out.status.code(), Some(0));
}

#[test]
fn send_sem_enter_faz_uma_escrita_so() {
    let (req, _, _, code) = run_against_fake_app(&["send", "ls"], r#"{"ok":true}"#);
    assert_eq!(req["args"]["data"], "bHM=", "sem \\r grudado no texto");
    assert_eq!(code, 0);
}

#[test]
fn focused_manda_o_sentinela_para_o_app_resolver() {
    // Quem sabe qual aba está em foco é o app, não a CLI: mandamos `@focused` e
    // o handler troca pelo id real. Assim uma ferramenta externa (ditado por
    // voz) não precisa descobrir nem copiar id nenhum.
    // Sem `--enter` aqui de propósito: o helper aceita UMA conexão, e o Enter
    // vai numa segunda escrita (coberta por `send_com_enter_...`).
    let (req, _, _, code) = run_against_fake_app(&["send", "--focused", "oi"], r#"{"ok":true}"#);
    assert_eq!(req["tabId"], "@focused");
    assert_eq!(code, 0);
}

#[test]
fn focused_ignora_o_tab_id_do_ambiente() {
    // COCKPIT_TAB_ID está setado no helper; --focused tem que vencer, senão o
    // texto iria pra aba que chamou em vez da que o usuário está vendo.
    let (req, _, _, _) = run_against_fake_app(&["send", "--focused", "oi"], r#"{"ok":true}"#);
    assert_ne!(req["tabId"], "t7");
    assert_eq!(req["tabId"], "@focused");
}

#[test]
fn acha_o_socket_bem_conhecido_sem_env_nenhuma() {
    // O caso da ferramenta externa: nenhuma env herdada. A CLI cai no
    // ~/.cockpit/status.sock. Aqui apontamos HOME pro temp pra não depender do
    // app real estar rodando.
    let dir = unique_dir("cockpit-discovery");
    std::fs::create_dir_all(dir.join(".cockpit")).unwrap();
    let sock_path = dir.join(".cockpit/status.sock");
    let listener = UnixListener::bind(&sock_path).unwrap();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let mut stream = reader.into_inner();
        stream.write_all(b"{\"ok\":true}\n").unwrap();
        stream.flush().unwrap();
        drop(stream);
        line
    });

    let out = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .args(["send", "--focused", "ditado"])
        .env("HOME", &dir)
        .env_remove("COCKPIT_STATUS_SOCK")
        .env_remove("COCKPIT_STATUS_PORT")
        .env_remove("COCKPIT_TAB_ID")
        .env_remove("COCKPIT_PANE_ID")
        .output()
        .unwrap();

    let line = server.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let req: Value = serde_json::from_str(&line).unwrap();
    assert_eq!(req["cmd"], "write");
    assert_eq!(req["tabId"], "@focused");
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn sem_app_nenhum_falha_com_exit_3() {
    let dir = unique_dir("cockpit-noapp");
    std::fs::create_dir_all(&dir).unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_cockpit"))
        .args(["list-tabs"])
        .env("HOME", &dir)
        .env_remove("COCKPIT_STATUS_SOCK")
        .env_remove("COCKPIT_STATUS_PORT")
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(out.status.code(), Some(3));
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("Is the app running?"),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn new_workspace_manda_path_resolvido_e_nome_opcional() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["new-workspace", "my/project", "--name", "My Project"],
        r#"{"ok":true,"data":{"id":"ws-uuid-1","name":"My Project","path":"/resolved/my/project","tabs":1}}"#,
    );
    assert_eq!(req["type"], "cmd");
    assert_eq!(req["cmd"], "new-workspace");
    assert!(
        req["args"]["path"].as_str().unwrap().ends_with("my/project"),
        "path deve ser absoluto: {}",
        req["args"]["path"]
    );
    assert_eq!(req["args"]["name"], "My Project");
    assert_eq!(stdout.trim(), "ws-uuid-1");
    assert_eq!(code, 0);
}

#[test]
fn new_remote_workspace_com_flags_host_e_path() {
    let (req, stdout, _, code) = run_against_fake_app(
        &[
            "new-remote-workspace",
            "--host",
            "workspace-scott-meyer-2",
            "--path",
            "/home/ubuntu/repo-worktrees/task-1",
            "--name",
            "task-1",
        ],
        r#"{"ok":true,"data":{"id":"__remote__1::/home/ubuntu/repo-worktrees/task-1","name":"task-1","path":"/home/ubuntu/repo-worktrees/task-1","host":"workspace-scott-meyer-2","tabs":1}}"#,
    );
    assert_eq!(req["type"], "cmd");
    assert_eq!(req["cmd"], "new-workspace");
    assert_eq!(req["args"]["host"], "workspace-scott-meyer-2");
    assert_eq!(
        req["args"]["path"],
        "/home/ubuntu/repo-worktrees/task-1",
        "caminho remoto deve ser preservado exatamente como passado"
    );
    assert_eq!(req["args"]["name"], "task-1");
    assert_eq!(
        stdout.trim(),
        "__remote__1::/home/ubuntu/repo-worktrees/task-1"
    );
    assert_eq!(code, 0);
}

#[test]
fn new_workspace_com_host_e_posicional_remoto() {
    let (req, stdout, _, code) = run_against_fake_app(
        &[
            "new-workspace",
            "/home/ubuntu/worktree",
            "--host",
            "workspace-vm",
            "--json",
        ],
        r#"{"ok":true,"data":{"id":"__remote__2::/home/ubuntu/worktree","name":"worktree","path":"/home/ubuntu/worktree","host":"workspace-vm","tabs":1}}"#,
    );
    assert_eq!(req["cmd"], "new-workspace");
    assert_eq!(req["args"]["host"], "workspace-vm");
    assert_eq!(req["args"]["path"], "/home/ubuntu/worktree");
    let parsed: Value = serde_json::from_str(&stdout).expect("JSON válido");
    assert_eq!(parsed["id"], "__remote__2::/home/ubuntu/worktree");
    assert_eq!(parsed["host"], "workspace-vm");
    assert_eq!(code, 0);
}


#[test]
fn new_workspace_json_ecoa_o_objeto_completo() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["new-workspace", "/tmp/proj", "--json"],
        r#"{"ok":true,"data":{"id":"ws-uuid-2","name":"proj","path":"/tmp/proj","tabs":1}}"#,
    );
    assert_eq!(req["cmd"], "new-workspace");
    assert_eq!(req["args"]["path"], "/tmp/proj");
    assert!(req["args"].get("name").is_none());
    let parsed: Value = serde_json::from_str(&stdout).expect("JSON válido");
    assert_eq!(parsed["id"], "ws-uuid-2");
    assert_eq!(parsed["tabs"], 1);
    assert_eq!(code, 0);
}

#[test]
fn open_workspace_e_alias_de_new_workspace() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["open-workspace", "/tmp/proj2"],
        r#"{"ok":true,"data":{"id":"ws-uuid-3","name":"proj2","path":"/tmp/proj2","tabs":1}}"#,
    );
    assert_eq!(req["cmd"], "new-workspace");
    assert_eq!(req["args"]["path"], "/tmp/proj2");
    assert_eq!(stdout.trim(), "ws-uuid-3");
    assert_eq!(code, 0);
}

#[test]
fn close_workspace_com_alvo_manda_target() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["close-workspace", "ws-uuid-1"],
        r#"{"ok":true,"data":{"id":"ws-uuid-1","path":"/tmp/proj","closed":true}}"#,
    );
    assert_eq!(req["cmd"], "close-workspace");
    assert_eq!(req["args"]["target"], "ws-uuid-1");
    assert_eq!(stdout.trim(), "ws-uuid-1");
    assert_eq!(code, 0);
}

#[test]
fn close_workspace_sem_alvo_cai_na_tab_do_ambiente() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["close-workspace"],
        r#"{"ok":true,"data":{"id":"ws-uuid-4","path":"/tmp/proj4","closed":true}}"#,
    );
    assert_eq!(req["cmd"], "close-workspace");
    assert!(req["args"].get("target").is_none());
    assert_eq!(req["tabId"], "t7");
    assert_eq!(stdout.trim(), "ws-uuid-4");
    assert_eq!(code, 0);
}

#[test]
fn close_workspace_json_ecoa_data() {
    let (_, stdout, _, code) = run_against_fake_app(
        &["close-workspace", "ws-uuid-1", "--json"],
        r#"{"ok":true,"data":{"id":"ws-uuid-1","path":"/tmp/proj","closed":true}}"#,
    );
    let parsed: Value = serde_json::from_str(&stdout).expect("JSON válido");
    assert_eq!(parsed["closed"], true);
    assert_eq!(code, 0);
}

#[test]
fn rename_workspace_manda_target_e_name() {
    let (req, stdout, _, code) = run_against_fake_app(
        &["rename-workspace", "ws-uuid-1", "Novo Nome"],
        r#"{"ok":true,"data":{"id":"ws-uuid-1","name":"Novo Nome","path":"/tmp/proj"}}"#,
    );
    assert_eq!(req["cmd"], "rename-workspace");
    assert_eq!(req["args"]["target"], "ws-uuid-1");
    assert_eq!(req["args"]["name"], "Novo Nome");
    assert_eq!(stdout.trim(), "ws-uuid-1");
    assert_eq!(code, 0);
}

#[test]
fn rename_workspace_json_ecoa_data() {
    let (_, stdout, _, code) = run_against_fake_app(
        &["rename-workspace", "ws-uuid-1", "Novo Nome", "--json"],
        r#"{"ok":true,"data":{"id":"ws-uuid-1","name":"Novo Nome","path":"/tmp/proj"}}"#,
    );
    let parsed: Value = serde_json::from_str(&stdout).expect("JSON válido");
    assert_eq!(parsed["name"], "Novo Nome");
    assert_eq!(code, 0);
}

#[test]
fn workspace_erros_propagam_exit_1() {
    let (_, _, stderr, code) = run_against_fake_app(
        &["new-workspace", "/nonexistent"],
        r#"{"ok":false,"error":"directory not found: /nonexistent"}"#,
    );
    assert_eq!(code, 1);
    assert!(stderr.contains("directory not found: /nonexistent"));
}

