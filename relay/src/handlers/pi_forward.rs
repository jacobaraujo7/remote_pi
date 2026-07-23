//! Plan 25 Wave A — Pi-to-Pi envelope forwarding via the relay.
//!
//! Pi-A sends a control frame:
//!
//! ```jsonc
//! { "type": "pi_envelope", "to_pc": "<Pi-B-pubkey-b64>", "envelope": { ... } }
//! ```
//!
//! The relay authenticates Pi-A via the existing challenge-response (so we
//! already trust `sender_peer_id` here), looks up the `mesh_versions` blob
//! that lists Pi-A and confirms Pi-B is in the same Owner's member list, then
//! forwards to Pi-B (any live conn) as:
//!
//! ```jsonc
//! { "type": "pi_envelope_in", "from_pc": "<Pi-A-pubkey>", "envelope": <verbatim> }
//! ```
//!
//! Failures don't use a custom error frame — the relay synthesizes an envelope
//! with `body.type = "transport_error"` (per the plan's ACK protocol section),
//! correlated to the sender's original envelope via `re: <original_id>`.

use std::collections::{HashMap, HashSet};
#[cfg(test)]
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use axum::extract::ws::Message;
use rand::thread_rng;
use tokio::sync::Mutex as AsyncMutex;
use tracing::warn;

use crate::identity::canonical_ed25519_public_key;
use crate::mesh::{MeshStore, types::MeshHeader};
use crate::peers::registry::PeerRegistry;

/// Time-to-live for a positive membership lookup. The plan calls for 60 s.
const MAX_CACHE_TTL: Duration = Duration::from_secs(60);
const NEGATIVE_CACHE_TTL: Duration = Duration::from_secs(1);
const MAX_CACHE_ENTRIES: usize = 1024;

/// In-memory cache that maps `Pi-pubkey → authorization result`. Positive
/// entries retain one shared union of direct mesh siblings; negative entries
/// briefly coalesce repeated misses for senders absent from every Owner blob.
#[derive(Debug)]
pub struct MeshAuthCache {
    inner: Mutex<HashMap<String, CachedAuthorization>>,
    /// Global async gate: callers wait here instead of consuming a blocking
    /// worker while another cold-cache SQLite snapshot is in flight.
    refresh_snapshot_lock: AsyncMutex<()>,
    ttl: Duration,
    #[cfg(test)]
    refresh_jobs: AtomicUsize,
}

#[derive(Clone, Debug)]
enum AuthorizationResult {
    Positive(Arc<HashSet<String>>),
    Negative,
}

#[derive(Clone, Debug)]
struct CachedAuthorization {
    result: AuthorizationResult,
    cached_at: Instant,
}

impl MeshAuthCache {
    pub fn new() -> Self {
        Self::with_ttl(MAX_CACHE_TTL)
    }

