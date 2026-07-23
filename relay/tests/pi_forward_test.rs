//! Plan 25 Wave A — integration tests for Pi-to-Pi envelope forwarding.
//!
//! Each test spins up the full unified relay (WS + HTTP), publishes one or
//! more Owner-signed mesh blobs that determine membership, connects Pi-A
//! (and sometimes Pi-B) via WebSocket, and asserts the forwarding /
//! transport-error behavior.

mod common;
use common::{connect_and_auth_with_key, start_relay};

use std::sync::Arc;

use base64::{
    Engine as _,
    engine::general_purpose::{STANDARD as B64, URL_SAFE_NO_PAD},
};
use ed25519_dalek::{Signer, SigningKey};
use futures_util::{SinkExt, StreamExt};
use relay::handlers::pi_forward::{PiForwardResult, handle_pi_envelope};
use relay::{
    FirehoseMetrics, MeshAuthCache, MeshStore, PeerRegistry, PresenceManager, RoomManager, RoomMeta,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio_tungstenite::tungstenite::Message;

fn random_key() -> SigningKey {
    SigningKey::generate(&mut rand::thread_rng())
}

fn pk_hash_hex(pk: &[u8]) -> String {
    let d = Sha256::digest(pk);
    let mut s = String::with_capacity(64);
    for b in d {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn mesh_member(remote_epk: &str) -> Value {
    json!({
        "remote_epk": remote_epk,
        "relay_url": "wss://relay.example.test",
        "paired_at": "2025-01-01T00:00:00.000Z",
    })
}

fn owner_blob(owner_pk: &str, members: Vec<Value>, version: u64) -> Value {
    json!({
        "owner_pk": owner_pk,
        "version": version,
        "members": members,
        "issued_at": 1_700_000_000_000_u64,
    })
}

fn test_registry() -> PeerRegistry {
    PeerRegistry::new(
        Arc::new(PresenceManager::new()),
        Arc::new(RoomManager::new()),
        Arc::new(FirehoseMetrics::new()),
    )
}

fn test_room_meta() -> RoomMeta {
    RoomMeta {
        room_id: "main".to_string(),
        name: None,
        cwd: None,
        model: None,
        thinking: None,
        working: false,
        started_at: 0,
    }
}

fn transport_error_frame(result: PiForwardResult) -> Value {
    match result {
        PiForwardResult::TransportError(axum::extract::ws::Message::Text(text)) => {
            serde_json::from_str(&text).unwrap()
        }
        PiForwardResult::TransportError(_) => panic!("transport error must be a text frame"),
        PiForwardResult::Forwarded => panic!("expected transport error, got forwarded"),
    }
}

fn parse_uuid_bytes(value: &str) -> Option<[u8; 16]> {
    if value.len() != 36 {
        return None;
    }

    let mut parsed = [0_u8; 16];
    let mut nibble_index = 0;
    for (index, byte) in value.bytes().enumerate() {
        if matches!(index, 8 | 13 | 18 | 23) {
            if byte != b'-' {
                return None;
            }
            continue;
        }

        let nibble = match byte {
            b'0'..=b'9' => byte - b'0',
            b'a'..=b'f' => byte - b'a' + 10,
            b'A'..=b'F' => byte - b'A' + 10,
            _ => return None,
        };
        let parsed_byte = &mut parsed[nibble_index / 2];
        if nibble_index % 2 == 0 {
            *parsed_byte = nibble << 4;
        } else {
            *parsed_byte |= nibble;
        }
        nibble_index += 1;
    }

    (nibble_index == 32).then_some(parsed)
}

fn assert_generated_uuid_v4(value: &Value) {
    let id = value
        .as_str()
        .expect("generated transport error id must be a string");
    let bytes = parse_uuid_bytes(id).unwrap_or_else(|| {
        panic!(
            "generated transport error id {id:?} must use case-insensitive 8-4-4-4-12 UUID syntax"
        )
    });
    assert_eq!(
        bytes[6] & 0xf0,
        0x40,
        "generated transport error id must have UUID version 4"
    );
    assert_eq!(
        bytes[8] & 0xc0,
        0x80,
        "generated transport error id must have the RFC UUID variant"
    );
}

fn assert_transport_error_shape(frame: &Value, expected_reason: &str) {
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], "_relay");

    let envelope = frame["envelope"]
        .as_object()
        .expect("transport error envelope must be an object");
    for field in ["from", "to"] {
        let address = envelope
            .get(field)
            .and_then(Value::as_str)
            .unwrap_or_else(|| panic!("transport error {field} must be a string"));
        assert!(
            !address.is_empty(),
            "transport error {field} must be non-empty"
        );
    }

    assert_generated_uuid_v4(
        envelope
            .get("id")
            .expect("transport error must contain an id"),
    );
    let re = envelope
        .get("re")
        .expect("transport error must contain an explicit re");
    assert!(
        re.is_null()
            || re
                .as_str()
                .is_some_and(|correlation| parse_uuid_bytes(correlation).is_some()),
        "transport error re must be a syntactically valid UUID or null"
    );

    let body = envelope
        .get("body")
        .and_then(Value::as_object)
        .expect("transport error body must be present and be an object");
    assert_eq!(
        body.get("type").and_then(Value::as_str),
        Some("transport_error")
    );
    let reason = body
        .get("reason")
        .and_then(Value::as_str)
        .expect("transport error reason must be a string");
    assert!(
        matches!(reason, "offline" | "not_authorized" | "bad_envelope"),
        "transport error reason must be closed"
    );
    assert_eq!(reason, expected_reason);
}

/// Publishes an Owner-signed `mesh_versions` blob via the relay's HTTP API.
/// `members` is the list of Pi-pubkeys (base64 strings) that this Owner
/// authorizes as siblings.
async fn publish_owner_blob(
    base_http: &str,
    owner_sk: &SigningKey,
    members: &[&str],
    version: u64,
) {
    let owner_pk_bytes = owner_sk.verifying_key().to_bytes();
    let owner_pk_b64 = B64.encode(owner_pk_bytes);
    let members_json = members.iter().map(|member| mesh_member(member)).collect();
    let blob = owner_blob(&owner_pk_b64, members_json, version);
    let blob_bytes = serde_json::to_vec(&blob).unwrap();
    let sig = owner_sk.sign(&blob_bytes);
    let envelope = json!({
        "blob": B64.encode(&blob_bytes),
        "sig": B64.encode(sig.to_bytes()),
    });
    let hash = pk_hash_hex(&owner_pk_bytes);
    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base_http}/mesh/{hash}"))
        .json(&envelope)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 200, "mesh blob publish must succeed");
}

