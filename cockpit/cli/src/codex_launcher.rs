//! Terminal-scoped `codex` entry point. Replaces itself with the real CLI so
//! stdin, TTY, signals, process identity, arguments and exit status stay native.
use std::ffi::OsString;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub fn run(args: Vec<OsString>) -> ! {
    let executable = find_codex();
    let executable = match executable {
        Some(path) => path,
        None => {
            eprintln!("codex: executable not found outside the Cockpit launcher");
            std::process::exit(127);
        }
    };
    let in_cockpit = ["COCKPIT_TAB_ID", "COCKPIT_PANE_ID"]
        .iter()
        .any(|key| std::env::var_os(key).is_some_and(|value| !value.is_empty()));
    let mut command = Command::new(&executable);
    if in_cockpit && needs_private_server(&args) && supports_private_server(&executable) {
        command.arg("--no-daemon");
    }
    let error = command.args(args).exec();
    eprintln!("codex: {error}");
    std::process::exit(126);
}

fn find_codex() -> Option<PathBuf> {
    let own = std::env::current_exe().ok()?.canonicalize().ok()?;
    for directory in std::env::split_paths(&std::env::var_os("PATH")?) {
        let candidate = directory.join("codex");
        let Ok(real) = candidate.canonicalize() else {
            continue;
        };
        let Ok(metadata) = real.metadata() else {
            continue;
        };
        if real != own && metadata.is_file() && metadata.permissions().mode() & 0o111 != 0 {
            return Some(candidate);
        }
    }
    None
}

fn needs_private_server(args: &[OsString]) -> bool {
    let mut values = args.iter();
    let mut mode = None;
    while let Some(value) = values.next() {
        let value = value.to_string_lossy();
        if value == "--" {
            break;
        }
        if matches!(
            value.as_ref(),
            "--remote" | "--no-daemon" | "--help" | "-h" | "--version" | "-V"
        ) || value.starts_with("--remote=")
        {
            return false;
        }
        if matches!(
            value.as_ref(),
            "--config"
                | "-c"
                | "--model"
                | "-m"
                | "--profile"
                | "-p"
                | "--cd"
                | "-C"
                | "--image"
                | "-i"
                | "--sandbox"
                | "-s"
                | "--ask-for-approval"
                | "-a"
                | "--add-dir"
                | "--enable"
                | "--disable"
                | "--remote-auth-token-env"
        ) {
            values.next();
            continue;
        }
        if value.starts_with('-') {
            continue;
        }
        if mode.is_none() {
            mode = Some(value.into_owned());
        }
    }
    !matches!(
        mode.as_deref().unwrap_or(""),
        "exec"
            | "e"
            | "review"
            | "login"
            | "logout"
            | "auth"
            | "app"
            | "app-server"
            | "exec-server"
            | "mcp"
            | "mcp-server"
            | "completion"
            | "features"
            | "debug"
            | "sandbox"
            | "remote-control"
            | "queue"
            | "help"
    )
}

fn supports_private_server(executable: &Path) -> bool {
    // Feature-detect rather than breaking older installed Codex releases.
    let Ok(mut child) = Command::new(executable)
        .arg("--help")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => {
                return child.wait_with_output().ok().is_some_and(|out| {
                    out.status.success()
                        && String::from_utf8_lossy(&out.stdout).contains("--no-daemon")
                })
            }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn needs(args: &[&str]) -> bool {
        needs_private_server(&args.iter().map(OsString::from).collect::<Vec<_>>())
    }
    #[test]
    fn interactive_launch_resume_and_fork_use_private_server() {
        for args in [
            vec![],
            vec!["resume", "id"],
            vec!["fork", "id"],
            vec!["--model", "exec"],
            vec!["--", "--remote"],
            vec!["a prompt with spaces"],
        ] {
            assert!(needs(&args), "{args:?}");
        }
    }
    #[test]
    fn explicit_remote_flags_and_noninteractive_commands_are_preserved() {
        for args in [
            vec!["exec", "prompt"],
            vec!["app-server"],
            vec!["--remote=unix://server"],
            vec!["--remote", "ws://server"],
            vec!["--no-daemon"],
            vec!["fork", "id", "--no-daemon"],
            vec!["resume", "id", "--remote", "ws://server"],
            vec!["--help"],
            vec!["--config", "key=value", "exec", "prompt"],
        ] {
            assert!(!needs(&args), "{args:?}");
        }
    }
}
