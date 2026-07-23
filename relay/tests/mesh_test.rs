//! Integration tests for `/mesh/:owner_pk_hash` HTTP endpoints (plan 24 W1).
//!
//! After plan 24 fix (unified server), these tests mount the full router
//! (WS + `/health` + `/mesh`) — same surface a real client sees.

use std::net::SocketAddr;
use std::sync::Arc;

use base64::{
    Engine as _,
    engine::general_purpose::{STANDARD as B64, URL_SAFE_NO_PAD},
};
use ed25519_dalek::{Signer, SigningKey};
use relay::{
    AppState, FirehoseMetrics, MeshAuthCache, MeshStore, PeerRegistry, PresenceManager,
    RoomManager, build_router,
};
use reqwest::StatusCode;
use serde_json::{Value, json};
use tokio::net::TcpListener;

/// Spawns the unified relay on a random localhost port with a persistent
/// SQLite DB inside a `TempDir`. Returns `(base_url, temp_dir)` — keep the
/// dir alive for the duration of the test.
async fn spawn_relay() -> (String, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("mesh.db");
    let mesh = Arc::new(MeshStore::open(&db_path).unwrap());
    let presence = Arc::new(PresenceManager::new());
    let rooms = Arc::new(RoomManager::new());
    let metrics = Arc::new(FirehoseMetrics::new());
    let registry = Arc::new(PeerRegistry::new(
        presence.clone(),
        rooms.clone(),
        metrics.clone(),
    ));
    let mesh_auth = Arc::new(MeshAuthCache::new());
    let state = AppState {
        registry,
        presence,
        rooms,
        mesh,
        mesh_auth,
        metrics,
    };

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let app = build_router(state);
    tokio::spawn(async move {
        let _ = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await;
    });
    // Give axum a moment to start accepting.
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;
    (format!("http://127.0.0.1:{port}"), dir)
}