/// Sends a `pi_envelope` frame from an already-authenticated Pi WS.
async fn send_pi_envelope(ws: &mut common::WsStream, to_pc: &str, envelope: Value) {
    ws.send(Message::text(
        json!({
            "type": "pi_envelope",
            "to_pc": to_pc,
            "envelope": envelope,
        })
        .to_string(),
    ))
    .await
    .unwrap();
}

/// Receives the next text frame (with timeout) and parses as JSON.
async fn recv_json(ws: &mut common::WsStream, label: &str) -> Value {
    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(2), ws.next())
        .await
        .unwrap_or_else(|_| panic!("{label} timed out waiting for frame"))
        .unwrap()
        .unwrap();
    serde_json::from_str(msg.to_text().unwrap())
        .unwrap_or_else(|e| panic!("{label} got non-JSON frame: {e}"))
}

async fn await_registered(ws: &mut common::WsStream, label: &str) {
    ws.send(Message::text(
        json!({"type": "presence_check", "peers": []}).to_string(),
    ))
    .await
    .unwrap();

    assert_eq!(
        recv_json(ws, label).await,
        json!({"type": "presence", "states": []}),
    );
}

async fn assert_forwarded(
    sender: &mut common::WsStream,
    receiver: &mut common::WsStream,
    target_pc: &str,
    sender_pc: &str,
    id: &str,
) {
    let envelope = json!({
        "from": "source:agent",
        "to": "target:agent",
        "id": id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(sender, target_pc, envelope.clone()).await;

    let frame = recv_json(receiver, id).await;
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], sender_pc);
    assert_eq!(frame["envelope"], envelope);
}

fn normalize_generated_transport_error_id(mut frame: Value) -> Value {
    assert!(frame["envelope"]["id"].is_string());
    frame["envelope"]["id"] = Value::String("<generated-id>".to_string());
    frame
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

/// Happy path: Pi-A and Pi-B belong to the same Owner's mesh and both are
/// online. Envelope from A arrives at B verbatim, wrapped as `pi_envelope_in`
/// with `from_pc = peer_a_pk`.
#[tokio::test]
async fn direct_owner_blob_co_membership_envelope_delivered_verbatim() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": "00000000-0000-4000-8000-000000000101",
        "re": null,
        "body": { "type": "hello", "text": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, envelope.clone()).await;

    let frame = recv_json(&mut ws_b, "ws_b").await;
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(
        frame["from_pc"], peer_a,
        "must carry authenticated sender pk"
    );
    assert_eq!(
        frame["envelope"], envelope,
        "envelope must be forwarded verbatim"
    );
}

