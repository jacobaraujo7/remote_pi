# Remote Pi

> Extend the [Pi coding agent](https://github.com/earendil-works/pi) with two
> superpowers: agents that talk to each other on the same machine, and a mobile
> app that drives Pi from your phone.

`/remote-pi` is a single slash command that wires both at once. Run it; the
first time it asks a couple of questions and you are done.

---

## Quick start

Install the extension (one-time):

```bash
pi install npm:@jacobmoura7/remote-pi
```

Then in any Pi terminal:

```text
/remote-pi
```

The first run shows a short interactive wizard (agent name, default session,
whether to auto-start the relay). On every following run, `/remote-pi` joins
the local agent session and starts the relay automatically — no extra typing.

### Try the agent network in 30 seconds

Open **two** Pi terminals in the same directory and run `/remote-pi` in each.
Both join the same session. Now just talk to the LLM — it has the tools.

In terminal A (say it ended up named `agent-A`):

```text
Who else is connected in our agent session? List them.
```

The LLM calls `agent_send` to `broker` with `{ type: "list_peers" }` and
replies with the names it sees.

Then, still in terminal A:

```text
Send a ping to agent-B and wait for a reply.
```

Pi calls `agent_request({ to: "agent-B", body: { type: "ping" } })`. The
message arrives in terminal B as a user-facing turn — terminal B's LLM
answers, and the reply lands back in terminal A. Two agents, one prompt
each, full round trip.

(Replace `agent-B` with whatever name terminal B reports for itself — the
wizard's default is the directory name plus a `#N` suffix on collision.)

---

## What it does

Remote Pi adds two independent layers on top of Pi. You can use either, or
both:

### 1) Agent network (local, same machine)

Several Pi instances running side-by-side in different terminals can discover
each other and exchange messages. Each instance is a peer in a named
*session* and gets two tools the LLM can call directly:

- `agent_send` — fire-and-forget message to another agent
- `agent_request` — send and await a reply (correlated by message id)

This is purely local: the agents talk over a Unix domain socket at
`~/.pi/remote/sessions/<session-name>/broker.sock`. No network involved.
Useful for splitting work across roles (`backend`, `frontend`, `tests`,
`orchestrator`, …) and letting them coordinate.

The first agent to enter a session becomes the *leader* (hosts the broker);
the rest are *followers*. If the leader exits, a follower automatically takes
over — the failover is invisible to the LLMs.

### 2) Mobile app (over the relay)

The companion mobile app lets you send prompts to Pi and read its responses
from your phone. The phone and the Pi process find each other through a
**relay**: a small WebSocket server that ferries end-to-end encrypted
messages between them. Pairing is one-time and per device, via QR code.

Encryption uses Curve25519 key agreement + ChaCha20-Poly1305 (libsodium).
The relay sees only ciphertext.

App downloads:

- **Google Play** — *coming soon*
- **App Store** — *coming soon*

Until the public releases land, follow
[the repo](https://github.com/jacobmoura7/remote-pi) for build/beta info.

---

## Install

Requirements: Node 20+, Pi (the host coding agent).

```bash
pi install npm:@jacobmoura7/remote-pi
```

The extension self-registers the `/remote-pi` slash command and deploys an
agent skill that teaches the LLM how to use `agent_send` / `agent_request`.

To verify:

```text
/remote-pi config
```

It should print the effective relay URL and where it came from
(`env` / `config` / `default`).

---

## Using `/remote-pi`

The bare command is the everyday entry point:

```text
/remote-pi
```

Behavior depends on whether there's a local config for this directory:

| State | What happens |
|---|---|
| First run (no `.pi/remote-pi/config.json`) | Interactive wizard → saves config → joins agent session → starts relay (if you opted in) |
| Returning user, auto-start enabled | Joins agent session + starts relay automatically, then prints status |
| Returning user, auto-start disabled | Prints status only; join/relay must be run manually |

The wizard asks three questions:

1. **Agent name** — how other agents will address you in `agent_send` /
   `agent_request`. Defaults to the directory name.
2. **Default session** — the name of the agent-network room for this
   directory. Multiple terminals in the same directory join the same session.
3. **Auto-start relay (for mobile app access)?** — `Yes` if you want
   `/remote-pi` to also connect to the relay so the mobile app can reach this
   Pi. `No` for local-only use (agent network without mobile access).

Re-run the wizard later with `/remote-pi setup`.

---

## Pairing a mobile device

Once the relay is up (`/remote-pi relay status` shows `started` or `paired`):

```text
/remote-pi pair
```

A QR code is printed in the terminal. Scan it with the Remote Pi mobile app.
Pairing is **per machine** — once a device is paired, every Pi process on
this machine accepts it (it lives in `~/.pi/remote/peers.json`).

To list paired devices:

```text
/remote-pi devices
```

To remove one:

```text
/remote-pi revoke <shortid>
```

The shortid is the first 8 chars shown by `devices`.

---

## The relay

The relay is the only network-touching piece of Remote Pi. It does **not**
read messages — payloads are end-to-end encrypted between the Pi and the
paired device — but it sees connection metadata: which keypair is online,
which room/cwd identifiers exist, message timing, sizes.

You have two options:

### Option A — Use the community relay

`wss://relay.remote-pi.dev` (default). Zero setup. Good for trying things
out or for casual use.

Caveats:

- Shared infrastructure — availability is best-effort.
- The operator could observe connection metadata as described above.
- TLS + per-message encryption is the only protection; **there is no IP
  allow-listing or VPN gating**.

### Option B — Self-host (recommended for privacy)

Run the relay yourself in Docker and put it behind a VPN like
[Tailscale](https://tailscale.com), [WireGuard](https://www.wireguard.com),
or your own VPC. Because the relay's network-level protection is just TLS +
keypair authentication, layering a VPN on top means **only your devices** can
even reach the WebSocket port — defense in depth.

Quick Docker outline (see the
[relay README](https://github.com/jacobmoura7/remote-pi/blob/main/relay/README.md#self-hosted-relay-recommended-for-privacy)
for the full setup, environment variables, and reverse-proxy guidance):

```bash
docker run -d \
  --name remote-pi-relay \
  -p 3000:3000 \
  --restart unless-stopped \
  ghcr.io/jacobmoura7/remote-pi-relay:latest
```

Bind the container to your VPN interface, terminate TLS in a reverse proxy,
and point both your Pi and your phone at the resulting `wss://…` URL.

### Pointing Pi at your own relay

Once your relay is reachable, tell the extension:

```text
/remote-pi relay url wss://relay.yourdomain.tld
```

This writes `~/.pi/remote/config.json` with `{ "relay": "..." }`. Resolution
order (highest precedence first):

1. `REMOTE_PI_RELAY` environment variable (CI / one-off overrides)
2. `~/.pi/remote/config.json`
3. The built-in default (`wss://relay.remote-pi.dev`)

Verify the active URL and its source with:

```text
/remote-pi config
```

If you change the URL while connected, run `/remote-pi relay stop` then
`/remote-pi relay start` (or `/remote-pi relay` to toggle).

The mobile app has its own relay-URL setting in its preferences pane — keep
both pointing at the same relay.

---

## Agent network: deeper look

Each session is one Unix-domain-socket broker plus N peers. The broker
multiplexes messages by `to` name and broadcasts system events
(`peer_joined`, `peer_left`).

Inside the LLM, the agent skill registers two tools:

```jsonc
// Fire-and-forget
agent_send({
  to: "backend",      // peer name (or array for multicast)
  body: { task: "add /healthz endpoint" },
  re: "<id>"          // optional — set when replying to a previous request
})

// Send + await reply (default 30s timeout)
agent_request({
  to: "backend",
  body: { question: "is the migration applied?" }
})
```

The wire format is a 5-field envelope `{ from, to, id, re, body }` serialized
as one JSON line per message. The leader's broker writes an `audit.jsonl`
log at `~/.pi/remote/sessions/<name>/audit.jsonl` for postmortem inspection.

Useful commands:

| Command | What it does |
|---|---|
| `/remote-pi join [name]` | Join (or create) a session — only needed manually if `auto_start_relay=false` |
| `/remote-pi leave` | Leave the current session |
| `/remote-pi sessions` | List local sessions and which are live |
| `/remote-pi rename <new>` | Rename this agent in the current session |

Name collisions inside a session get a numeric suffix automatically
(`backend`, `backend#2`, `backend#3`). The broker assigns it and returns the
real name to the peer.

---

## Command reference

| Command | Description |
|---|---|
| `/remote-pi` | Connect (join session + start relay), or run setup on first use |
| `/remote-pi setup` | Run the setup wizard and update local config |
| `/remote-pi join [name]` | Join (or create) a local agent session |
| `/remote-pi leave` | Leave the current agent session |
| `/remote-pi rename <name>` | Rename this agent in the current session |
| `/remote-pi sessions` | List local agent sessions |
| `/remote-pi relay` | Toggle the relay connection on/off |
| `/remote-pi relay start` | Connect to the relay |
| `/remote-pi relay stop` | Disconnect from the relay |
| `/remote-pi relay status` | Show current relay status |
| `/remote-pi relay url <url>` | Set the relay URL (alias of `/remote-pi set-relay`) |
| `/remote-pi pair` | Show a QR code to pair a new mobile device |
| `/remote-pi devices` | List paired mobile devices |
| `/remote-pi revoke <shortid>` | Revoke a paired device by its shortid |
| `/remote-pi set-relay <url>` | Persist a new relay URL to user config |
| `/remote-pi config` | Show the effective relay URL and its source |

The footer in the Pi TUI reflects state live:

- `📡 <session> (N)` — current agent session and peer count
- `🟢 relay` — relay connected, at least one device paired
- `🟡 relay waiting for pairing` — relay connected, no device paired yet
- `📱 <shortid>` — a mobile device is actively connected right now

The window title becomes `<agent-name> · <session> · relay` so you can tell
your terminals apart at a glance.

---

## Configuration files

| Path | Scope | What's in it |
|---|---|---|
| `<cwd>/.pi/remote-pi/config.json` | Per-directory | `agent_name`, `session_name`, `auto_start_relay` |
| `~/.pi/remote/config.json` | Per-user | `relay` URL |
| `~/.pi/remote/peers.json` | Per-machine | Paired mobile devices |
| `~/.pi/remote/sessions/<name>/` | Per-session | Broker socket + `audit.jsonl` |
| `~/.pi/remote/skills/agent-network/SKILL.md` | Per-user | Agent skill the LLM reads |

Override the relay for a single run without persisting:

```bash
REMOTE_PI_RELAY=wss://staging.example.tld pi
```

---

## Troubleshooting

**Footer says `🟡 relay waiting for pairing` even though I paired a device.**
The icon reflects whether *any* device has been paired on this machine, not
whether one is connected right now. If you really have a paired device in
`/remote-pi devices`, restart Pi — the cache may be stale (fixed in current
release; report a bug if it recurs).

**Mobile app times out connecting.** Verify the same relay URL is configured
on both sides. If you self-host behind a VPN, your phone must also be on the
VPN (Tailscale on iOS/Android works fine).

**`agent_request` keeps timing out.** Default timeout is 30 s. For tasks
that legitimately take longer, the receiver should reply with `agent_send`
including `re: "<original-id>"` so the requester can correlate. The skill
explains this to the LLM automatically.

**Multiple terminals in the same directory.** Supported. They share the same
agent-network session (UDS broker) and the relay handles each Pi process
independently. If the relay refuses with `RoomAlreadyOpenError`, stop the
other terminal first.

---

## Links

- Source: <https://github.com/jacobmoura7/remote-pi>
- Pi coding agent: <https://github.com/earendil-works/pi>
- Relay (self-hosting guide): <https://github.com/jacobmoura7/remote-pi/blob/main/relay/README.md>
- Issues / bugs: <https://github.com/jacobmoura7/remote-pi/issues>

---

## License

MIT
