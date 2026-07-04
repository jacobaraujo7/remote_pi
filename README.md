<p align="center">
  <img src="branding/logo-full.svg" width="140" alt="Remote Pi logo" />
</p>

<h1 align="center">Remote Pi</h1>

<p align="center">
  Control your <a href="https://github.com/earendil-works/pi">Pi coding agent</a> from your phone.
  Pair with a one-time QR code and chat with your local agent — even when you're away from your computer.
</p>

---

## Links

- **Official site** — <https://remote-pi.jacobmoura.work>
- **Package documentation** — <https://pi.dev/packages/remote-pi?name=remote-pi>
- **GitHub** — <https://github.com/jacobaraujo7/remote_pi>

### Downloads

| Platform | Status |
|---|---|
| Google Play (Android) | [Get it on Google Play](https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi) |
| App Store (iOS) | [Download on the App Store](https://apps.apple.com/app/remote-pi-coding-agent/id6773499691) |
| APK (sideload, Android) | [GitHub Releases](https://github.com/jacobaraujo7/remote_pi/releases) |

## What's in this repo

| Package | Stack | Role |
|---|---|---|
| [`app/`](./app) | Flutter (iOS / Android) | Mobile client |
| [`pi-extension/`](./pi-extension) | Node + TypeScript | Pi extension exposing `/remote-pi` |
| [`relay/`](./relay) | Rust + Tokio | Stateless WebSocket relay |
| [`site/`](./site) | NextJS | Landing page + legal pages |

## Architecture

```
Flutter app ──wss──► Relay (Rust) ◄──wss── Pi extension (Node)
                                                  │
                                           Local Pi process
                                                  │
                                           UDS broker (local mesh)
                                                  │
                                           Other agents on the same machine
```

- **Pairing** via short-lived QR code; peers persisted in Keychain (mobile) and `~/.pi/remote/` (desktop)
- **TLS in transit** on the WebSocket connection
- **Ed25519 pairing authentication** — only paired devices can route messages through your peer slot on the relay (challenge-response handshake)
- **The relay forwards opaque ciphertext** as far as routing is concerned, but the payload itself is **not end-to-end encrypted in the current version** — see [`relay/README.md`](./relay/README.md) for the security trade-offs

## Local agent mesh

When multiple Pi agents run on the same machine, they discover each other through
a **Unix Domain Socket broker** managed by the extension. One agent wins the
leader election and binds the socket; the others connect as clients. After that,
any agent can send a message or make a request to any other agent by name —
no relay, no network, no extra config.

Two LLM-facing tools are exposed in the Pi chat:

- `agent_send` — fire-and-forget message to another local agent
- `agent_request` — request/response with timeout

This lets you set up local multi-agent workflows (e.g. a `backend` agent asks a
`frontend` agent for help) entirely on your machine, in parallel with the remote
mobile pairing.

## Relay

A free community relay is available at:

```
wss://relay-rp1.jacobmoura.work
```

It's enough to get started, but the relay operator can see the content of your
messages and is a single point of trust for routing. **For sensitive work, we
strongly recommend running your own relay** — it's a single Docker command and
the only thing your traffic ever touches is your own infrastructure.

Full security trade-offs and the self-hosting guide live in
**[`relay/README.md`](./relay/README.md)**.

## Getting started

Install the Pi extension in any project where Pi runs:

```bash
pi install npm:remote-pi
```

Then in the Pi chat, run:

```
/remote-pi
```

The setup wizard walks you through agent name, session name, and relay choice,
then prints a QR code. Scan it with the Remote Pi mobile app and you're paired.

## Statu

The MVP is functional. Planning notes and roadmap live in [`plan/`](./plan).

## License

License is per-package — see each subproject's `LICENSE` file (the `pi-extension`
is MIT). A repository-wide license decision is pending.