/// Computes `sha256(owner_pk)` as lowercase hex — matches the relay's
/// `owner_pk_hash` exactly.
fn pk_hash(pk: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let d = Sha256::digest(pk);
    let mut out = String::with_capacity(64);
    for b in d {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

fn full_member(remote_epk: &str) -> Value {
    json!({
        "remote_epk": remote_epk,
        "relay_url": "wss://relay.example.test",
        "paired_at": "2025-01-01T00:00:00.000Z",
    })
}

fn full_blob(owner_pk: &str, version: u64, members: Vec<Value>) -> Value {
    json!({
        "issued_at": 1_700_000_000_000_u64,
        "members": members,
        "owner_pk": owner_pk,
        "version": version,
    })
}

fn sign_blob(sk: &SigningKey, blob_value: &Value) -> (Value, Vec<u8>) {
    let blob_bytes = serde_json::to_vec(blob_value).unwrap();
    let sig = sk.sign(&blob_bytes);
    let envelope = json!({
        "blob": B64.encode(&blob_bytes),
        "sig": B64.encode(sig.to_bytes()),
    });
    (envelope, blob_bytes)
}

/// Builds a signed mesh envelope (wire format) using the given signing key
/// and version. The blob is canonical-ish JSON (we don't enforce canonical
/// for tests since we sign the bytes we produce here).
fn make_envelope(sk: &SigningKey, version: u64) -> (Value, String) {
    let pk_b64 = B64.encode(sk.verifying_key().to_bytes());
    let (envelope, _) = sign_blob(sk, &full_blob(&pk_b64, version, vec![]));
    let hash = pk_hash(&sk.verifying_key().to_bytes());
    (envelope, hash)
}

fn second_member_mut(blob: &mut Value) -> &mut serde_json::Map<String, Value> {
    blob.get_mut("members")
        .and_then(Value::as_array_mut)
        .and_then(|members| members.get_mut(1))
        .and_then(Value::as_object_mut)
        .expect("full fixture must contain a second member object")
}

#[tokio::test]
async fn url_safe_unpadded_owner_key_is_accepted_by_bytes() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::from_bytes(&[2_u8; 32]);
    let owner_pk_bytes = sk.verifying_key().to_bytes();
    let owner_pk = URL_SAFE_NO_PAD.encode(owner_pk_bytes);
    let member_pk = URL_SAFE_NO_PAD.encode([0xfb_u8; 32]);

    let blob = full_blob(&owner_pk, 1, vec![full_member(&member_pk)]);
    let (envelope, _) = sign_blob(&sk, &blob);
    let hash = pk_hash(&owner_pk_bytes);
    let client = reqwest::Client::new();

    let response = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&envelope)
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let stored: Value = client
        .get(format!("{base}/mesh/{hash}"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(stored["blob"], envelope["blob"]);
}

#[tokio::test]
async fn empty_members_and_nullable_or_string_nickname_are_accepted() {
    let (base, _dir) = spawn_relay().await;
    let member_pk = B64.encode([0x31_u8; 32]);
    let mut nullable_nickname = full_member(&member_pk);
    nullable_nickname["nickname"] = Value::Null;
    let mut string_nickname = full_member(&member_pk);
    string_nickname["nickname"] = json!("Workstation");
    let cases = [vec![], vec![nullable_nickname], vec![string_nickname]];
    let client = reqwest::Client::new();

    for (index, members) in cases.into_iter().enumerate() {
        let sk = SigningKey::from_bytes(&[0x10_u8 + index as u8; 32]);
        let owner_pk_bytes = sk.verifying_key().to_bytes();
        let owner_pk = B64.encode(owner_pk_bytes);
        let (envelope, _) = sign_blob(&sk, &full_blob(&owner_pk, 1, members));
        let response = client
            .post(format!("{base}/mesh/{}", pk_hash(&owner_pk_bytes)))
            .json(&envelope)
            .send()
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::OK,
            "compatibility case {index} must be accepted",
        );
    }
}

#[tokio::test]
async fn malformed_member_shape_rejects_whole_upload() {
    enum Malformation {
        MissingIssuedAt,
        NonIntegerIssuedAt,
        MissingMembers,
        NonArrayMembers,
        MissingRemoteEpk,
        MissingRelayUrl,
        MissingPairedAt,
        WrongTypedNickname,
        InvalidMemberKey,
        WrongLengthMemberKey,
    }

    let cases = [
        ("missing issued_at", Malformation::MissingIssuedAt),
        ("non-integer issued_at", Malformation::NonIntegerIssuedAt),
        ("missing members", Malformation::MissingMembers),
        ("non-array members", Malformation::NonArrayMembers),
        ("missing remote_epk", Malformation::MissingRemoteEpk),
        ("missing relay_url", Malformation::MissingRelayUrl),
        ("missing paired_at", Malformation::MissingPairedAt),
        ("wrong-typed nickname", Malformation::WrongTypedNickname),
        ("invalid member key", Malformation::InvalidMemberKey),
        (
            "wrong-length member key",
            Malformation::WrongLengthMemberKey,
        ),
    ];
    let (base, _dir) = spawn_relay().await;
    let client = reqwest::Client::new();
    let valid_member_a = B64.encode([0x31_u8; 32]);
    let valid_member_b = B64.encode([0x32_u8; 32]);

    for (index, (label, malformation)) in cases.into_iter().enumerate() {
        let sk = SigningKey::from_bytes(&[0x40_u8 + index as u8; 32]);
        let owner_pk_bytes = sk.verifying_key().to_bytes();
        let owner_pk = B64.encode(owner_pk_bytes);
        let mut blob = full_blob(
            &owner_pk,
            1,
            vec![full_member(&valid_member_a), full_member(&valid_member_b)],
        );

        match malformation {
            Malformation::MissingIssuedAt => {
                blob.as_object_mut().unwrap().remove("issued_at");
            }
            Malformation::NonIntegerIssuedAt => blob["issued_at"] = json!("not an integer"),
            Malformation::MissingMembers => {
                blob.as_object_mut().unwrap().remove("members");
            }
            Malformation::NonArrayMembers => blob["members"] = json!({}),
            Malformation::MissingRemoteEpk => {
                second_member_mut(&mut blob).remove("remote_epk");
            }
            Malformation::MissingRelayUrl => {
                second_member_mut(&mut blob).remove("relay_url");
            }
            Malformation::MissingPairedAt => {
                second_member_mut(&mut blob).remove("paired_at");
            }
            Malformation::WrongTypedNickname => {
                second_member_mut(&mut blob).insert("nickname".into(), json!(false));
            }
            Malformation::InvalidMemberKey => {
                second_member_mut(&mut blob).insert("remote_epk".into(), json!("not base64"));
            }
            Malformation::WrongLengthMemberKey => {
                second_member_mut(&mut blob)
                    .insert("remote_epk".into(), json!(B64.encode([7_u8; 31])));
            }
        }

        let (envelope, _) = sign_blob(&sk, &blob);
        let hash = pk_hash(&owner_pk_bytes);
        let response = client
            .post(format!("{base}/mesh/{hash}"))
            .json(&envelope)
            .send()
            .await
            .unwrap();
        let status = response.status();
        let body = response.text().await.unwrap();
        assert_eq!(status, StatusCode::BAD_REQUEST, "case {label}: {body}");

        let stored = client
            .get(format!("{base}/mesh/{hash}"))
            .send()
            .await
            .unwrap();
        assert_eq!(
            stored.status(),
            StatusCode::NOT_FOUND,
            "case {label} must not store a contribution",
        );
    }
}

#[tokio::test]
async fn post_v1_then_get_returns_v1() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let (env, hash) = make_envelope(&sk, 1);

    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: Value = resp.json().await.unwrap();
    assert_eq!(body["version"], 1);

    let resp = client
        .get(format!("{base}/mesh/{hash}"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: Value = resp.json().await.unwrap();
    assert_eq!(body["version"], 1);
    assert!(body["blob"].is_string());
    assert!(body["sig"].is_string());
}

#[tokio::test]
async fn post_v2_after_v1_advances_state() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());

    let (env1, hash) = make_envelope(&sk, 1);
    let (env2, _) = make_envelope(&sk, 2);

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env1)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env2)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    let body: Value = client
        .get(format!("{base}/mesh/{hash}"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(body["version"], 2);
}

#[tokio::test]
async fn post_stale_version_returns_409() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());

    let (env2, hash) = make_envelope(&sk, 2);
    let (env1, _) = make_envelope(&sk, 1);

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env2)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env1)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn post_same_version_returns_409() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());

    let (env, hash) = make_envelope(&sk, 7);

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();
    assert_eq!(
        r.status(),
        StatusCode::CONFLICT,
        "re-posting same version must be 409"
    );
}

