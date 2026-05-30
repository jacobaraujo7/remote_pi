mod common;
use common::{
    connect_and_auth, connect_and_auth_with_key, connect_and_auth_with_room, start_relay,
};

use ed25519_dalek::SigningKey;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tokio_tungstenite::tungstenite::Message;

fn random_key() -> SigningKey {
    SigningKey::generate(&mut rand::thread_rng())
}

/// B subscribes to Pi's rooms. Pi connects with a named room → B gets room_announced.
#[tokio::test]
async fn subscribe_rooms_then_peer_opens_room_pushes_announced() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    // App (B) subscribes to Pi's room events before Pi connects.
    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi connects with a specific room.
    let (_ws_pi, _) = connect_and_auth_with_room(port, &sk_pi, "aB12CD34eF56").await;

    // App must receive room_announced.
    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_announced")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_announced", "got: {v}");
    assert_eq!(v["peer"], peer_pi);
    assert_eq!(v["room_id"], "aB12CD34eF56");
    assert!(
        v["started_at"].as_i64().is_some(),
        "started_at must be epoch-ms"
    );
}

/// Pi connects; App subscribes then Pi disconnects → App gets room_ended.
#[tokio::test]
async fn peer_disconnects_pushes_room_ended() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (ws_pi, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    drop(ws_pi);
    tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_ended")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_ended", "got: {v}");
    assert_eq!(v["peer"], peer_pi);
    assert_eq!(v["room_id"], "work");
    assert!(
        v["since_ts"].as_i64().is_some(),
        "since_ts must be epoch-ms"
    );
}

/// rooms_check for a peer with no active connections → rooms: [].
#[tokio::test]
async fn rooms_check_empty_for_offline_peer() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for rooms response")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "rooms");
    assert_eq!(v["peer"], peer_pi);
    assert_eq!(v["rooms"].as_array().unwrap().len(), 0);
}

/// rooms_check while two rooms are active → both room_ids appear in snapshot.
#[tokio::test]
async fn rooms_check_returns_all_active_rooms() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (_ws_pi_work, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;
    let (_ws_pi_home, _) = connect_and_auth_with_room(port, &sk_pi, "home").await;

    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for rooms response")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "rooms");
    let rooms = v["rooms"].as_array().unwrap();
    assert_eq!(rooms.len(), 2, "expected 2 rooms, got: {rooms:?}");
    let ids: Vec<&str> = rooms
        .iter()
        .map(|r| r["room_id"].as_str().unwrap())
        .collect();
    assert!(ids.contains(&"work"), "missing 'work'");
    assert!(ids.contains(&"home"), "missing 'home'");
}

/// Messages route to the exact (peer, room) — a different room of the same peer does NOT receive them.
#[tokio::test]
async fn forward_routes_by_room_not_just_peer() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi_work, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;
    let (mut ws_pi_home, _) = connect_and_auth_with_room(port, &sk_pi, "home").await;

    let (mut ws_app, peer_app) = connect_and_auth(port).await;

    let ct = "dGVzdA=="; // "test" base64

    // App sends to Pi's "work" room.
    ws_app
        .send(Message::text(
            json!({"peer": peer_pi, "room": "work", "ct": ct}).to_string(),
        ))
        .await
        .unwrap();

    // Pi's "work" room must receive it.
    let received = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_pi_work.next())
        .await
        .expect("timed out waiting for message at work room")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(received.to_text().unwrap()).unwrap();
    assert_eq!(v["ct"], ct);
    assert_eq!(v["peer"], peer_app, "relay must rewrite peer to sender");
    assert_eq!(v["room"], "main", "relay must include sender's room");

    // Pi's "home" room must NOT receive anything.
    let spurious =
        tokio::time::timeout(tokio::time::Duration::from_millis(150), ws_pi_home.next()).await;
    assert!(
        spurious.is_err(),
        "home room must not receive messages sent to work room"
    );
}

/// Plan 23 (Wave 2C): a second connection at the same (peer, room) must now
/// be ACCEPTED (multi-device Owner-key scenario). No `room_already_open` is sent.
/// A message from a third party reaches BOTH conns (broadcast).
#[tokio::test]
async fn duplicate_room_connection_accepted_and_both_receive_broadcast() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    // Two conns at the same (peer, room) — both must complete the handshake.
    let (mut ws_pi_1, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;
    let (mut ws_pi_2, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;

    // A third party (the "app") sends a message to (peer_pi, "work").
    let (mut ws_app, _) = connect_and_auth(port).await;
    let ct = "YnJvYWRjYXN0"; // "broadcast" b64
    ws_app
        .send(Message::text(
            json!({"peer": peer_pi, "room": "work", "ct": ct}).to_string(),
        ))
        .await
        .unwrap();

    // Both Pi conns must receive the forwarded envelope.
    let r1 = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_pi_1.next())
        .await
        .expect("ws_pi_1 timed out")
        .unwrap()
        .unwrap();
    let r2 = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_pi_2.next())
        .await
        .expect("ws_pi_2 timed out")
        .unwrap()
        .unwrap();

    let v1: serde_json::Value = serde_json::from_str(r1.to_text().unwrap()).unwrap();
    let v2: serde_json::Value = serde_json::from_str(r2.to_text().unwrap()).unwrap();
    assert_eq!(v1["ct"], ct, "first conn must receive broadcast");
    assert_eq!(v2["ct"], ct, "second conn must receive broadcast");
    // Neither conn should have received `room_already_open`.
    assert!(v1["code"].is_null());
    assert!(v2["code"].is_null());
}

