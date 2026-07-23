<p align="center">
  <img src="https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/branding/logo-full.svg" width="160" alt="Remote Pi logo" />
</p>

<h1 align="center">Remote Pi</h1>

> Extend the [Pi coding agent](https://github.com/earendil-works/pi) with two
> superpowers: agents that talk to each other on the same machine, and a mobile
> app that drives Pi from your phone.

**Homepage:** <https://remote-pi.jacobmoura.work>

`/remote-pi` is a single slash command that wires both at once. Run it; the
first time it asks a couple of questions and you are done.

## Protocol & Security

For wire format, identity model, ACK protocol, cross-PC routing, mesh
membership, and the trust model (what the relay sees and doesn't see),
read [`PROTOCOL.md`](../PROTOCOL.md) at the repo root. It is the canonical
document — this README only covers user-facing setup.

---

## Quick start

Install the extension (one-time):

```bash
pi install npm:remote-pi
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

The LLM calls `list_peers` and reports the complete routing addresses it sees.

Then, still in terminal A:

```text
Send a ping to agent-B using its listed address and ask it to reply later.
```

Pi calls `agent_send({ to: "<exact address from list_peers>", body: {
type: "ping" } })`. For unicast, the call waits only for the broker's delivery
ACK. Terminal B receives the message as a user-facing turn and can answer later
with `agent_send`, setting `re` to the ping's message id; that reply arrives in
terminal A's inbox or a later turn. It does not block terminal A waiting for
agent-B's content reply.

Copy the complete address exactly as listed. Do not build, parse, decode, or
normalize it.

---

## What it does

Remote Pi adds two independent layers on top of Pi. You can use either, or
both:

### 1) Agent network (local broker, optional cross-PC relay)

Several Pi instances running side-by-side in different terminals can discover
each other and exchange messages. Each instance is a peer in a named
*session*. The LLM uses:

- `list_peers` — discover current peer routing addresses
- `agent_send` — unicast waits for the broker delivery ACK; broadcast is
  fire-and-forget

The legacy Pi-only `agent_request` tool is deprecated because it blocks while
waiting for another agent's content reply. Use `agent_send`, continue the
current turn, and receive any later reply through the inbox/turn flow with
`re` correlating it to the original message id.

Peers on the same machine talk over a Unix domain socket at
`~/.pi/remote/sessions/<session-name>/broker.sock`. When sibling PCs are paired,
a leader-capable Extension or MCP participant bridges the opaque cross-PC
addresses over the relay; local-only use stays on UDS when relay access is off.
Useful for splitting work across roles (`backend`, `frontend`, `tests`,
`orchestrator`, …) and letting them coordinate.

The first agent to enter a session becomes the *leader* (hosts the broker);
the rest are *followers*. If the leader exits, a follower automatically takes
over — the failover is invisible to the LLMs.

### 2) Mobile app (over the relay)

The companion mobile app lets you send prompts to Pi and read its responses
from your phone. The phone and the Pi process find each other through a
**relay**: a small WebSocket server that ferries messages between them.
Pairing is one-time and per device, via QR code.

Communication uses WebSocket over TLS to the relay. Fields such as `ct` are
wire containers, not a systemwide end-to-end confidentiality guarantee: current
Pi-forward, cross-PC, app, and control envelopes visible to the relay are not
fully opaque or E2E encrypted. A relay operator can see routed plaintext
protocol content and metadata; see [`PROTOCOL.md`](../PROTOCOL.md) for the exact
trust boundaries.

**Get the app** — all current download options (Google Play, App Store, and
direct builds while public releases roll out):

<https://remote-pi.jacobmoura.work/#get-the-app>

---

## Mobile app actions

Beyond the chat, the app surfaces a small set of typed actions you can run
on the paired Pi session. Tap the ⚙ button next to the message input (visible
when the input is empty) to open the Quick Actions sheet:

| Action | What it does |
|---|---|
| **Compact context** | Runs `ctx.compact()` — same as `/compact` in the TUI. |
| **New session** | Runs `ctx.newSession()` — equivalent to `/new`, asks for confirmation first. |
| **Model** | Opens a model picker fed by your authenticated providers (same source the TUI uses) and switches via `pi.setModel(model)`. |
| **Thinking** | Segmented control with the 6 SDK levels (`off` · `minimal` · `low` · `medium` · `high` · `xhigh`). Changes via `pi.setThinkingLevel(level)`. |

Each action gets a structured `action_ok` / `action_error` reply so the app
can show a SnackBar on failure. Visible side-effects (chat output, model
change broadcasts, compaction notice) still flow through the normal chat
channels. The wire schema is documented in [`PROTOCOL.md`](../PROTOCOL.md)
under "App actions".

It is **not** a generic slash-command picker. The Pi SDK does not expose
programmatic invocation for most builtins (those live in the TUI's
interactive loop), so the app exposes only the actions that have a clean
SDK call. The [`pi-telegram`](https://github.com/llblab/pi-telegram) adapter
follows the same pattern.

### Images

The app can attach **one image** (camera or gallery) to a message. It's
compressed on the device and rides **inline** in the `user_message` — the
optional `images` field carries `{ data: <base64>, mime }`. The pi-extension
turns it into the SDK's multimodal content (an `ImageContent` followed by the
caption `TextContent`) and calls `sendUserMessage(content)`, so the model sees
the picture plus your text.

Whether a model accepts images is surfaced as a `vision` flag on each
`WireModel` (derived from the SDK's `Model.input` including `"image"`); the app
greys out the attach button when the active model is text-only.

The **relay is unchanged** — the image travels inside the same application
message container as the text, so there's no binary channel (large files are a
future track). Base64 or a field named `ct` is not an E2E confidentiality
boundary; the current Relay visibility follows the trust model above. Text-only
messages are unaffected.

---

## Install

Requirements: Node 20+, Pi (the host coding agent).

```bash
pi install npm:remote-pi
```

The extension self-registers the `/remote-pi` slash command and deploys an
agent skill that teaches the LLM how to use `list_peers`, `agent_send`, and the
event-driven inbox/reply flow.

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

1. **Agent name** — the presentation leaf name for this agent. Senders still
   copy the complete opaque address returned by `list_peers`; they never build
   an address from this name. Defaults to the directory name.
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

The relay is the network boundary. TLS protects transit, but the Relay can see
routed plaintext protocol content and metadata; use a relay you trust or
self-host. There is no systemwide or PC-mesh E2E guarantee. For Pi-to-Pi
forwarding, the Relay currently permits a route when any correctly signed Owner
blob lists both canonical Pi keys. That does not prove the Owner paired with or
controls either Pi.

### Upgrade order (Relay 0.3 first, then Extension 0.6)

Upgrade the **Relay to 0.3 first**: an old Extension can consume the new
Relay's UUID errors. Extension 0.6 carries a one-release legacy wire-label
shim, so mixed new/old Extensions interoperate when both select the same unique
colon-free signed nickname label, or when neither has one and both use the
canonical standard-padded key prefix. Delimiter or collision cases, like
divergent nickname views, are unsupported and may be silently dropped by the
old receiver. Upgrade all Extension/MCP participants in one maintenance window.
The shim does not replace the receiver-local aliases returned by `list_peers`;
addresses remain opaque.

Extension 0.6 accepts an old Relay's lowercase 32-hex trusted error ID only as
a narrow shim for an old Relay or Relay rollback; that shim is not why
Relay-first is safe.

You have two options:

### Option A — Use the community relay

`https://relay-rp1.jacobmoura.work` (default). Zero setup. Good for trying
things out or for casual use. (The extension converts to `wss://…`
internally when opening the connection — both schemes point at the same
endpoint.)

Caveats:

- Shared infrastructure — availability is best-effort.
- **There is no IP allow-listing or VPN gating**.

### Option B — Self-host (recommended for privacy)

Run the relay yourself in Docker and put it behind a VPN like
[Tailscale](https://tailscale.com), [WireGuard](https://www.wireguard.com),
or your own VPC. Because the relay's network-level protection is just TLS +
keypair authentication, layering a VPN on top means **only your devices** can
even reach the WebSocket port — defense in depth.

Quick Docker outline (see the
[relay README](https://github.com/jacobaraujo7/remote_pi/blob/main/relay/README.md#self-hosted-relay-recommended-for-privacy)
for the full setup, environment variables, and reverse-proxy guidance):

```bash
docker run -d \
  --name remote-pi-relay \
  -p 3000:3000 \
  --restart unless-stopped \
  ghcr.io/jacobaraujo7/remote-pi-relay:latest
```

Bind the container to your VPN interface, terminate TLS in a reverse proxy,
and point both your Pi and your phone at the resulting `https://…` URL.

### Pointing Pi at your own relay

Once your relay is reachable, tell the extension:

```text
/remote-pi relay url https://relay.yourdomain.tld
```

The URL **must** be `http://` or `https://` — `ws://` / `wss://` are
rejected at validation. The extension converts to WebSocket internally when
it opens the connection. Same canonical form for the mobile app and any
self-hosting docs: paste the URL your reverse proxy exposes.

This writes `~/.pi/remote/config.json` with `{ "relay": "..." }`. Resolution
order (highest precedence first):

1. `REMOTE_PI_RELAY` environment variable (CI / one-off overrides)
2. `~/.pi/remote/config.json`
3. The built-in default (`https://relay-rp1.jacobmoura.work`)

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
multiplexes messages by opaque `to` address and broadcasts system events
(`peer_joined`, `peer_left`).

Inside the LLM, the agent skill uses `list_peers` for discovery and
`agent_send` for delivery:

```jsonc
list_peers() // copy a complete address from this result

agent_send({
  to: "/repo/api@backend", // exact opaque address returned by list_peers
  body: { task: "add /healthz endpoint" },
  re: "<id>" // set to the received message id when replying
})
```

A unicast `agent_send` waits for the broker delivery ACK and returns the public
status `received`, `denied`, or `timeout`; broadcast is fire-and-forget. A
trusted Relay's closed transport reason is returned in `details` without
changing those statuses: `offline` maps to `timeout`, while `not_authorized`
and `bad_envelope` map to `denied`. Genuine silence is a reasonless `timeout`.
Do not blindly retry authorization or envelope failures. Trusted Relay errors
are consumed internally to settle pending sends; forged or invalid reserved
bodies do not gain that authority.

Mesh addresses are opaque routing values: echo them verbatim, including
receiver-local PC aliases with percent-encoded bytes (such as `%3A` or `%25`)
or collision suffixes containing `~`. Never parse, build, decode, or normalize
an address for routing or security. A PC alias is receiver-local presentation
and routing only, so different PCs may list the same sibling under different
aliases. The canonical 32-byte Ed25519 Pi public key is the PC's technical
identity; never use an alias as proof of identity.

`agent_request` remains available only as a deprecated legacy Pi tool. Prefer
`agent_send`, then handle any later inbox/turn reply whose `re` matches the
original message id.

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

### Local session (one Pi, one terminal)

| Command | Description |
|---|---|
| `/remote-pi` | Connect (join local mesh + start relay), or run setup on first use |
| `/remote-pi setup` | Run the setup wizard and update local config |
| `/remote-pi status` | Show local mesh + relay status |
| `/remote-pi stop` | Stop everything for **this** terminal (mesh + relay) |
| `/remote-pi pair` | Show QR code + copy-paste pairing URI for a new mobile device |
| `/remote-pi devices` | List paired mobile devices (online/offline per device) |
| `/remote-pi revoke <shortid>` | Revoke a paired device by its shortid |
| `/remote-pi set-relay <url>` | Persist a new relay URL (http:// or https://) |

### Daemon fleet (one supervisor, N background Pis — see [Daemon mode](#daemon-mode))

| Command | Description |
|---|---|
| `/remote-pi create <cwd> [--name X]` | Register a folder as a daemon |
| `/remote-pi remove <id>` | Unregister a daemon (local config preserved) |
| `/remote-pi daemons` | List registered daemons + state |
| `/remote-pi daemon start` | Start every registered daemon |
| `/remote-pi daemon stop` | Stop every running daemon (`/remote-pi stop` stops only the local terminal) |
| `/remote-pi daemon restart` | Stop + start all daemons |
| `/remote-pi daemon status` | Detailed runtime status (pid, uptime, restart count) |
| `/remote-pi daemon send <id> "<text>"` | Send a prompt to a specific daemon |
| `/remote-pi cron add <id> "<expr>" "<prompt>"` | Schedule a recurring prompt (`--tz`, `--wake`, `--no-skip-busy`, `--catchup`) |
| `/remote-pi cron list` | List scheduled jobs (schedule, enabled, next run, last status) |
| `/remote-pi cron run <jobId>` | Fire a job now (ignores its schedule) |
| `/remote-pi cron enable\|disable <jobId>` | Toggle a job on/off |
| `/remote-pi cron remove <jobId>` | Delete a job |
| `/remote-pi cron log [<jobId>] [--tail N]` | Read the fire/skip audit log |
| `/remote-pi install` | Install `pi-supervisord` as a system service |
| `/remote-pi uninstall` | Remove the system service (registry preserved) |

All commands above work both as Pi slash commands (interactive) and as
shell-level `remote-pi <subcommand>` when the package is installed
globally (`npm install -g remote-pi`).

### Scheduled prompts (`cron`)

`remote-pi cron` schedules **recurring prompts** to daemons through the
supervisor — e.g. a daily "summarise new PRs". Output flows fire-and-forget to
the mesh/app like any prompt; the cron layer only audits the dispatch.

- **Schedule** is a cron expression (croner syntax; an optional 6th *seconds*
  field is supported), with an optional IANA timezone via `--tz`:

  ```sh
  remote-pi cron add a1b2c3d4 "0 9 * * *" "Summarise new PRs" --tz America/Sao_Paulo
  ```

- **Minimum interval is 60s** — more frequent schedules are rejected (guards
  token cost + pileup). A fire is **skipped when the daemon is mid-turn**
  (`--no-skip-busy` to override); `--wake` starts a stopped daemon first;
  `--catchup` runs once on supervisor start if the previous run was missed.
- **Prerequisite**: the supervisor must run as a service (`remote-pi install`).
  Without it there is no scheduler, and `cron` commands say so instead of
  silently pretending to schedule.
- **Audit**: every fire **and** every skip appends one line to
  `~/.pi/remote/cron.jsonl` with a `result` of `delivered`,
  `woke_and_delivered`, `deliver_failed`, `skipped_busy`, `skipped_down`, or
  `skipped_disabled` — read it with `remote-pi cron log`.

Step-by-step walkthrough: the [daemon tutorial](https://remote-pi.jacobmoura.work/tutorials/daemon).

### Footer + title

- `📡 local (N)` — current agent session and peer count (local mesh)
- `🟢 relay` — relay connected, at least one device paired (globally)
- `🟡 relay waiting for pairing` — relay connected, no device paired yet
- `📱 <shortid>` — a mobile device is actively connected right now

Window title: `<agent-name> · On` when relay is up, `<agent-name> · Off`
otherwise. Tells your terminals apart at a glance in `cmux`/`tmux`/iTerm
tabs.

---

## Daemon mode

When you want a Pi to keep running in the background (responding to
mobile prompts at 3am, processing cron jobs, monitoring a folder while
you're not at the keyboard), promote it to a **daemon** managed by a
single OS-level supervisor.

See [`docs/daemon.md`](./docs/daemon.md) for troubleshooting.

### One-time setup

```bash
# Install the package globally so `remote-pi` and `pi-supervisord`
# are on your PATH (`pi install npm:remote-pi` alone makes the Pi
# extension available but does NOT expose the CLI binaries — see
# https://docs.npmjs.com/cli/v10/configuring-npm/package-json#bin).
npm install -g remote-pi

# Install the supervisor as a user-level system service. Linux uses
# systemd --user; macOS uses launchd LaunchAgent. Both auto-start at
# login and survive reboots.
remote-pi install
```

The `install` command:
- Writes `~/.config/systemd/user/remote-pi-supervisord.service` (Linux)
  or `~/Library/LaunchAgents/dev.remotepi.supervisord.plist` (macOS)
- Activates it via `systemctl --user enable --now` or `launchctl bootstrap`
- The supervisor starts immediately and re-starts on every login

### Per-folder workflow

For each agent you want to keep alive 24/7:

```bash
# 1. Configure the agent interactively first (one time).
cd ~/Movies
pi                                 # /remote-pi → setup wizard, /remote-pi pair, etc

# 2. Promote to a daemon. The id is derived from the cwd
#    (sha256(realpath)[:8]), stable across machines.
remote-pi create ~/Movies --name "Video Editor"
# → Daemon registered: id=4e39152d name="Video Editor" cwd=/Users/x/Movies

# 3. Start it (supervisor spawns `pi --mode rpc` for this folder).
remote-pi daemon start
```

Now you can:

```bash
remote-pi daemons                  # list + state
remote-pi daemon status            # uptime, pid, restart count
remote-pi daemon send 4e39152d "Cut the first 30 seconds of latest clip"
remote-pi daemon stop              # stop all
remote-pi daemon restart           # restart all
```

The agent receives the prompt as if a user typed it; its response flows
back through the relay/mesh you configured during interactive setup —
mobile app sees it live, other agents on the same machine can see it
via the local UDS mesh.

### Removing or uninstalling

```bash
remote-pi remove <id>              # unregister one daemon (config preserved)
remote-pi uninstall                # remove the supervisor service (registry kept)
```

`uninstall` is reversible — re-running `install` later brings every
registered daemon back. To wipe the registry entirely, `rm
~/.pi/remote/daemons.json`.

### Where to find logs

| Platform | Command |
|---|---|
| Linux | `journalctl --user -u remote-pi-supervisord -f` |
| macOS | `tail -f ~/.pi/remote/supervisord.log` |

Each spawned daemon's stderr is forwarded into the supervisor's log
with a `[<cwd>]` prefix, so a single log stream shows every agent.

### Caveats (plan/26 trade-offs)

- **Tool approval is not gated.** Daemons inherit the same Pi config
  the interactive run uses — Bash, Edit, Write etc. all execute without
  prompting. Configure Pi's tool permissions to taste before promoting
  a folder to daemon.
- **Pairing still happens interactively.** Daemons don't show a QR
  themselves; the keypair + paired devices come from the prior `pi`
  session in the same folder.
- **Single supervisor.** If `pi-supervisord` crashes all daemons go
  down with it. systemd/launchd restarts it within seconds; daemons
  come back automatically.
- **One daemon per cwd.** The `roomIdForCwd` derivation makes daemons
  by-path; two daemons in the same folder is rejected at `create` time.

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
REMOTE_PI_RELAY=https://staging.example.tld pi
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

**`agent_request` keeps timing out.** It is deprecated because it blocks the
turn while waiting for another agent's content reply. Migrate to `agent_send`;
a unicast waits only for the delivery ACK, and the receiver can reply later
with `agent_send` including `re: "<original-id>"` for correlation.

**Multiple terminals in the same directory.** Supported. They share the same
agent-network session (UDS broker) and the relay handles each Pi process
independently. If the relay refuses with `RoomAlreadyOpenError`, stop the
other terminal first.

---

## Branding

Official brand assets live in
[`/branding`](https://github.com/jacobaraujo7/remote_pi/tree/main/branding) —
SVG sources for the logo (full, foreground, background, monochrome) plus a
banner. See the
[branding README](https://github.com/jacobaraujo7/remote_pi/blob/main/branding/README.md)
for palette and export sizes.

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/branding/logo-full.svg" width="96" alt="logo-full" /><br/>
      <sub><code>logo-full</code></sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/branding/logo-foreground.svg" width="96" alt="logo-foreground" /><br/>
      <sub><code>logo-foreground</code></sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/branding/logo-monochrome.svg" width="96" alt="logo-monochrome" /><br/>
      <sub><code>logo-monochrome</code></sub>
    </td>
  </tr>
</table>

---

## Links

- Homepage: <https://remote-pi.jacobmoura.work>
- Source: <https://github.com/jacobaraujo7/remote_pi>
- Pi coding agent: <https://github.com/earendil-works/pi>
- Relay (self-hosting guide): <https://github.com/jacobaraujo7/remote_pi/blob/main/relay/README.md>
- Issues / bugs: <https://github.com/jacobaraujo7/remote_pi/issues>

---

## License

MIT
