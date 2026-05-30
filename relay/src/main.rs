use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use tokio::net::TcpListener;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let addr = relay::config::relay_socket_addr_from_env()?;

    // Default puts the SQLite file (and any transient -journal) under data/,
    // so bare-metal `cargo run` doesn't litter the project root.
    let db_path = std::env::var("REMOTEPI_MESH_DB_PATH")
        .unwrap_or_else(|_| "data/mesh.db".to_string());

    let mesh = Arc::new(
        relay::MeshStore::open(&db_path)
            .with_context(|| format!("failed to open mesh DB at {db_path}"))?,
    );
    info!("mesh storage opened at {db_path}");

    let presence = Arc::new(relay::PresenceManager::new());
    let rooms = Arc::new(relay::RoomManager::new());
    let metrics = Arc::new(relay::FirehoseMetrics::new());
    let registry = Arc::new(relay::PeerRegistry::new(
        presence.clone(),
        rooms.clone(),
        metrics.clone(),
    ));
    let mesh_auth = Arc::new(relay::MeshAuthCache::new());

    // Background reporter: drain firehose counters every 10 s and emit a
    // single structured log line. Quiet windows are silent.
    let metrics_for_reporter = metrics.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
        interval.tick().await; // first tick is immediate; skip it
        loop {
            interval.tick().await;
            metrics_for_reporter.report_and_reset();
        }
    });

    let state = relay::AppState {
        registry,
        presence,
        rooms,
        mesh,
        mesh_auth,
        metrics,
    };
    let app = relay::build_router(state);

    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;

    info!("relay listening on {addr} (WebSocket + /health + /mesh)");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install ctrl_c handler");
        info!("ctrl_c received, shutting down");
    })
    .await
    .context("axum::serve failed")?;

    Ok(())
}
