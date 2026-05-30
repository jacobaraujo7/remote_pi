# Remote Pi — Relay

A lightweight WebSocket relay server that connects the **Remote Pi** mobile app to
`pi-extension` processes running on your Operational System. It handles peer routing and presence
tracking without ever reading message content.

For a full overview of the project, see the
[root README](../README.md).

---

## Protocol & Security

For wire format, identity model, ACK protocol, cross-PC routing, mesh
membership, trust model, and failure modes, see
[PROTOCOL.md](../PROTOCOL.md) at the repo root. It is the canonical reference
for everything the relay enforces on the wire.

---

## How it works

Every device authenticates with an Ed25519 keypair during the WebSocket handshake
(challenge-response). After that, the relay routes opaque messages between peers
identified by their public key. It never decrypts or inspects payload content.

---

## Public relay

A shared relay is available at:

```
https://relay-rp1.jacobmoura.work
```

You can use it to get started without any setup. However, be aware of the security
trade-offs below.

### Security considerations

Messages are protected in two ways on the public relay:

- **TLS (SSL)** — the WebSocket connection is encrypted in transit.
- **Ed25519 pairing key** — only devices that completed the pairing flow can
  exchange messages; the relay enforces this via challenge-response authentication.

What the relay **cannot** protect against is the relay operator reading the content
of your messages. The payload (`ct` field) is forwarded as opaque bytes and is not
end-to-end encrypted in the current version. A compromised or malicious relay would
be able to see the commands you send to your Mac and the agent responses.

**If you handle sensitive work — private code, credentials, proprietary data — we
strongly recommend running your own relay.**

---

## Self-hosted relay (recommended for privacy)

Running your own relay means only your devices ever touch the connection. No third
party can observe your traffic.

### Docker (quickest)

```bash
docker run -d \
  --name remote-pi-relay \
  -p 3000:3000 \
  -v remote-pi-data:/data \
  --restart unless-stopped \
  jacobmoura7/remote-pi-relay
```

The relay listens on a **single port** (`3000` by default) and serves three
surfaces at once:

- `GET /` — WebSocket upgrade (the peer protocol)
- `GET /health` — health check (returns `200 OK`)
- `GET / POST /mesh/<owner_pk_hash>` — signed membership versions

Point your app and `pi-extension` to `ws://<your-server-ip>:3000` (or `wss://`
if you put it behind a TLS-terminating reverse proxy such as Caddy or nginx).

**`/data` volume**: the relay stores its SQLite database (signed membership
versions) at `/data/mesh.db` inside the container. Mount a named volume (as in
the example above) or a host directory (`-v /srv/remote-pi:/data`) so the state
survives `docker rm` and image upgrades. Without a mount, the database is
recreated empty each time the container starts and clients re-publish their
state at the next mutation.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `REMOTEPI_RELAY_BIND_ADDR` | `0.0.0.0` | IP address to bind. Use `127.0.0.1` behind a local reverse proxy, a Tailscale/WireGuard interface IP for private-network-only exposure, or `0.0.0.0` for the existing all-interface behavior |
| `REMOTEPI_RELAY_PORT` | `3000` | TCP port that serves the WebSocket upgrade, `/health`, and `/mesh/*` (all on the same port) |
| `REMOTEPI_MESH_DB_PATH` | `/data/mesh.db` in Docker · `data/mesh.db` (cwd-relative) for bare-metal builds | Path to the SQLite database that stores signed membership versions. The parent directory is created automatically on first boot. The Docker image presets this to `/data/mesh.db` and declares `/data` as a volume — see the volume note above |
| `RUST_LOG` | _(none)_ | Log level filter — e.g. `info`, `debug`, `warn` |

Example with a custom port and logging (volume mount is the same):

```bash
docker run -d \
  --name remote-pi-relay \
  -p 8080:8080 \
  -v remote-pi-data:/data \
  -e REMOTEPI_RELAY_BIND_ADDR=127.0.0.1 \
  -e REMOTEPI_RELAY_PORT=8080 \
  -e RUST_LOG=info \
  --restart unless-stopped \
  jacobmoura7/remote-pi-relay
```

### Mesh membership endpoint

The `/mesh/<owner_pk_hash>` endpoint stores **Owner-signed** lists of paired Pis,
keyed by `sha256(owner_pk)` in lowercase hex. It enables an app on a new device
(same Apple ID / Google account) to recover its peer list automatically after
restoring the Owner Ed25519 key from iCloud Keychain / Block Store.

The relay verifies every `POST` against the embedded `owner_pk` using Ed25519
and only accepts versions strictly greater than the current one (monotonic).
Bodies are capped at 500 KB. The relay never decides membership — it only
stores what was signed by the Owner. A compromised relay can deny service but
cannot forge membership without the Owner private key.

**Self-hosting note**: the SQLite database at `REMOTEPI_MESH_DB_PATH`
(`/data/mesh.db` inside the official Docker image) is your operational
responsibility — make sure `/data` is on a persistent volume and back it up
alongside any other server state. If you lose it, clients re-publish their
current view at their next mutation.

**Storage layout**: SQLite runs in the default rollback-journal mode (NOT
WAL), so only `mesh.db` persists. During a write transaction a transient
`mesh.db-journal` may appear in the same directory and is deleted on commit.
Both files live under `REMOTEPI_MESH_DB_PATH`'s parent directory — typically
`/data/` in Docker or `data/` next to the binary on bare metal. The directory
is created automatically on first boot.

### Behind a reverse proxy (HTTPS/WSS)

For production use, put the relay behind a TLS-terminating proxy. Example Caddy config:

```
relay.yourdomain.com {
    reverse_proxy localhost:3000
}
```

Then set your app and `pi-extension` relay URL to `wss://relay.yourdomain.com`.

---

## Building from source

```bash
cargo build --release
./target/release/relay
```

```bash
REMOTEPI_RELAY_BIND_ADDR=127.0.0.1 REMOTEPI_RELAY_PORT=8080 RUST_LOG=info ./target/release/relay
```

## Running tests

```bash
cargo test
cargo clippy -- -D warnings
```
