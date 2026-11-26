use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "cockpit-native-open-{}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(root.join(".cockpit")).unwrap();
        std::fs::write(root.join("equipe 日本.orc"), "{}").unwrap();
        Self(root)
    }
    fn file(&self) -> String {
        self.0
            .join("equipe 日本.orc")
            .to_string_lossy()
            .into_owned()
    }
    fn endpoint(&self, name: &str, port: u16) {
        std::fs::write(
            self.0.join(".cockpit").join(name),
            json!({"port":port,"tok":"native-test-token"}).to_string(),
        )
        .unwrap();
    }
    fn command(&self, flavor: &str, file: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_cockpit"));
        command
            .args(["--forward-native-open", flavor, file])
            .env("COCKPIT_ISOLATED_ROOT", &self.0)
            .env("HOME", &self.0)
            .env("USERPROFILE", &self.0)
            .env("COCKPIT_STATUS_PORT", "9")
            .env("COCKPIT_STATUS_TOKEN", "inherited-wrong-token")
            .env("COCKPIT_TAB_ID", "foreign-owned-terminal")
            .env("COCKPIT_PANE_ID", "foreign-owned-terminal");
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }
        command
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn server(reply: &'static str) -> (u16, thread::JoinHandle<Option<Value>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    listener.set_nonblocking(true).unwrap();
    let worker = thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    // Windows accepted sockets inherit the listener mode.
                    // The fixture polls accept, then reads one blocking request.
                    stream.set_nonblocking(false).unwrap();
                    stream
                        .set_write_timeout(Some(Duration::from_secs(2)))
                        .unwrap();
                    stream
                        .set_read_timeout(Some(Duration::from_secs(2)))
                        .unwrap();
                    let mut line = String::new();
                    BufReader::new(stream.try_clone().unwrap())
                        .read_line(&mut line)
                        .unwrap();
                    let request = serde_json::from_str(&line).unwrap();
                    // Exercise a reply arriving across multiple reads.
                    stream.write_all(&reply.as_bytes()[..3]).unwrap();
                    thread::sleep(Duration::from_millis(10));
                    stream.write_all(&reply.as_bytes()[3..]).unwrap();
                    return Some(request);
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    if Instant::now() >= deadline {
                        return None;
                    }
                    thread::sleep(Duration::from_millis(5));
                }
                Err(error) => panic!("accept: {error}"),
            }
        }
    });
    (port, worker)
}
fn quiet_failure(output: Output) {
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}

#[test]
fn forwards_unicode_file_with_exact_auth_and_no_inherited_origin() {
    let fixture = Fixture::new();
    let (port, worker) = server("{\"ok\":true}\n");
    fixture.endpoint("status.json", port);
    let file = fixture.file();
    let output = fixture.command("release", &file).output().unwrap();
    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    let request = worker.join().unwrap().unwrap();
    assert_eq!(request["type"], "cmd");
    assert_eq!(request["cmd"], "open-document");
    assert_eq!(request["tok"], "native-test-token");
    assert_eq!(
        Path::new(request["args"]["paths"][0].as_str().unwrap()),
        Path::new(&file)
    );
    assert!(request.get("callerTabId").is_none());
    assert!(request.get("tabId").is_none());
}
#[test]
fn debug_mode_uses_only_debug_endpoint() {
    let fixture = Fixture::new();
    let (port, worker) = server("{\"ok\":true}\n");
    fixture.endpoint("status-debug.json", port);
    let output = fixture.command("debug", &fixture.file()).output().unwrap();
    assert!(output.status.success());
    assert!(worker.join().unwrap().is_some());
}
#[test]
fn release_never_falls_back_to_debug_or_inherited_endpoint() {
    let fixture = Fixture::new();
    let (port, worker) = server("{\"ok\":true}\n");
    fixture.endpoint("status-debug.json", port);
    quiet_failure(
        fixture
            .command("release", &fixture.file())
            .output()
            .unwrap(),
    );
    assert!(worker.join().unwrap().is_none());
}
#[test]
fn invalid_isolated_root_never_falls_back_to_home() {
    let fixture = Fixture::new();
    let (port, worker) = server("{\"ok\":true}\n");
    fixture.endpoint("status.json", port);
    quiet_failure(
        fixture
            .command("release", &fixture.file())
            .env("COCKPIT_ISOLATED_ROOT", "relative-native-root")
            .output()
            .unwrap(),
    );
    assert!(worker.join().unwrap().is_none());
}
#[test]
fn malformed_metadata_and_missing_files_fail_without_output() {
    let fixture = Fixture::new();
    let endpoint = fixture.0.join(".cockpit/status.json");
    for value in [
        "invalid",
        "{\"port\":65536,\"tok\":\"x\"}",
        "{\"port\":1,\"tok\":\"\"}",
    ] {
        std::fs::write(&endpoint, value).unwrap();
        quiet_failure(
            fixture
                .command("release", &fixture.file())
                .output()
                .unwrap(),
        );
    }
    quiet_failure(
        fixture
            .command("release", "missing-native-file.orc")
            .output()
            .unwrap(),
    );
    quiet_failure(
        fixture
            .command("other-flavor", &fixture.file())
            .output()
            .unwrap(),
    );
}
#[test]
fn negative_acknowledgement_does_not_claim_delivery() {
    let fixture = Fixture::new();
    let (port, worker) = server("{\"ok\":false}\n");
    fixture.endpoint("status.json", port);
    quiet_failure(
        fixture
            .command("release", &fixture.file())
            .output()
            .unwrap(),
    );
    assert!(worker.join().unwrap().is_some());
}
