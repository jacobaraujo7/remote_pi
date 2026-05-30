use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use tokio::sync::Mutex;

/// Metadata about one active Pi room (sub-channel of a peer_id).
#[derive(Debug, Clone, serde::Serialize)]
pub struct RoomMeta {
    pub room_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    /// Active Claude model for this room (plano 18). None = not reported yet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// Active thinking level for this room (plano 28). Opaque string from the
    /// Pi's perspective (e.g. `"high"`, `"medium"`, `"none"`) — the relay
    /// never interprets it. None = not reported yet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<String>,
    /// Whether this room currently has an in-flight agent turn (plano 32).
    /// A plain bool with the same merge-patch semantics as `thinking`: a
    /// `room_meta_update` that omits `working` leaves it unchanged — it never
    /// auto-clears. Defaults to `false` until the Pi reports otherwise, and is
    /// always serialized so subscribers can rely on its presence.
    pub working: bool,
    pub started_at: i64,
}

/// Patch over the mutable `RoomMeta` fields. Each entry distinguishes
/// "field absent in the update" (outer `None`, meaning "leave current") from
/// "field present in the update" (outer `Some(_)`, whose inner `None` means
/// "clear to null" and whose inner `Some(s)` means "set to s").
///
/// Built by the `room_meta_update` handler from the `meta` JSON object; the
/// relay never inspects the inner values beyond JSON-shape (they're forwarded
/// opaquely to subscribers).
#[derive(Debug, Default, Clone)]
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    /// `working` is a non-nullable bool, so the patch is a single `Option`:
    /// `None` = field absent (leave current), `Some(b)` = set to `b`. There is
    /// no "clear to null" — `false` *is* the cleared state.
    pub working: Option<bool>,
}

impl RoomMetaPatch {
    /// `true` when at least one field is present (i.e. the patch is a no-op
    /// otherwise). Used by the registry to skip work when callers send empty
    /// `meta: {}`.
    pub fn is_empty(&self) -> bool {
        self.model.is_none() && self.thinking.is_none() && self.working.is_none()
    }
}

#[derive(Debug, Default)]
struct Inner {
    /// subscribers_of[X] = set of peer_ids that want push when X opens/closes a room.
    subscribers_of: HashMap<String, HashSet<String>>,
    /// subscriptions_by[Y] = set of peer_ids that Y is watching (for efficient cleanup).
    subscriptions_by: HashMap<String, HashSet<String>>,
}

/// Tracks who has subscribed to room announcements for which peer_ids.
/// Complements PresenceManager: same subscription graph, separate broadcast semantics.
#[derive(Clone, Debug, Default)]
pub struct RoomManager {
    inner: Arc<Mutex<Inner>>,
}

impl RoomManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Replaces `subscriber`'s full subscription list with `peers`.
    /// Empty list = unsubscribe all.
    pub async fn subscribe(&self, subscriber: String, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        if let Some(old) = g.subscriptions_by.remove(&subscriber) {
            for peer in &old {
                if let Some(set) = g.subscribers_of.get_mut(peer) {
                    set.remove(&subscriber);
                }
            }
        }
        let new_set: HashSet<String> = peers.into_iter().collect();
        for peer in &new_set {
            g.subscribers_of
                .entry(peer.clone())
                .or_default()
                .insert(subscriber.clone());
        }
        if !new_set.is_empty() {
            g.subscriptions_by.insert(subscriber, new_set);
        }
    }

    /// Removes `peers` from `subscriber`'s watched list.
    pub async fn unsubscribe(&self, subscriber: &str, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        for peer in &peers {
            if let Some(set) = g.subscribers_of.get_mut(peer) {
                set.remove(subscriber);
            }
            if let Some(subs) = g.subscriptions_by.get_mut(subscriber) {
                subs.remove(peer);
            }
        }
    }

    /// Removes all subscriptions for `subscriber` (called on disconnect to prevent leaks).
    pub async fn unsubscribe_all(&self, subscriber: &str) {
        let mut g = self.inner.lock().await;
        if let Some(peers) = g.subscriptions_by.remove(subscriber) {
            for peer in &peers {
                if let Some(set) = g.subscribers_of.get_mut(peer) {
                    set.remove(subscriber);
                }
            }
        }
    }

    /// Returns everyone who subscribed to room events for `peer`.
    pub async fn subscribers_of(&self, peer: &str) -> Vec<String> {
        let g = self.inner.lock().await;
        g.subscribers_of
            .get(peer)
            .map(|s| s.iter().cloned().collect())
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn subscribe_replaces_list() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        assert!(rm.subscribers_of("A").await.contains(&"B".to_string()));

        rm.subscribe("B".into(), vec!["A".into()]).await;
        assert!(!rm.subscribers_of("C").await.contains(&"B".to_string()));
    }

    #[tokio::test]
    async fn subscribe_empty_equals_unsubscribe_all() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into()]).await;
        rm.subscribe("B".into(), vec![]).await;
        assert!(rm.subscribers_of("A").await.is_empty());
    }

    #[tokio::test]
    async fn unsubscribe_all_cleans_subscriber_from_sets() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        rm.unsubscribe_all("B").await;
        assert!(rm.subscribers_of("A").await.is_empty());
        assert!(rm.subscribers_of("C").await.is_empty());
    }
}
