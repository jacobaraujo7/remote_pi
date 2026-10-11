//! `cockpit install-skill` (plano 69): grava as skills embutidas nas pastas de
//! skills dos harnesses instalados nesta máquina.
//!
//! Uma skill é a pasta `<nome>/` com `SKILL.md` e arquivos de apoio. Cada
//! skill instalada ganha um manifesto `.cockpit-skill.json` com a lista de
//! arquivos que são nossos: no update, o que saiu da árvore é apagado (sem
//! isso uma `references/x.md` órfã ficaria pra sempre), e arquivo igual é
//! no-op. Arquivos que o usuário colocou na pasta e não constam no manifesto
//! não são tocados.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use serde_json::{json, Value};

use crate::util::{die, home_dir};

include!(concat!(env!("OUT_DIR"), "/skills_gen.rs"));

const MANIFEST: &str = ".cockpit-skill.json";
const HELP: &str = "cockpit install-skill [--agent claude|codex|pi|all] [--force] [--list]
  Installs Cockpit's agent skills (cockpit-cli, …) into the skills folder of each
  harness found in $HOME. Idempotent: identical files are left alone, files that
  no longer ship are removed. --list prints the embedded skills and exits.";

/// Harness → pasta de skills (relativa ao HOME) e a pasta que prova que o
/// harness existe nesta máquina. Só instala onde o harness já está.
const AGENTS: &[(&str, &str, &str)] = &[
    ("claude", ".claude/skills", ".claude"),
    ("codex", ".codex/skills", ".codex"),
    ("pi", ".pi/agent/skills", ".pi/agent"),
];

pub fn install_skill(args: &[String]) -> ! {
    let mut agent = "all".to_string();
    let mut force = false;
    let mut list = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--agent" => {
                i += 1;
                agent = args
                    .get(i)
                    .cloned()
                    .unwrap_or_else(|| die("cockpit install-skill: --agent requires a value", 2));
            }
            a if a.starts_with("--agent=") => agent = a["--agent=".len()..].to_string(),
            "--force" | "-f" => force = true,
            "--list" => list = true,
            "-h" | "--help" => {
                println!("{HELP}");
                std::process::exit(0)
            }
            other => die(
                &format!("cockpit install-skill: unknown flag {other}\n{HELP}"),
                2,
            ),
        }
        i += 1;
    }
    if list {
        for name in skill_names() {
            println!("{name}");
            for (rel, bytes) in SKILLS
                .iter()
                .filter(|(r, _)| r.starts_with(&format!("{name}/")))
            {
                println!("  {rel} ({} bytes)", bytes.len());
            }
        }
        std::process::exit(0)
    }
    let home = home_dir().unwrap_or_else(|| die("cockpit: HOME not resolved", 1));
    let home = Path::new(&home);
    let targets: Vec<&(&str, &str, &str)> = AGENTS
        .iter()
        .filter(|(n, _, _)| agent == "all" || agent == *n)
        .collect();
    if targets.is_empty() {
        die(
            &format!("cockpit install-skill: unknown agent {agent} (claude|codex|pi|all)"),
            2,
        );
    }
    let mut any = false;
    for (name, skills_dir, marker) in targets {
        // `all` só instala onde o harness existe; `--agent X` explícito cria.
        if agent == "all" && !home.join(marker).exists() {
            continue;
        }
        any = true;
        let root = home.join(skills_dir);
        match install_tree(&root, SKILLS, force) {
            Ok(report) => println!("cockpit: {name}: {report} ({})", root.display()),
            Err(e) => eprintln!("cockpit: {name}: {e}"),
        }
    }
    if !any {
        println!(
            "cockpit: no agent skills folder found in {} (nothing installed)",
            home.display()
        );
    }
    std::process::exit(0)
}

fn skill_names() -> Vec<String> {
    let mut names = BTreeSet::new();
    for (rel, _) in SKILLS {
        if let Some((name, _)) = rel.split_once('/') {
            names.insert(name.to_string());
        }
    }
    names.into_iter().collect()
}

/// Resultado legível de uma instalação (por raiz de skills).
pub struct Report {
    pub written: usize,
    pub removed: usize,
    pub unchanged: usize,
}

impl std::fmt::Display for Report {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.written == 0 && self.removed == 0 {
            write!(f, "skills already installed")
        } else {
            write!(
                f,
                "{} file(s) written, {} removed, {} unchanged",
                self.written, self.removed, self.unchanged
            )
        }
    }
}

