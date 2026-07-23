pub mod auth;
pub mod handlers;
mod identity;
pub mod mesh;
pub mod metrics;
pub mod peers;
pub mod presence;
pub mod protocol;
pub mod rooms;

use std::sync::Arc;

use axum::{
    Router,
    extract::{DefaultBodyLimit, FromRef},
    routing::get,
};

pub use handlers::pi_forward::MeshAuthCache;
pub use mesh::MeshStore;
pub use metrics::FirehoseMetrics;
pub use peers::registry::PeerRegistry;
pub use presence::PresenceManager;
pub use rooms::{RoomManager, RoomMeta, RoomMetaPatch};

/// Shared state injected into every axum handler.
///
/// The relay serves WebSocket upgrades (`GET /`), health checks (`GET /health`),
/// and mesh membership endpoints (`GET/POST /mesh/:hash`) on a single port —
/// they all read from this struct.
#[derive(Clone)]
pub struct AppState {
    pub registry: Arc<PeerRegistry>,
    pub presence: Arc<PresenceManager>,
    pub rooms: Arc<RoomManager>,
    pub mesh: Arc<MeshStore>,
    /// Plan 25 — caches `Pi-pubkey → mesh siblings` to avoid hitting SQLite
    /// for every `pi_envelope` forward (60 s TTL).
    pub mesh_auth: Arc<MeshAuthCache>,
    /// In-process counters for emit/suppress accounting (firehose dedup).
    /// A background task drains and logs them every 10 s.
    pub metrics: Arc<FirehoseMetrics>,
}

// Allows mesh handlers to keep using `State<Arc<MeshStore>>` instead of
// reaching into the full `AppState`.
impl FromRef<AppState> for Arc<MeshStore> {
    fn from_ref(state: &AppState) -> Self {
        state.mesh.clone()
    }
}

/// Builds the unified axum router: WebSocket upgrade + HTTP API.
///
/// Mount it with `axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())`
/// — the WS handler extracts `ConnectInfo<SocketAddr>` for log spans.
pub fn build_router(state: AppState) -> Router {
    Router::new()
        .route("/", get(handlers::peer::ws_handler))
        .route("/health", get(|| async { "OK" }))
        .route(
            "/mesh/:owner_pk_hash",
            get(mesh::handler::get_mesh).post(mesh::handler::post_mesh),
        )
        .layer(DefaultBodyLimit::max(mesh::handler::MAX_BODY_BYTES))
        .with_state(state)
}