    pub fn with_ttl(ttl: Duration) -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
            refresh_snapshot_lock: AsyncMutex::new(()),
            ttl: ttl.min(MAX_CACHE_TTL),
            #[cfg(test)]
            refresh_jobs: AtomicUsize::new(0),
        }
    }

    fn cache_guard(&self) -> MutexGuard<'_, HashMap<String, CachedAuthorization>> {
        match self.inner.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                warn!("mesh authorization cache mutex poisoned; clearing cache");
                let mut guard = poisoned.into_inner();
                guard.clear();
                self.inner.clear_poison();
                guard
            }
        }
    }

    fn prune_expired(entries: &mut HashMap<String, CachedAuthorization>, ttl: Duration) {
        entries.retain(|_, entry| {
            let entry_ttl = match entry.result {
                AuthorizationResult::Positive(_) => ttl,
                AuthorizationResult::Negative => NEGATIVE_CACHE_TTL,
            };
            entry.cached_at.elapsed() < entry_ttl
        });
    }

    fn cached_result(&self, pi_pk: &str) -> Option<AuthorizationResult> {
        let mut entries = self.cache_guard();
        Self::prune_expired(&mut entries, self.ttl);
        entries.get(pi_pk).map(|entry| entry.result.clone())
    }

    fn insert_result(&self, pi_pk: String, result: AuthorizationResult) {
        let mut entries = self.cache_guard();
        Self::prune_expired(&mut entries, self.ttl);
        if !entries.contains_key(&pi_pk) && entries.len() >= MAX_CACHE_ENTRIES {
            let oldest_key = entries
                .iter()
                .min_by(|(left_key, left), (right_key, right)| {
                    left.cached_at
                        .cmp(&right.cached_at)
                        .then_with(|| left_key.cmp(right_key))
                })
                .map(|(key, _)| key.clone());
            if let Some(oldest_key) = oldest_key {
                entries.remove(&oldest_key);
            }
        }
        entries.insert(
            pi_pk,
            CachedAuthorization {
                result,
                cached_at: Instant::now(),
            },
        );
    }

    fn cached_authorization(result: AuthorizationResult, target: &str) -> bool {
        match result {
            AuthorizationResult::Positive(members) => members.contains(target),
            AuthorizationResult::Negative => false,
        }
    }

    fn refresh_authorization(&self, pi_pk: &str, target: &str, store: &MeshStore) -> bool {
        let blobs = match store.all_blobs() {
            Ok(blobs) => blobs,
            Err(error) => {
                warn!(error = %error, "mesh store read failed during authorization refresh");
                return false;
            }
        };
        match direct_members_from_blobs(pi_pk, &blobs) {
            Some(members) => {
                let members = Arc::new(members);
                let authorized = members.contains(target);
                self.insert_result(pi_pk.to_owned(), AuthorizationResult::Positive(members));
                authorized
            }
            None => {
                self.insert_result(pi_pk.to_owned(), AuthorizationResult::Negative);
                false
            }
        }
    }

    /// `true` iff both Pis belong to the same direct Owner membership.
    pub async fn is_authorized(
        self: &Arc<Self>,
        pi_a: &str,
        pi_b: &str,
        store: Arc<MeshStore>,
    ) -> bool {
        let (Ok(a), Ok(b)) = (
            canonical_ed25519_public_key(pi_a),
            canonical_ed25519_public_key(pi_b),
        ) else {
            return false;
        };
        self.is_authorized_canonical(&a, &b, store).await
    }

    async fn is_authorized_canonical(
        self: &Arc<Self>,
        pi_a: &str,
        pi_b: &str,
        store: Arc<MeshStore>,
    ) -> bool {
        if let Some(result) = self.cached_result(pi_a) {
            return Self::cached_authorization(result, pi_b);
        }

        // Serialize cold refreshes before creating a blocking task. A caller
        // that queued behind the gate sees the entry created by its predecessor
        // and returns without occupying Tokio's blocking pool.
        let _refresh_guard = self.refresh_snapshot_lock.lock().await;
        if let Some(result) = self.cached_result(pi_a) {
            return Self::cached_authorization(result, pi_b);
        }

        let cache = Arc::clone(self);
        let sender = pi_a.to_owned();
        let target = pi_b.to_owned();
        #[cfg(test)]
        self.refresh_jobs
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        match tokio::task::spawn_blocking(move || {
            cache.refresh_authorization(&sender, &target, store.as_ref())
        })
        .await
        {
            Ok(authorized) => authorized,
            Err(error) => {
                warn!(error = %error, "mesh authorization refresh task failed");
                false
            }
        }
    }
}

impl Default for MeshAuthCache {
    fn default() -> Self {
        Self::new()
    }
}

