#![cfg(unix)]
use serde_json::Value;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "cockpit-codex-launcher-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        for directory in ["app", "other-app", "real"] {
            std::fs::create_dir_all(root.join(directory)).unwrap();
        }
        symlink(env!("CARGO_BIN_EXE_cockpit"), root.join("app/cockpit")).unwrap();
        symlink("cockpit", root.join("app/codex")).unwrap();
        symlink("cockpit", root.join("app/cockpit-codex")).unwrap();
        symlink(env!("CARGO_BIN_EXE_cockpit"), root.join("other-app/codex")).unwrap();
        let real = root.join("real/codex");
        std::fs::write(&real, r#"#!/bin/sh
if [ "$1" = --help ]; then
  if [ "$FIXTURE_OLD_CODEX" != 1 ]; then printf '%s\n' '--no-daemon'; fi
  exit 0
fi
exec /usr/bin/python3 -c 'import json,os,sys; print(json.dumps({"pid":os.getpid(),"args":sys.argv[1:]}));sys.exit(int(os.environ.get("FIXTURE_EXIT","0")))' "$@"
"#).unwrap();
        std::fs::set_permissions(real, std::fs::Permissions::from_mode(0o755)).unwrap();
        Self(root)
    }
    fn command(&self, scoped: bool) -> Command {
        let mut command = Command::new(self.0.join("app/cockpit-codex"));
        command
            .env(
                "PATH",
                std::env::join_paths([
                    self.0.join("app"),
                    self.0.join("other-app"),
                    self.0.join("real"),
                ])
                .unwrap(),
            )
            .env_remove("COCKPIT_PANE_ID")
            .env_remove("COCKPIT_TAB_ID")
            .env_remove("FIXTURE_OLD_CODEX")
            .env_remove("FIXTURE_EXIT")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if scoped {
            command.env("COCKPIT_TAB_ID", "fixture");
        }
        command
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn normal_codex_command_is_transparent_and_keeps_process_identity() {
    let fixture = Fixture::new();
    let child = fixture
        .command(true)
        .args(["--model", "fixture", "a prompt with 'quotes'", "日本語", ""])
        .spawn()
        .unwrap();
    let pid = child.id();
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["pid"], pid);
    assert_eq!(
        value["args"],
        serde_json::json!([
            "--no-daemon",
            "--model",
            "fixture",
            "a prompt with 'quotes'",
            "日本語",
            ""
        ])
    );
}

#[test]
fn explicit_modes_exit_codes_and_old_versions_are_preserved() {
    let fixture = Fixture::new();
    for args in [
        vec!["exec", "prompt"],
        vec!["resume", "id", "--remote", "ws://server"],
        vec!["fork", "id", "--no-daemon"],
    ] {
        let output = fixture
            .command(true)
            .args(&args)
            .env("FIXTURE_EXIT", "37")
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(37));
        let value: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(value["args"], serde_json::json!(args));
    }
    let old = fixture
        .command(true)
        .arg("resume")
        .env("FIXTURE_OLD_CODEX", "1")
        .output()
        .unwrap();
    let value: Value = serde_json::from_slice(&old.stdout).unwrap();
    assert_eq!(value["args"], serde_json::json!(["resume"]));
}

#[test]
fn outside_cockpit_codex_is_unmodified() {
    let fixture = Fixture::new();
    let output = fixture.command(false).arg("resume").output().unwrap();
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["args"], serde_json::json!(["resume"]));
}