/// Pi connects with room_meta.model → room_announced received by subscriber includes model.
#[tokio::test]
async fn room_announced_includes_model_from_hello() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::Signer;

    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi connects with room_meta.model
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws_pi, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let vk = sk_pi.verifying_key();
    ws_pi
        .send(Message::text(
            json!({
                "type": "hello",
                "pubkey": B64.encode(vk.to_bytes()),
                "room_id": "work",
                "room_meta": {"name": "my-proj", "model": "claude-opus-4-7"},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let challenge_msg = ws_pi.next().await.unwrap().unwrap();
    let cj: serde_json::Value = serde_json::from_str(challenge_msg.to_text().unwrap()).unwrap();
    let nonce_arr: [u8; 32] = B64
        .decode(cj["nonce"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let sig = sk_pi.sign(&nonce_arr);
    ws_pi
        .send(Message::text(
            json!({"type": "auth", "sig": B64.encode(sig.to_bytes())}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_announced")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_announced");
    assert_eq!(
        v["model"], "claude-opus-4-7",
        "model must be present in room_announced"
    );
    assert_eq!(v["name"], "my-proj");
}

/// Pi sends room_meta_update → subscribers receive room_meta_updated with new model.
#[tokio::test]
async fn room_meta_update_broadcasts_to_subscribers() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await; // room = "main"
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi sends room_meta_update for its own "main" room.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"model": "claude-haiku-4-5-20251001"},
            })
            .to_string(),
        ))
        .await
        .unwrap();

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_meta_updated")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_meta_updated", "got: {v}");
    assert_eq!(v["peer"], peer_pi);
    assert_eq!(v["room_id"], "main");
    assert_eq!(v["meta"]["model"], "claude-haiku-4-5-20251001");
}

/// `rooms_check` dedup: an identical follow-up snapshot for the same target
/// peer is suppressed by the relay (firehose-fix). First reply always sent.
#[tokio::test]
async fn rooms_check_dedup_suppresses_identical_responses() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (_ws_pi, _) = connect_and_auth_with_room(port, &sk_pi, "work").await;
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    let first = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on first rooms reply")
        .unwrap()
        .unwrap();
    let v1: serde_json::Value = serde_json::from_str(first.to_text().unwrap()).unwrap();
    assert_eq!(v1["type"], "rooms");
    assert_eq!(v1["peer"], peer_pi);

    // Identical follow-up — suppressed.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    let dup = tokio::time::timeout(tokio::time::Duration::from_millis(250), ws_app.next()).await;
    assert!(
        dup.is_err(),
        "identical rooms reply must be suppressed, got: {:?}",
        dup.ok()
            .and_then(|m| m.and_then(|r| r.ok()))
            .map(|m| m.into_text())
    );
}

/// After a real room change (room_meta_update with a new model), the next
/// `rooms_check` reply is distinct from the cached one and therefore is
/// emitted, not suppressed.
#[tokio::test]
async fn rooms_check_after_real_change_emits_new_snapshot() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await; // room "main"
    let (mut ws_app, _) = connect_and_auth(port).await;

    // First rooms_check — primes the cache.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    let _ = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();

    // Real change in Pi's room meta.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"model": "claude-sonnet-4-6"},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;

    // Second rooms_check — distinct payload (model changed) → must come through.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    // The subscriber may have received an unsolicited room_meta_updated
    // earlier; loop until we see the rooms snapshot. Cap at a handful of
    // frames to avoid runaway.
    let mut got = None;
    for _ in 0..4 {
        let m = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
            .await
            .expect("timed out waiting for distinct rooms reply")
            .unwrap()
            .unwrap();
        let v: serde_json::Value = serde_json::from_str(m.to_text().unwrap()).unwrap();
        if v["type"] == "rooms" {
            got = Some(v);
            break;
        }
    }
    let v = got.expect("never received the post-change rooms reply");
    let rooms_arr = v["rooms"].as_array().unwrap();
    assert_eq!(rooms_arr.len(), 1);
    assert_eq!(rooms_arr[0]["model"], "claude-sonnet-4-6");
}

