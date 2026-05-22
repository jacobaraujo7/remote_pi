# Remote Pi — Relay

A lightweight WebSocket relay server that connects the **Remote Pi** mobile app to
`pi-extension` processes running on your Operational System. It handles peer routing and presence
tracking without ever reading message content.

For a full overview of the project, see the
[root README](../README.md).

---

## How it works

Every device authenticates with an Ed25519 keypair during the WebSocket handshake
(challenge-response). After that, the relay routes opaque messages between peers
identified by their public key. It never decrypts or inspects payload content.

---

## Public relay

A shared relay is available at:

```
wss://relay.remote-pi.app
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
  --restart unless-stopped \
  jacobmoura7/remote-pi-relay
```

The relay listens on port `3000` by default. Point your app and `pi-extension` to
`ws://<your-server-ip>:3000` (or `wss://` if you put it behind a TLS-terminating
reverse proxy such as Caddy or nginx).

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `REMOTEPI_RELAY_PORT` | `3000` | TCP port the relay listens on |
| `RUST_LOG` | _(none)_ | Log level filter — e.g. `info`, `debug`, `warn` |

Example with custom port and logging:

```bash
docker run -d \
  --name remote-pi-relay \
  -p 8080:8080 \
  -e REMOTEPI_RELAY_PORT=8080 \
  -e RUST_LOG=info \
  --restart unless-stopped \
  jacobmoura7/remote-pi-relay
```

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
REMOTEPI_RELAY_PORT=8080 RUST_LOG=info ./target/release/relay
```

## Running tests

```bash
cargo test
cargo clippy -- -D warnings
```