fn direct_members_from_blobs(pi_pk: &str, blobs: &[Vec<u8>]) -> Option<HashSet<String>> {
    let mut union = HashSet::new();
    for blob in blobs {
        let header: MeshHeader = match serde_json::from_slice(blob) {
            Ok(header) => header,
            Err(_) => continue,
        };
        let owner_members: Result<HashSet<String>, _> = header
            .members
            .iter()
            .map(|member| canonical_ed25519_public_key(&member.remote_epk))
            .collect();
        let Ok(owner_members) = owner_members else {
            continue;
        };
        if owner_members.contains(pi_pk) {
            union.extend(owner_members);
        }
    }
    (!union.is_empty()).then_some(union)
}

/// What the routing loop should do after calling `handle_pi_envelope`.
pub enum PiForwardResult {
    /// Envelope delivered (or accepted by the channel of) Pi-B.
    Forwarded,
    /// Send this message back to the original sender via their own WS sink.
    /// Always a `pi_envelope_in` whose envelope carries
    /// `body.type = "transport_error"`.
    TransportError(Message),
}

#[derive(Clone, Copy)]
enum TransportErrorReason {
    Offline,
    NotAuthorized,
    BadEnvelope,
}

impl TransportErrorReason {
    fn as_str(self) -> &'static str {
        match self {
            Self::Offline => "offline",
            Self::NotAuthorized => "not_authorized",
            Self::BadEnvelope => "bad_envelope",
        }
    }
}

/// Handles one `pi_envelope` frame. `sender_peer_id` is the authenticated
/// Pi-A pubkey (already verified by the WS handshake).
pub async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: &serde_json::Value,
    registry: &PeerRegistry,
    mesh: Arc<MeshStore>,
    cache: Arc<MeshAuthCache>,
) -> PiForwardResult {
    let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
    let envelope = frame.get("envelope");

    let (to_pc, envelope) = match (to_pc, envelope) {
        (Some(t), Some(e)) if e.is_object() && !t.is_empty() => (t, e),
        _ => {
            return PiForwardResult::TransportError(make_transport_error(
                frame.get("envelope"),
                TransportErrorReason::BadEnvelope,
            ));
        }
    };

    let sender = match canonical_ed25519_public_key(sender_peer_id) {
        Ok(value) => value,
        Err(_) => {
            return PiForwardResult::TransportError(make_transport_error(
                frame.get("envelope"),
                TransportErrorReason::BadEnvelope,
            ));
        }
    };
    let target = match canonical_ed25519_public_key(to_pc) {
        Ok(value) => value,
        Err(_) => {
            return PiForwardResult::TransportError(make_transport_error(
                Some(envelope),
                TransportErrorReason::BadEnvelope,
            ));
        }
    };

    if !cache.is_authorized_canonical(&sender, &target, mesh).await {
        return PiForwardResult::TransportError(make_transport_error(
            Some(envelope),
            TransportErrorReason::NotAuthorized,
        ));
    }

    let outbound = serde_json::json!({
        "type": "pi_envelope_in",
        "from_pc": sender,
        "envelope": envelope, // verbatim
    });
    let msg = Message::Text(outbound.to_string());

    if registry.forward_to_peer(&target, msg) {
        PiForwardResult::Forwarded
    } else {
        PiForwardResult::TransportError(make_transport_error(
            Some(envelope),
            TransportErrorReason::Offline,
        ))
    }
}