/// Plan 28 (Wave D.6): `room_meta_update` with `meta.thinking` propagates
/// to subscribers in the subsequent `room_meta_updated` broadcast.
#[tokio::test]
async fn room_meta_update_propagates_thinking() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await; // room "main"
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi flips thinking to "high" via room_meta_update.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"thinking": "high"},
            })
            .to_string(),
        ))
        .await
        .unwrap();

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_meta_updated")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_meta_updated", "got: {v}");
    assert_eq!(v["peer"], peer_pi);
    assert_eq!(v["room_id"], "main");
    assert_eq!(
        v["meta"]["thinking"], "high",
        "thinking must round-trip: {v}"
    );
}

/// Plan 28 (Wave D.6): a `room_meta_update` carrying only `model` must NOT
/// drop a previously-set `thinking`. Patch semantics: absent fields are
/// preserved.
#[tokio::test]
async fn room_meta_update_with_only_model_preserves_thinking() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await;
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Step 1 — set thinking only.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"thinking": "high"},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let first = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on first room_meta_updated")
        .unwrap()
        .unwrap();
    let v1: serde_json::Value = serde_json::from_str(first.to_text().unwrap()).unwrap();
    assert_eq!(v1["meta"]["thinking"], "high");
    assert!(v1["meta"]["model"].is_null(), "model must be absent: {v1}");

    // Step 2 — set model only. `thinking` must survive.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"model": "claude-opus-4-7"},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let second = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on second room_meta_updated")
        .unwrap()
        .unwrap();
    let v2: serde_json::Value = serde_json::from_str(second.to_text().unwrap()).unwrap();
    assert_eq!(v2["meta"]["model"], "claude-opus-4-7");
    assert_eq!(
        v2["meta"]["thinking"], "high",
        "thinking must be preserved when patch only carries model: {v2}"
    );
}

