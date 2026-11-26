//! Windows loopback contract. Unix uses the same request path in wire.rs.
#![cfg(windows)]

use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::process::Command;

fn request(args: &[&str], legacy_env: bool) -> Value {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(10)))
            .unwrap();
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let mut stream = reader.into_inner();
        stream.write_all(b"{\"ok\":true,\"data\":[]}\n").unwrap();
        serde_json::from_str::<Value>(&line).unwrap()
    });
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_cockpit"));
    cmd.args(args)
        .env("COCKPIT_STATUS_PORT", port.to_string())
        .env("COCKPIT_STATUS_TOKEN", "test-token")
        .env_remove("COCKPIT_STATUS_SOCK")
        .env_remove("COCKPIT_TAB_ID")
        .env_remove("COCKPIT_PANE_ID")
        .env(
            if legacy_env {
                "COCKPIT_PANE_ID"
            } else {
                "COCKPIT_TAB_ID"
            },
            "sender",
        );
    let output = cmd.output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    server.join().unwrap()
}

#[test]
fn sender_is_independent_of_explicit_and_focused_targets() {
    for target in ["other-terminal", "@focused"] {
        let req = request(&["send", "--tab-id", target, "hello"], false);
        assert_eq!(req["callerTabId"], "sender");
        assert_eq!(req["tabId"], target);
        assert_eq!(req["args"]["sourceTabId"], "sender");
    }
}

#[test]
fn list_includes_origin_even_without_a_destination() {
    let req = request(&["list-tabs", "--json"], false);
    assert_eq!(req["cmd"], "list-panes");
    assert_eq!(req["callerTabId"], "sender");
}

#[test]
fn legacy_pane_environment_supplies_origin() {
    let req = request(&["list-tabs", "--json"], true);
    assert_eq!(req["callerTabId"], "sender");
}