/// Instala a árvore [skills] sob [root] (`~/.claude/skills`). Pura em relação a
/// env/HOME, pra teste.
pub fn install_tree(root: &Path, skills: &[(&str, &[u8])], force: bool) -> std::io::Result<Report> {
    let mut report = Report {
        written: 0,
        removed: 0,
        unchanged: 0,
    };
    for name in names_of(skills) {
        let dir = root.join(&name);
        fs::create_dir_all(&dir)?;
        let manifest_path = dir.join(MANIFEST);
        let previous: BTreeSet<String> = read_manifest(&manifest_path);
        let mut current = BTreeSet::new();
        for (rel, bytes) in skills
            .iter()
            .filter(|(r, _)| r.starts_with(&format!("{name}/")))
        {
            let inside = &rel[name.len() + 1..];
            current.insert(inside.to_string());
            let target = dir.join(inside);
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            let same = !force && fs::read(&target).map(|cur| cur == *bytes).unwrap_or(false);
            if same {
                report.unchanged += 1;
            } else {
                fs::write(&target, bytes)?;
                report.written += 1;
            }
        }
        for stale in previous.difference(&current) {
            let p = dir.join(stale);
            if p.is_file() {
                fs::remove_file(&p)?;
                report.removed += 1;
                prune_empty_dirs(p.parent(), &dir);
            }
        }
        let manifest = json!({
            "version": env!("CARGO_PKG_VERSION"),
            "files": current.iter().collect::<Vec<_>>(),
        });
        let text = serde_json::to_string_pretty(&manifest).unwrap_or_default() + "\n";
        if fs::read_to_string(&manifest_path).ok().as_deref() != Some(text.as_str()) {
            fs::write(&manifest_path, text)?;
        }
    }
    Ok(report)
}

fn names_of(skills: &[(&str, &[u8])]) -> Vec<String> {
    let mut names = BTreeSet::new();
    for (rel, _) in skills {
        if let Some((name, _)) = rel.split_once('/') {
            names.insert(name.to_string());
        }
    }
    names.into_iter().collect()
}

fn read_manifest(path: &Path) -> BTreeSet<String> {
    let Ok(text) = fs::read_to_string(path) else {
        return BTreeSet::new();
    };
    let Ok(v) = serde_json::from_str::<Value>(&text) else {
        return BTreeSet::new();
    };
    v.get("files")
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default()
}

/// Apaga pastas que ficaram vazias entre o arquivo removido e a raiz da skill.
fn prune_empty_dirs(mut dir: Option<&Path>, stop: &Path) {
    while let Some(d) = dir {
        if d == stop || !d.starts_with(stop) {
            break;
        }
        if fs::read_dir(d)
            .map(|mut it| it.next().is_none())
            .unwrap_or(false)
        {
            let _ = fs::remove_dir(d);
        }
        dir = d.parent();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn tmp() -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "ck-skills-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn instala_atualiza_e_remove_orfaos() {
        let root = tmp();
        let v1: &[(&str, &[u8])] = &[
            ("cockpit-cli/SKILL.md", b"v1"),
            ("cockpit-cli/references/a.md", b"a"),
        ];
        let r = install_tree(&root, v1, false).unwrap();
        assert_eq!((r.written, r.removed, r.unchanged), (2, 0, 0));
        assert!(root.join("cockpit-cli/references/a.md").exists());
        // arquivo do usuário, fora do manifesto: fica
        fs::write(root.join("cockpit-cli/notes.md"), b"mine").unwrap();

        let r = install_tree(&root, v1, false).unwrap();
        assert_eq!((r.written, r.removed, r.unchanged), (0, 0, 2));
        assert_eq!(r.to_string(), "skills already installed");

        let v2: &[(&str, &[u8])] = &[("cockpit-cli/SKILL.md", b"v2")];
        let r = install_tree(&root, v2, false).unwrap();
        assert_eq!((r.written, r.removed, r.unchanged), (1, 1, 0));
        assert!(
            !root.join("cockpit-cli/references").exists(),
            "pasta vazia some"
        );
        assert!(
            root.join("cockpit-cli/notes.md").exists(),
            "arquivo do usuário intacto"
        );
        assert_eq!(fs::read(root.join("cockpit-cli/SKILL.md")).unwrap(), b"v2");
        let m: Value = serde_json::from_str(
            &fs::read_to_string(root.join("cockpit-cli/.cockpit-skill.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(m["files"], json!(["SKILL.md"]));
    }

    #[test]
    fn force_regrava_mesmo_igual() {
        let root = tmp();
        let v: &[(&str, &[u8])] = &[("x/SKILL.md", b"x")];
        install_tree(&root, v, false).unwrap();
        let r = install_tree(&root, v, true).unwrap();
        assert_eq!(r.written, 1);
    }

    #[test]
    fn arvore_embutida_tem_a_cli() {
        assert!(SKILLS.iter().any(|(r, _)| *r == "cockpit-cli/SKILL.md"));
    }
}