#[tokio::test]
async fn get_with_since_below_current_returns_blob() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let (env, hash) = make_envelope(&sk, 5);

    let client = reqwest::Client::new();
    client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();

    let r = client
        .get(format!("{base}/mesh/{hash}?since=3"))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    let body: Value = r.json().await.unwrap();
    assert_eq!(body["version"], 5);
}

#[tokio::test]
async fn get_with_since_at_or_above_current_returns_304() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let (env, hash) = make_envelope(&sk, 5);

    let client = reqwest::Client::new();
    client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();

    let r = client
        .get(format!("{base}/mesh/{hash}?since=5"))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::NOT_MODIFIED);

    let r = client
        .get(format!("{base}/mesh/{hash}?since=999"))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::NOT_MODIFIED);
}

#[tokio::test]
async fn get_unknown_owner_returns_404() {
    let (base, _dir) = spawn_relay().await;
    let r = reqwest::get(format!("{base}/mesh/{}", "0".repeat(64)))
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn post_with_invalid_signature_returns_403() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let (mut env, hash) = make_envelope(&sk, 1);
    // Replace sig with random bytes.
    env["sig"] = json!(B64.encode([0u8; 64]));

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn post_with_url_hash_mismatch_returns_403() {
    let (base, _dir) = spawn_relay().await;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let (env, _real_hash) = make_envelope(&sk, 1);
    let bogus_hash = "f".repeat(64);

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{bogus_hash}"))
        .json(&env)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn post_with_bad_json_returns_400() {
    let (base, _dir) = spawn_relay().await;
    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{}", "0".repeat(64)))
        .header("content-type", "application/json")
        .body("{not valid json")
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn post_body_over_500kb_returns_413() {
    let (base, _dir) = spawn_relay().await;
    // 600 KB body — exceeds the 500 KB cap.
    let huge = "a".repeat(600 * 1024);
    let body = json!({"blob": huge, "sig": "AA"});

    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base}/mesh/{}", "0".repeat(64)))
        .json(&body)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn health_endpoint_returns_200_ok() {
    let (base, _dir) = spawn_relay().await;
    let r = reqwest::get(format!("{base}/health")).await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    assert_eq!(r.text().await.unwrap(), "OK");
}

/// Unified server: `/health`, `/mesh/:hash`, and WS upgrade all coexist on
/// the same port. Hits all three back-to-back to prove the routing.
#[tokio::test]
async fn unified_port_serves_health_mesh_and_ws() {
    let (base, _dir) = spawn_relay().await;
    let host_port = base.strip_prefix("http://").unwrap();

    // 1) /health → 200
    let r = reqwest::get(format!("{base}/health")).await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    // 2) GET /mesh/<unknown hash> → 404
    let r = reqwest::get(format!("{base}/mesh/{}", "0".repeat(64)))
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::NOT_FOUND);

    // 3) WebSocket upgrade succeeds on the same port (no /ws prefix).
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    let ws_url = format!("ws://{host_port}");
    let (mut ws, _) = connect_async(&ws_url)
        .await
        .expect("WS handshake must succeed");
    // Send something invalid as hello → relay drops connection cleanly,
    // proving the WS handler is wired.
    ws.send(Message::text("not a valid hello")).await.unwrap();
    let _ = ws.next().await; // expect None / close — either is fine
}