/// Plan 28 (Wave D.6): `room_meta.thinking` from the hello frame is included
/// in `room_announced` (flat, top-level, matching the existing `model` shape)
/// and in `rooms_check` snapshots.
#[tokio::test]
async fn room_announced_and_rooms_check_include_thinking_from_hello() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::Signer;
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    // App subscribes first so it catches room_announced.
    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi connects with room_meta.thinking populated (and a model, to confirm
    // both serialize side-by-side in room_announced).
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws_pi, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let vk = sk_pi.verifying_key();
    ws_pi
        .send(Message::text(
            json!({
                "type": "hello",
                "pubkey": B64.encode(vk.to_bytes()),
                "room_id": "main",
                "room_meta": {
                    "name": "deep-think",
                    "model": "claude-sonnet-4-6",
                    "thinking": "medium",
                },
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let challenge_msg = ws_pi.next().await.unwrap().unwrap();
    let cj: serde_json::Value = serde_json::from_str(challenge_msg.to_text().unwrap()).unwrap();
    let nonce_arr: [u8; 32] = B64
        .decode(cj["nonce"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let sig = sk_pi.sign(&nonce_arr);
    ws_pi
        .send(Message::text(
            json!({"type": "auth", "sig": B64.encode(sig.to_bytes())}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_announced")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_announced", "got: {v}");
    assert_eq!(
        v["thinking"], "medium",
        "thinking flat on room_announced: {v}"
    );
    assert_eq!(v["model"], "claude-sonnet-4-6");
    assert_eq!(v["name"], "deep-think");

    // rooms_check should also carry the thinking on the per-room object.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    let snap = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on rooms snapshot")
        .unwrap()
        .unwrap();
    let s: serde_json::Value = serde_json::from_str(snap.to_text().unwrap()).unwrap();
    assert_eq!(s["type"], "rooms");
    let rooms = s["rooms"].as_array().unwrap();
    assert_eq!(rooms.len(), 1);
    assert_eq!(
        rooms[0]["thinking"], "medium",
        "thinking flat on rooms snapshot: {s}"
    );
    assert_eq!(rooms[0]["model"], "claude-sonnet-4-6");
}

/// Plan 32 (Part B Wave 1): `room_meta_update` with `meta.working` propagates
/// to subscribers, toggling both `true` and `false` through the broadcast.
#[tokio::test]
async fn room_meta_update_propagates_working() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await; // room "main"
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi flips working on.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"working": true},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let m1 = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for working=true")
        .unwrap()
        .unwrap();
    let v1: serde_json::Value = serde_json::from_str(m1.to_text().unwrap()).unwrap();
    assert_eq!(v1["type"], "room_meta_updated", "got: {v1}");
    assert_eq!(v1["peer"], peer_pi);
    assert_eq!(v1["room_id"], "main");
    assert_eq!(
        v1["meta"]["working"], true,
        "working=true must round-trip: {v1}"
    );

    // Pi flips working back off.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"working": false},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let m2 = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for working=false")
        .unwrap()
        .unwrap();
    let v2: serde_json::Value = serde_json::from_str(m2.to_text().unwrap()).unwrap();
    assert_eq!(
        v2["meta"]["working"], false,
        "working=false must round-trip: {v2}"
    );
}

/// Plan 32 (Part B Wave 1): a `room_meta_update` carrying only `model` must
/// NOT clear a previously-set `working: true`. Merge-patch semantics: absent
/// fields are preserved (working never auto-zeroes).
#[tokio::test]
async fn room_meta_update_with_only_model_preserves_working() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await;
    let (mut ws_app, _) = connect_and_auth(port).await;

    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Step 1 — set working only.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"working": true},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let first = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on first room_meta_updated")
        .unwrap()
        .unwrap();
    let v1: serde_json::Value = serde_json::from_str(first.to_text().unwrap()).unwrap();
    assert_eq!(v1["meta"]["working"], true);

    // Step 2 — set model only. `working` must survive the model-only patch.
    ws_pi
        .send(Message::text(
            json!({
                "type": "room_meta_update",
                "room_id": "main",
                "meta": {"model": "claude-opus-4-7"},
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let second = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on second room_meta_updated")
        .unwrap()
        .unwrap();
    let v2: serde_json::Value = serde_json::from_str(second.to_text().unwrap()).unwrap();
    assert_eq!(v2["meta"]["model"], "claude-opus-4-7");
    assert_eq!(
        v2["meta"]["working"], true,
        "working must be preserved when patch only carries model: {v2}"
    );
}

/// Plan 32 (Part B Wave 1): `room_meta.working` from the hello frame is
/// included in `room_announced` (flat, top-level, matching the `model`/
/// `thinking` shape) and in `rooms_check` snapshots.
#[tokio::test]
async fn room_announced_and_rooms_check_include_working_from_hello() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::Signer;
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    // App subscribes first so it catches room_announced.
    let (mut ws_app, _) = connect_and_auth(port).await;
    ws_app
        .send(Message::text(
            json!({"type": "subscribe_rooms", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Pi connects already working.
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws_pi, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let vk = sk_pi.verifying_key();
    ws_pi
        .send(Message::text(
            json!({
                "type": "hello",
                "pubkey": B64.encode(vk.to_bytes()),
                "room_id": "main",
                "room_meta": {
                    "name": "busy-room",
                    "working": true,
                },
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let challenge_msg = ws_pi.next().await.unwrap().unwrap();
    let cj: serde_json::Value = serde_json::from_str(challenge_msg.to_text().unwrap()).unwrap();
    let nonce_arr: [u8; 32] = B64
        .decode(cj["nonce"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let sig = sk_pi.sign(&nonce_arr);
    ws_pi
        .send(Message::text(
            json!({"type": "auth", "sig": B64.encode(sig.to_bytes())}).to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for room_announced")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "room_announced", "got: {v}");
    assert_eq!(v["working"], true, "working flat on room_announced: {v}");
    assert_eq!(v["name"], "busy-room");

    // rooms_check should also carry working on the per-room object.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();
    let snap = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out on rooms snapshot")
        .unwrap()
        .unwrap();
    let s: serde_json::Value = serde_json::from_str(snap.to_text().unwrap()).unwrap();
    assert_eq!(s["type"], "rooms");
    let rooms = s["rooms"].as_array().unwrap();
    assert_eq!(rooms.len(), 1);
    assert_eq!(
        rooms[0]["working"], true,
        "working flat on rooms snapshot: {s}"
    );
}

/// rooms_check after room_meta_update reflects the updated model.
#[tokio::test]
async fn rooms_check_reflects_updated_model() {
    let port = start_relay().await;
    let sk_pi = random_key();
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    let peer_pi = B64.encode(sk_pi.verifying_key().to_bytes());

    let (mut ws_pi, _) = connect_and_auth_with_key(port, &sk_pi).await;
    let (mut ws_app, _) = connect_and_auth(port).await;

    // Update model first.
    ws_pi
        .send(Message::text(
            json!({"type": "room_meta_update", "room_id": "main", "meta": {"model": "claude-sonnet-4-6"}})
                .to_string(),
        ))
        .await
        .unwrap();
    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

    // Request snapshot.
    ws_app
        .send(Message::text(
            json!({"type": "rooms_check", "peers": [&peer_pi]}).to_string(),
        ))
        .await
        .unwrap();

    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_app.next())
        .await
        .expect("timed out waiting for rooms response")
        .unwrap()
        .unwrap();

    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "rooms");
    let rooms = v["rooms"].as_array().unwrap();
    assert_eq!(rooms.len(), 1);
    assert_eq!(
        rooms[0]["model"], "claude-sonnet-4-6",
        "rooms_check must show updated model"
    );
}
