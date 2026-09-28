//! Helpers compartilhados: ambiente, caminhos e formatação de coluna.
//!
//! Porte fiel dos helpers do `tool/cockpit_cli.dart` — o formato de saída é
//! consumido por humano E por agente, então largura de coluna e espaçamento
//! importam.

use std::path::Path;

/// Id da própria tab: `COCKPIT_TAB_ID` (novo) com fallback pro legado
/// `COCKPIT_PANE_ID`. O app injeta os dois; o fallback cobre binário novo com
/// app antigo (só PANE_ID) e vice-versa.
pub fn self_tab_id() -> Option<String> {
    env_non_empty("COCKPIT_TAB_ID").or_else(|| env_non_empty("COCKPIT_PANE_ID"))
}

/// Variável de ambiente, tratando vazio como ausente.
pub fn env_non_empty(key: &str) -> Option<String> {
    match std::env::var(key) {
        Ok(v) if !v.is_empty() => Some(v),
        _ => None,
    }
}

/// Escreve em stderr e sai com [code]. Usado nos erros de uso da CLI.
pub fn die(msg: &str, code: i32) -> ! {
    eprintln!("{msg}");
    std::process::exit(code)
}

/// Expande `~` e resolve caminhos relativos contra o cwd atual, produzindo um
/// caminho absoluto. **Não normaliza `..`** — igual ao `File(p).absolute.path`
/// do Dart, porque quem interpreta é o app.
pub fn resolve_path(path: &str) -> String {
    let mut p = path.to_string();
    if p == "~" || p.starts_with("~/") {
        if let Some(home) = home_dir() {
            p = if p == "~" {
                home
            } else {
                format!("{home}/{}", &p[2..])
            };
        }
    }
    let candidate = Path::new(&p);
    if candidate.is_absolute() {
        return p;
    }
    match std::env::current_dir() {
        Ok(cwd) => cwd.join(&p).to_string_lossy().into_owned(),
        Err(_) => p,
    }
}

/// `HOME` (POSIX) ou `USERPROFILE` (Windows).
pub fn home_dir() -> Option<String> {
    env_non_empty("HOME").or_else(|| env_non_empty("USERPROFILE"))
}

/// Preenche à direita com espaços até [n] caracteres (nunca trunca).
pub fn pad(s: &str, n: usize) -> String {
    let len = s.chars().count();
    if len >= n {
        s.to_string()
    } else {
        let mut out = String::with_capacity(s.len() + (n - len));
        out.push_str(s);
        out.extend(std::iter::repeat(' ').take(n - len));
        out
    }
}

/// Último segmento do caminho, ignorando separadores finais. Aceita `\` e `/`
/// no Windows.
pub fn basename(path: &str) -> String {
    let parts: Vec<&str> = if cfg!(windows) {
        path.split(['/', '\\']).filter(|p| !p.is_empty()).collect()
    } else {
        path.split('/').filter(|p| !p.is_empty()).collect()
    };
    match parts.last() {
        Some(last) => (*last).to_string(),
        None => path.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pad_preenche_e_nunca_trunca() {
        assert_eq!(pad("ab", 5), "ab   ");
        assert_eq!(pad("abcdef", 3), "abcdef");
        assert_eq!(pad("", 2), "  ");
    }

    #[test]
    fn basename_ignora_barras_finais() {
        assert_eq!(basename("/a/b/c"), "c");
        assert_eq!(basename("/a/b/c/"), "c");
        assert_eq!(basename("solo"), "solo");
    }

    #[test]
    fn resolve_path_mantem_absoluto_intacto() {
        // No Windows "/tmp/x" não é absoluto (falta o drive) e vira "D:/tmp/x".
        let abs = if cfg!(windows) { "C:/tmp/x" } else { "/tmp/x" };
        assert_eq!(resolve_path(abs), abs);
    }

    #[test]
    fn resolve_path_expande_til() {
        let home = home_dir().expect("HOME");
        assert_eq!(resolve_path("~"), home);
        assert_eq!(resolve_path("~/a"), format!("{home}/a"));
    }
}
