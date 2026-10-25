//! Assa no binário (1) o flavor e (2) a árvore de skills.
//!
//! Flavor: o app namespaceia o socket por flavor (`status.sock` x
//! `status-debug.sock`) porque um Cockpit de dev e um instalado rodam lado a
//! lado. A CLI é materializada junto do app que a empacotou, então ela deve
//! procurar PRIMEIRO o socket do seu próprio flavor. Quem define é quem
//! compila: `macos/build_cli.sh` e os CMakeLists passam `COCKPIT_FLAVOR=debug`.
//!
//! Skills (plano 69): tudo sob `cli/skills/<nome>/...` vira uma tabela
//! `(caminho relativo, bytes)` em `$OUT_DIR/skills_gen.rs`, que o
//! `install-skill` grava em `~/.claude/skills/<nome>/` (e nos demais
//! harnesses). Árvore no repo, não um arquivo só: cada skill tem `SKILL.md`
//! curto e `references/`/`templates/` lidos sob demanda.

use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-env-changed=COCKPIT_FLAVOR");
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("skills");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut files = Vec::new();
    walk(&root, &root, &mut files);
    assert!(
        files.iter().any(|f| f.ends_with("/SKILL.md")),
        "cli/skills/ precisa de pelo menos uma skill (<nome>/SKILL.md)"
    );
    files.sort();
    let mut out = String::from("pub static SKILLS: &[(&str, &[u8])] = &[\n");
    for rel in &files {
        let abs = root.join(rel);
        println!("cargo:rerun-if-changed={}", abs.display());
        out.push_str(&format!(
            "    ({:?}, include_bytes!({:?})),\n",
            rel,
            abs.display().to_string()
        ));
    }
    out.push_str("];\n");
    let dest = Path::new(&std::env::var("OUT_DIR").unwrap()).join("skills_gen.rs");
    fs::write(dest, out).unwrap();
}

fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let p = e.path();
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        if p.is_dir() {
            println!("cargo:rerun-if-changed={}", p.display());
            walk(root, &p, out);
        } else {
            let rel = p
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .replace('\\', "/");
            out.push(rel);
        }
    }
}
