//! `cockpit` — CLI **interna** do Cockpit, e o helper de hook do Claude Code.
//!
//! Fica visível apenas dentro dos terminais que o app spawna (o app prependa
//! `~/.cockpit/bin[-debug]` no PATH só dessas abas) e fala com o app por um
//! socket (`COCKPIT_STATUS_SOCK` no POSIX; `COCKPIT_STATUS_PORT` +
//! `COCKPIT_STATUS_TOKEN` no Windows), discriminando `type:"cmd"` no wire.
//!
//! Nomenclatura: a unidade que a CLI endereça é uma **tab** (uma sessão de
//! terminal/agente). Um **pane** é a folha do split que agrupa várias tabs — a
//! CLI não o endereça. Por isso o vocabulário é "tab"; `list-panes`/`read-pane`
//! e `COCKPIT_PANE_ID` ficam como **aliases legados**.
//!
//! O subcomando `hook` absorve o antigo binário `cockpit-hook`: um binário só,
//! um protocolo só, uma assinatura só. Ver `hook.rs`.

mod commands;
mod flags;
mod hook;
mod keys;
mod transport;
mod util;

/// Versão da CLI. O sufixo `r` marca a implementação **Rust** — é como se sabe,
/// olhando `cockpit --version`, se o binário instalado ainda é o Dart antigo
/// (sem sufixo) ou este.
const VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "r");

const HELP: &str = include_str!("../text/help.txt");

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.is_empty() {
        eprint!("{HELP}");
        std::process::exit(2);
    }
    let first = argv[0].as_str();
    if first == "--help" || first == "-h" || first == "help" {
        print!("{HELP}");
        std::process::exit(0);
    }
    if first == "--version" || first == "-v" {
        println!("cockpit {VERSION}");
        std::process::exit(0);
    }

    let args = &argv[1..];
    match first {
        // Hook de ciclo de vida dos harnesses (antigo binário `cockpit-hook`).
        // `--harness <nome>` diz de quem veio o evento (default: claude, pros
        // entries antigos que não passam a flag). Silencioso por contrato: não
        // escreve no stdout e nunca falha barulhento.
        "hook" => hook::run(args),
        "send" => commands::send(args),
        "send-key" | "send-keys" => commands::send_key(args),
        "open" => commands::open(args),
        // Mantém o comando de wire 'list-panes' (protocolo estável); só o nome
        // do verbo mudou na superfície.
        "list-tabs" | "list-panes" => commands::list("list-panes", args),
        "list-workspaces" => commands::list("list-workspaces", args),
        "list-tasks" => commands::list("list-tasks", args),
        "read-tab" | "read-pane" => commands::read("read-pane", args),
        "read-task" => commands::read("read-task", args),
        "db" => commands::db(args),
        "http" => commands::http(args),
        "redis" => commands::redis(args),
        "mongo" => commands::mongo(args),
        "new-tab" => commands::new_tab(args),
        "close-tab" => commands::close_tab(args),
        "browse" => commands::browse_url(args),
        "browser" => commands::browser(args),
        "orchestrate" => commands::orchestrate(args),
        "install-skill" => commands::install_skill(args),
        // Atalho: `cockpit <arquivo>` (sem verbo) abre o arquivo — o token
        // desconhecido é tratado como caminho. `cockpit open <arquivo>` é a
        // forma explícita.
        _ => commands::open(&argv),
    }
}