fn is_uuid(value: &str) -> bool {
    value.len() == 36
        && value.as_bytes().iter().enumerate().all(|(index, byte)| {
            if matches!(index, 8 | 13 | 18 | 23) {
                *byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

fn new_uuid_v4() -> String {
    use rand::RngCore;

    let mut bytes = [0_u8; 16];
    thread_rng().fill_bytes(&mut bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
        bytes[4],
        bytes[5],
        bytes[6],
        bytes[7],
        bytes[8],
        bytes[9],
        bytes[10],
        bytes[11],
        bytes[12],
        bytes[13],
        bytes[14],
        bytes[15],
    )
}

/// Builds a `pi_envelope_in` frame whose inner envelope carries
/// `body.type = "transport_error"`, correlated to the original via `re`.
fn make_transport_error(
    envelope: Option<&serde_json::Value>,
    reason: TransportErrorReason,
) -> Message {
    let re = envelope
        .and_then(|value| value.get("id"))
        .and_then(serde_json::Value::as_str)
        .filter(|value| is_uuid(value))
        .map(str::to_owned);
    let to_addr = envelope
        .and_then(|value| value.get("from"))
        .and_then(serde_json::Value::as_str)
        .filter(|address| !address.is_empty())
        .unwrap_or("_unknown");

    let err_envelope = serde_json::json!({
        "from": "_relay",
        "to": to_addr,
        "id": new_uuid_v4(),
        "re": re,
        "body": { "type": "transport_error", "reason": reason.as_str() },
    });

    let frame = serde_json::json!({
        "type": "pi_envelope_in",
        "from_pc": "_relay",
        "envelope": err_envelope,
    });
    Message::Text(frame.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{PresenceManager, RoomManager};
    use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
    use std::sync::Arc;

    fn fresh_cache_and_store() -> (Arc<MeshAuthCache>, Arc<MeshStore>) {
        (
            Arc::new(MeshAuthCache::new()),
            Arc::new(MeshStore::open_in_memory().unwrap()),
        )
    }

    fn pi_key(byte: u8) -> String {
        use base64::{Engine as _, engine::general_purpose::STANDARD};
        STANDARD.encode([byte; 32])
    }

    fn pi_key_url_safe(byte: u8) -> String {
        URL_SAFE_NO_PAD.encode([byte; 32])
    }

    fn owner_blob(owner_pk: &[u8], members: &[&str], version: u64) -> Vec<u8> {
        let pk_b64 = {
            use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
            B64.encode(owner_pk)
        };
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|member| {
                serde_json::json!({
                    "remote_epk": member,
                    "relay_url": "wss://relay.example.test",
                    "paired_at": "2025-01-01T00:00:00.000Z",
                })
            })
            .collect();
        serde_json::to_vec(&serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "issued_at": 1_700_000_000_000_u64,
            "members": members_json,
        }))
        .unwrap()
    }

    fn write_owner_blob(store: &MeshStore, owner_pk: &[u8], members: &[&str], version: u64) {
        use sha2::{Digest, Sha256};
        let blob_bytes = owner_blob(owner_pk, members, version);
        let hash = Sha256::digest(owner_pk)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        store
            .upsert(&hash, owner_pk, version, &blob_bytes, &[0u8; 64], 0)
            .unwrap();
    }

    #[test]
    fn multi_owner_union_ignores_sender_only_owner_inserted_first() {
        let pi_a = pi_key(0x0a);
        let pi_b = pi_key(0x0b);
        let blobs = vec![
            owner_blob(&[1; 32], &[&pi_a], 1),
            owner_blob(&[2; 32], &[&pi_a, &pi_b], 1),
        ];

        assert_eq!(
            direct_members_from_blobs(&pi_a, &blobs),
            Some(HashSet::from([pi_a, pi_b])),
        );
    }

    #[test]
    fn multi_owner_union_is_order_independent_and_direct() {
        let pi_a = pi_key(0x0a);
        let pi_b = pi_key(0x0b);
        let pi_c = pi_key(0x0c);
        let owner_ab = owner_blob(&[1; 32], &[&pi_a, &pi_b], 1);
        let owner_ac = owner_blob(&[2; 32], &[&pi_a, &pi_c], 1);
        for blobs in [
            &vec![owner_ab.clone(), owner_ac.clone()],
            &vec![owner_ac, owner_ab],
        ] {
            let members_a = direct_members_from_blobs(&pi_a, blobs).unwrap();
            let members_b = direct_members_from_blobs(&pi_b, blobs).unwrap();
            let members_c = direct_members_from_blobs(&pi_c, blobs).unwrap();
            assert!(members_a.contains(&pi_b) && members_a.contains(&pi_c));
            assert!(!members_b.contains(&pi_c) && !members_c.contains(&pi_b));
        }
    }

    #[tokio::test]
    async fn authorization_is_direct_not_transitive() {
        let (cache, store) = fresh_cache_and_store();
        let a = pi_key(0x0a);
        let b = pi_key(0x0b);
        let c = pi_key(0x0c);
        write_owner_blob(&store, &[1; 32], &[&a, &b], 1);
        write_owner_blob(&store, &[2; 32], &[&b, &c], 1);

        assert!(cache.is_authorized(&a, &b, store.clone()).await);
        assert!(cache.is_authorized(&b, &a, store.clone()).await);
        assert!(cache.is_authorized(&b, &c, store.clone()).await);
        assert!(cache.is_authorized(&c, &b, store.clone()).await);
        assert!(!cache.is_authorized(&a, &c, store.clone()).await);
        assert!(!cache.is_authorized(&c, &a, store).await);
    }

    #[tokio::test]
    async fn canonical_variants_share_positive_cache_state() {
        let (cache, store) = fresh_cache_and_store();
        let a = pi_key(0xfb);
        let b = pi_key(0xef);
        let a_url_safe = pi_key_url_safe(0xfb);
        let b_url_safe = pi_key_url_safe(0xef);
        let owner = [3_u8; 32];
        write_owner_blob(&store, &owner, &[&a_url_safe, &b_url_safe], 1);

        assert!(
            cache
                .is_authorized(&a_url_safe, &b_url_safe, store.clone())
                .await
        );
        write_owner_blob(&store, &owner, &[&a_url_safe], 2);
        assert!(cache.is_authorized(&a, &b, store).await);
    }

    #[tokio::test]
    async fn zero_ttl_observes_membership_revocation_on_next_lookup() {
        let cache = Arc::new(MeshAuthCache::with_ttl(Duration::ZERO));
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        let a = pi_key(0x0a);
        let b = pi_key(0x0b);
        let owner = [4_u8; 32];
        write_owner_blob(&store, &owner, &[&a, &b], 1);
        assert!(cache.is_authorized(&a, &b, store.clone()).await);

        write_owner_blob(&store, &owner, &[&a], 2);
        assert!(!cache.is_authorized(&a, &b, store).await);
    }

    #[tokio::test]
    async fn positive_cache_survives_immediate_revoke_before_expiry() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        let target = pi_key(0x0b);
        let owner = [5; 32];
        write_owner_blob(&store, &owner, &[&sender, &target], 1);
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        write_owner_blob(&store, &owner, &[&sender], 2);
        assert!(cache.is_authorized(&sender, &target, store).await);
    }

    #[tokio::test]
    async fn fresh_positive_entry_reuses_union_for_random_target_misses() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        let member = pi_key(0x0b);
        write_owner_blob(&store, &[5; 32], &[&sender, &member], 1);

        assert!(cache.is_authorized(&sender, &member, store.clone()).await);
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0c), store.clone())
                .await
        );
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0d), store.clone())
                .await
        );
        assert_eq!(store.all_blobs_calls(), 1);
    }

    #[tokio::test]
    async fn negative_entry_coalesces_repeated_unknown_sender_misses() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0b), store.clone())
                .await
        );
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0c), store.clone())
                .await
        );
        assert_eq!(store.all_blobs_calls(), 1);
    }

    #[tokio::test]
    async fn positive_expiry_refreshes_authorization() {
        let cache = Arc::new(MeshAuthCache::with_ttl(Duration::from_millis(5)));
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        let sender = pi_key(0x0a);
        let target = pi_key(0x0b);
        write_owner_blob(&store, &[6; 32], &[&sender, &target], 1);
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        assert_eq!(store.all_blobs_calls(), 2);
    }

    #[tokio::test]
    async fn negative_expiry_refreshes_authorization() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0b), store.clone())
                .await
        );
        {
            let mut entries = cache.cache_guard();
            entries.get_mut(&sender).unwrap().cached_at = Instant::now()
                .checked_sub(NEGATIVE_CACHE_TTL + Duration::from_millis(1))
                .unwrap();
        }
        assert!(
            !cache
                .is_authorized(&sender, &pi_key(0x0c), store.clone())
                .await
        );
        assert_eq!(store.all_blobs_calls(), 2);
    }

    #[test]
    fn cache_is_bounded_and_evicts_oldest_sender() {
        let cache = MeshAuthCache::new();
        cache.insert_result("sender-0000".to_owned(), AuthorizationResult::Negative);
        std::thread::sleep(Duration::from_millis(1));
        for index in 1..=MAX_CACHE_ENTRIES {
            cache.insert_result(format!("sender-{index:04}"), AuthorizationResult::Negative);
        }
        let entries = cache.cache_guard();
        assert_eq!(entries.len(), MAX_CACHE_ENTRIES);
        assert!(!entries.contains_key("sender-0000"));
        assert!(entries.contains_key("sender-1024"));
    }

    #[tokio::test]
    async fn concurrent_cold_requests_coalesce_to_one_store_scan() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        let target = pi_key(0x0b);
        write_owner_blob(&store, &[8; 32], &[&sender, &target], 1);
        let (a, b, c, d) = tokio::join!(
            cache.is_authorized(&sender, &target, store.clone()),
            cache.is_authorized(&sender, &target, store.clone()),
            cache.is_authorized(&sender, &target, store.clone()),
            cache.is_authorized(&sender, &target, store.clone()),
        );
        assert!(a && b && c && d);
        assert_eq!(store.all_blobs_calls(), 1);
        assert_eq!(cache.refresh_jobs.load(Ordering::Relaxed), 1);
    }

    #[tokio::test]
    async fn poisoned_cache_clears_and_recovers_without_panicking() {
        let (cache, store) = fresh_cache_and_store();
        let sender = pi_key(0x0a);
        let target = pi_key(0x0b);
        write_owner_blob(&store, &[9; 32], &[&sender, &target], 1);
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        let poisoned_cache = cache.clone();
        assert!(
            std::thread::spawn(move || {
                let _guard = poisoned_cache.inner.lock().unwrap();
                panic!("poison cache");
            })
            .join()
            .is_err()
        );
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        assert!(!cache.inner.is_poisoned());
        // The repaired cache reuses the refreshed entry instead of scanning
        // SQLite again after the recovered lock is released.
        assert!(cache.is_authorized(&sender, &target, store.clone()).await);
        assert_eq!(store.all_blobs_calls(), 2);
        assert_eq!(cache.refresh_jobs.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn configured_positive_ttl_is_capped_at_sixty_seconds() {
        let cache = MeshAuthCache::with_ttl(Duration::from_secs(600));
        assert_eq!(cache.ttl, MAX_CACHE_TTL);
    }

    #[tokio::test]
    async fn bad_envelope_when_missing_to_pc() {
        let registry = Arc::new(PeerRegistry::new(
            Arc::new(PresenceManager::new()),
            Arc::new(RoomManager::new()),
            Arc::new(crate::metrics::FirehoseMetrics::new()),
        ));
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        let cache = Arc::new(MeshAuthCache::new());
        let frame = serde_json::json!({
            "type": "pi_envelope",
            "envelope": {
                "from": "x",
                "to": "y",
                "id": "30000000-0000-4000-8000-000000000003",
                "re": null,
                "body": {},
            },
        });
        match handle_pi_envelope(&pi_key(0x0a), &frame, &registry, store, cache).await {
            PiForwardResult::TransportError(_) => {}
            PiForwardResult::Forwarded => panic!("must be transport_error"),
        }
    }
}