#[tokio::test]
async fn each_direct_owner_blob_pair_forwards_in_both_directions() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner_ab = random_key();
    let owner_bc = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let sk_c = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());
    let peer_c = B64.encode(sk_c.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner_ab, &[&peer_a, &peer_b], 1).await;
    publish_owner_blob(&base_http, &owner_bc, &[&peer_b, &peer_c], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;
    let (mut ws_c, _) = connect_and_auth_with_key(port, &sk_c).await;
    await_registered(&mut ws_a, "ws_a registration barrier").await;
    await_registered(&mut ws_b, "ws_b registration barrier").await;
    await_registered(&mut ws_c, "ws_c registration barrier").await;

    assert_forwarded(
        &mut ws_a,
        &mut ws_b,
        &peer_b,
        &peer_a,
        "00000000-0000-4000-8000-000000000001",
    )
    .await;
    assert_forwarded(
        &mut ws_b,
        &mut ws_a,
        &peer_a,
        &peer_b,
        "00000000-0000-4000-8000-000000000002",
    )
    .await;
    assert_forwarded(
        &mut ws_b,
        &mut ws_c,
        &peer_c,
        &peer_b,
        "00000000-0000-4000-8000-000000000003",
    )
    .await;
    assert_forwarded(
        &mut ws_c,
        &mut ws_b,
        &peer_b,
        &peer_c,
        "00000000-0000-4000-8000-000000000004",
    )
    .await;
}

#[tokio::test]
async fn url_safe_unpadded_members_and_target_route_to_canonical_peer() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = SigningKey::from_bytes(&[2_u8; 32]);
    let sk_b = SigningKey::from_bytes(&[4_u8; 32]);
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_a_url_safe = URL_SAFE_NO_PAD.encode(sk_a.verifying_key().to_bytes());
    let peer_b_url_safe = URL_SAFE_NO_PAD.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a_url_safe, &peer_b_url_safe], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;
    await_registered(&mut ws_b, "ws_b registration barrier").await;

    let envelope = json!({
        "from": "source:agent",
        "to": "target:agent",
        "id": "00000000-0000-4000-8000-000000000020",
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b_url_safe, envelope.clone()).await;

    let frame = recv_json(&mut ws_b, "canonical peer delivery").await;
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], peer_a);
    assert_eq!(frame["envelope"], envelope);
}

#[tokio::test]
async fn invalid_target_keys_fail_closed_as_bad_envelope() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    publish_owner_blob(&base_http, &owner, &[&peer_a], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    await_registered(&mut ws_a, "ws_a registration barrier").await;
    let invalid_targets = [
        "not base64".to_string(),
        B64.encode([7_u8; 31]),
        B64.encode([7_u8; 33]),
    ];

    for (index, target) in invalid_targets.into_iter().enumerate() {
        let envelope = json!({
            "from": "source:agent",
            "to": "target:agent",
            "id": format!("00000000-0000-4000-8000-{index:012}"),
            "re": null,
            "body": { "type": "ping" },
        });
        send_pi_envelope(&mut ws_a, &target, envelope).await;
        let frame = recv_json(&mut ws_a, "invalid target transport error").await;
        assert_transport_error_shape(&frame, "bad_envelope");
        assert_eq!(
            frame["envelope"]["re"],
            format!("00000000-0000-4000-8000-{index:012}"),
            "invalid target {target:?} must preserve correlation",
        );
    }
}

/// Pi-B is NOT connected when A sends. Relay synthesizes a transport_error
/// envelope and returns it to A as `pi_envelope_in`. Body carries
/// `type=transport_error, reason=offline` and `re` matches the original id.
#[tokio::test]
async fn pi_b_offline_returns_transport_error_offline() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    // Only A connects — B is offline.
    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;

    let request_id = "8f14e45f-ea5e-4f2d-a7c3-6d7f8a9b0c1d";
    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": request_id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, envelope).await;

    let frame = recv_json(&mut ws_a, "ws_a transport_error").await;
    assert_transport_error_shape(&frame, "offline");
    assert_eq!(frame["envelope"]["re"], request_id, "must correlate via re");
    assert_eq!(frame["envelope"]["from"], "_relay");
    assert_eq!(frame["envelope"]["to"], "casa:sess-3");
}

/// Pi-A and Pi-B belong to DIFFERENT Owners. The relay's mesh authorization
/// rejects the forward; A gets `transport_error: not_authorized`.
#[tokio::test]
async fn no_owner_blob_lists_both_pis_returns_not_authorized() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner_1 = random_key();
    let owner_2 = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    // Two separate Owners, each with just one Pi in their mesh.
    publish_owner_blob(&base_http, &owner_1, &[&peer_a], 1).await;
    publish_owner_blob(&base_http, &owner_2, &[&peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut _ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    let request_id = "2c1a9f60-1234-4abc-9def-0123456789ab";
    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": request_id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, envelope).await;

    let frame = recv_json(&mut ws_a, "ws_a transport_error").await;
    assert_transport_error_shape(&frame, "not_authorized");
    assert_eq!(frame["envelope"]["re"], request_id);
}

#[tokio::test]
async fn not_authorized_does_not_reveal_target_presence() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner_a = random_key();
    let owner_b = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner_a, &[&peer_a], 1).await;
    publish_owner_blob(&base_http, &owner_b, &[&peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let envelope = json!({
        "from": "source:agent",
        "to": "target:agent",
        "id": "00000000-0000-4000-8000-000000000010",
        "re": null,
        "body": { "type": "ping" },
    });

    send_pi_envelope(&mut ws_a, &peer_b, envelope.clone()).await;
    let offline_error = recv_json(&mut ws_a, "offline unauthorized target").await;
    assert_eq!(
        offline_error["envelope"]["body"]["reason"],
        "not_authorized"
    );

    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;
    await_registered(&mut ws_b, "ws_b registration barrier").await;
    send_pi_envelope(&mut ws_a, &peer_b, envelope).await;
    let online_error = recv_json(&mut ws_a, "online unauthorized target").await;
    assert_eq!(online_error["envelope"]["body"]["reason"], "not_authorized");

    assert_eq!(
        normalize_generated_transport_error_id(offline_error),
        normalize_generated_transport_error_id(online_error),
    );
    assert!(
        tokio::time::timeout(tokio::time::Duration::from_millis(200), ws_b.next())
            .await
            .is_err(),
        "online unauthorized target must not receive a frame",
    );
}

#[tokio::test]
async fn stored_malformed_member_shape_invalidates_whole_owner() {
    enum Malformation {
        MissingRequiredField,
        WrongTypedNickname,
        MalformedMemberKey,
    }

    let cases = [
        ("missing relay_url", Malformation::MissingRequiredField),
        ("wrong-typed nickname", Malformation::WrongTypedNickname),
        ("malformed member key", Malformation::MalformedMemberKey),
    ];

    for (index, (label, malformation)) in cases.into_iter().enumerate() {
        let a = B64.encode([0x20_u8 + index as u8; 32]);
        let b = B64.encode([0x30_u8 + index as u8; 32]);
        let c = B64.encode([0x40_u8 + index as u8; 32]);
        let mut members = vec![mesh_member(&a), mesh_member(&b), mesh_member(&c)];
        let malformed_member = members[2]
            .as_object_mut()
            .expect("full member fixture must be an object");
        match malformation {
            Malformation::MissingRequiredField => {
                malformed_member.remove("relay_url");
            }
            Malformation::WrongTypedNickname => {
                malformed_member.insert("nickname".to_string(), json!(false));
            }
            Malformation::MalformedMemberKey => {
                malformed_member.insert("remote_epk".to_string(), json!("not base64"));
            }
        }

        let owner_pk = [0x70_u8 + index as u8; 32];
        let blob = owner_blob(&B64.encode(owner_pk), members, 1);
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert(
                &pk_hash_hex(&owner_pk),
                &owner_pk,
                1,
                &blob_bytes,
                &[0_u8; 64],
                0,
            )
            .unwrap();

        let registry = test_registry();
        let (tx_b, mut rx_b) = tokio::sync::mpsc::unbounded_channel();
        let _conn_id = registry.register(b.clone(), test_room_meta(), tx_b).await;
        let frame = json!({
            "type": "pi_envelope",
            "to_pc": b,
            "envelope": {
                "from": "source:agent",
                "to": "target:agent",
                "id": format!("00000000-0000-4000-8000-{index:012}"),
                "re": null,
                "body": { "type": "ping" },
            },
        });

        let error = transport_error_frame(
            handle_pi_envelope(
                &a,
                &frame,
                &registry,
                Arc::new(store),
                Arc::new(MeshAuthCache::new()),
            )
            .await,
        );
        assert_eq!(
            error["envelope"]["body"]["reason"], "not_authorized",
            "case {label} must skip the whole Owner contribution",
        );
        assert!(
            rx_b.try_recv().is_err(),
            "case {label} must not partially authorize forwarding",
        );
    }
}

/// Malformed `pi_envelope` (missing `to_pc` / `envelope`): relay returns
/// `transport_error: bad_envelope` to A. The error envelope's `re` is null
/// because we can't recover the original id.
#[tokio::test]
async fn malformed_pi_envelope_returns_transport_error_bad_envelope() {
    let port = start_relay().await;

    let sk_a = random_key();
    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;

    // No `to_pc`, no `envelope` — pure stub.
    ws_a.send(Message::text(json!({ "type": "pi_envelope" }).to_string()))
        .await
        .unwrap();

    let frame = recv_json(&mut ws_a, "ws_a bad_envelope").await;
    assert_transport_error_shape(&frame, "bad_envelope");
    assert!(
        frame["envelope"]["re"].is_null(),
        "re must be null when original id is unrecoverable"
    );
}
