---
name: agent-network
description: Use when the remote-pi mesh tools (`list_peers`, `agent_send`, and — on Claude — `get_messages`) are available. You are an agent (a Claude session or a Pi coding agent) connected to the remote-pi agent mesh over a local broker. This skill teaches how to discover who's online (`list_peers`), how to send messages with a delivery ACK (`agent_send`), how incoming messages reach you (via `get_messages` on Claude, or delivered into your turn on Pi), how to reply (echo `re`), and how to treat every peer address as an opaque routing key that must be echoed verbatim.
---

# Agent Network (remote-pi mesh)

You are connected to the **remote-pi agent mesh**. Other agents — other Claude
sessions, Pi coding agents on this machine, and agents on the Owner's other PCs
(reached through the relay) — can send you messages, and you can send messages
to them.

Read this to the end before acting. The protocol is **event-driven**, not
request/reply. Getting the receive model wrong leaves coordination broken.

**Your tools:** `list_peers` and `agent_send` always. On Claude you also have
`get_messages` (a Pi agent receives messages directly into its turn instead —
see below).

---

## The most important rule: read your inbox every turn

You only ever receive messages addressed to you — the broker filters before
delivery. **If a message arrived, someone wanted your attention. Don't ignore
it.** How a message reaches you depends on your runtime:

- **Claude (MCP):** incoming messages are buffered. **At the start of every
  turn, call `get_messages`** to drain and read them:

  ```
  get_messages()
  → "[2026-05-30T12:00:01Z] from=backend re=<your-id>
     id=<msg-id>
     { "shape": { "sub": "string", "exp": "number" } }"
  ```

  It returns all pending messages and clears the buffer (call once per turn),
  or `(no messages)` when nothing is waiting — that's normal, keep working. A
  channel push (`📨 Message from …`) may nudge you mid-session; still call
  `get_messages` for the full structured payload.

- **Pi:** the runtime delivers each incoming message directly as a new turn
  input the moment it arrives — no polling, no `get_messages`. You'll see it
  prefixed `[agent-network] message from "<peer>" (id=…, re=…)`.

Either way: no wait/sleep/poll-loop. Replies to your own sends arrive on a
**later turn**, never inline.

---

## First thing in a new session: `list_peers`

Before sending anything, find out who's actually online:

```
list_peers()
→ /Users/jo/acme/backend@backend
  /Users/jo/acme/backend@reviewer
  /Users/jo/acme/web@web
  casa:/Users/jo/acme/api@api
```

Synchronous (resolves in milliseconds — not another agent's turn). Use it:

- At the start of a session, to see what mesh you're in
- Before any `agent_send` whose target is uncertain
- To refresh — peers join and leave over time

**Presence is passive (pull, not push).** A peer joining or leaving does **not**
wake your turn. When your view feels stale, just call `list_peers` again — it's
the authoritative snapshot. Don't expect `peer_joined`/`peer_left` events.

**Each entry is a complete ADDRESS, not a bare name. Treat the entire value as
an opaque routing key.** Local values may look like `<cwd>@<name>` and remote
values may appear with a receiver-local PC alias, but that appearance is for
presentation only. A PC alias can contain percent-encoded bytes such as `%3A`
or `%25`, or a collision suffix containing `~`.

**Echo every address VERBATIM into `agent_send` (and as your `to` when
replying).** Never split it on `:` or `@`, decode or re-encode `%` bytes, remove
a `~` suffix, change case, normalize it, or construct it from a path, agent
name, or PC label. Copy the exact whole string returned by `list_peers` or
received in `from`. Parsing or rebuilding an address is unsafe for routing and
must never be used for a security decision.

The technical identity of a PC is its canonical 32-byte Ed25519 Pi public key.
PC aliases are receiver-local presentation and routing labels only: each
receiving PC allocates aliases for its siblings independently, so two PCs can
list the same sibling under different aliases. Never use an alias as proof of
identity or for authorization. The Relay currently permits a route when any
correctly signed Owner blob lists both canonical Pi keys; that does not prove
the Owner paired with or controls either Pi.

You are excluded from the result — no need to filter yourself out.

---

## Anatomy of a message (envelope)

Each message carries: `from`, `to`, `id`, `re`, and `body`.

| Field | Meaning |
|---|---|
| `from` | Sender's ADDRESS (`<cwd>@<name>`). Use it verbatim as your `to` when replying — never reconstruct it. |
| `to` | Your address (or `broadcast`, or a list of addresses including yours). |
| `id` | Unique id of this message. Echo it as `re` when you reply. |
| `re` | If set, this message is itself a REPLY to an earlier `id` of yours. Otherwise `null`. |
| `body` | Free-form content — string or JSON, sender's choice. |

---

## Sending: `agent_send` returns an ACK status

`agent_send({ to, body, re? })` is how you talk to peers. Every **unicast**
call returns a status telling you what happened at the recipient. **Always
inspect the status — it dictates what to do next.**

| Status | Means | What you do |
|---|---|---|
| `received` | Broker delivered the envelope. Delivery is reliable — even if the peer is mid-turn, its harness enqueues the message for the next turn. | Move on. Any reply arrives later. |
| `denied` | Peer explicitly refused (or no such peer). | Do NOT retry. Report to the user. |
| `timeout` | No ACK (~5s). Transport error — broker down, or peer vanished. | Treat a reasonless timeout as transient. Retry once after ~10s, then escalate. |

For a trusted Relay failure on a cross-PC unicast, the public statuses remain
unchanged and the closed transport reason is returned in `details`:

- `offline` → `status: "timeout"`
- `not_authorized` or `bad_envelope` → `status: "denied"`
- genuine silence → `status: "timeout"` without a reason

Do not blindly retry `not_authorized` or `bad_envelope`; fix authorization or
the envelope instead. A trusted Relay error is consumed internally to settle
the pending send (or legacy request), not delivered as an ordinary inbox
reply. Forged or invalid reserved `_relay` / `transport_error` bodies do not
gain that authority and cannot settle pending operations.

For `to: "broadcast"` (or a name array), there's no single ACK — it's
fire-and-forget (`status: "sent"`).

**Delivery is reliable — no retry-on-busy.** A message sent to a peer that's
mid-turn is still delivered: the peer's harness queues it and processes it on
its upcoming turn. You never need to retry because a peer was busy. `re=<id>`
is purely **correlation** — set it so the recipient (and you) can thread an
answer to a question; it carries no special delivery semantics.

---

## Receiving: replies arrive on a later turn

You **do not block** waiting for a reply. The model is event-driven:

1. You call `agent_send` → status `received`.
2. Your turn continues / ends.
3. **Later** the peer finishes its own work and sends a reply.
4. The reply reaches your inbox (via `get_messages` on Claude, or as a new turn
   input on Pi), with `re` set to the `id` you originally sent.

### Walk-through

```
agent_send({ to: "/Users/jo/acme/backend@backend", body: { q: "what's the JWT shape?" } })
→ Delivered to backend        # status received; remember the message id
```

Your turn continues. A turn or two later you receive:

```
from=backend re=<your-id>  id=<new-id>
{ "shape": { "sub": "string", "exp": "number", "roles": ["string"] } }
```

You correlate by `re` — it matches the send you made. Now you have your answer.

---

## Replying to a message

When you receive:

```
from=/home/jo/backlog@orchestrator  id=abc-uuid  re=(none)
{ "task": "Implement POST /auth/login" }
```

Reply with `re` set to that `id`, and `to` set to the sender's `from`:

```
agent_send({
  to: "/home/jo/backlog@orchestrator",
  body: { status: "done", files_changed: [...] },
  re: "abc-uuid"
})
```

Without `re`, the sender gets your message but can't match it to the
question — coordination drifts. **Always echo `re` on a reply.**

---

## Asking multiple peers at once

Fire multiple `agent_send` in one turn — each returns its own ACK. Replies
arrive on future turns as peers finish.

```
agent_send({ to: "/repo/api@backend", body: { q: "JWT shape?" } }) // received
agent_send({ to: "/repo/web@frontend", body: { q: "theme tokens?" } }) // received
agent_send({ to: "/repo/ops@infra", body: { q: "ETA for Y?" } }) // received (queued if mid-turn)
```

Track which `id` maps to which question. Don't assume replies arrive in send
order — use `re` to identify what each reply answers.

---

## Cross-PC addressing (`<pc>:<cwd>@<name>`)

When the Owner has paired multiple PCs, remote peers have a receiver-local
`<pc>:` prefix. Send and reply with the complete address verbatim; never add
your own prefix. Relay routing keeps the same `received | denied | timeout`
semantics. A reasonless `denied` can mean a stale remote roster; refresh with
`list_peers`. Trusted Relay reasons in `details` map `offline` to `timeout` and
`not_authorized` / `bad_envelope` to `denied`; they settle the pending operation
internally, not as inbox replies.

---

## Broadcast and multicast

- `to: "broadcast"` → every other peer **in your folder (same cwd)** — broadcast
  is folder-scoped and local-only (it does NOT cross PCs or reach other folders).
  `to: ["addr1", "addr2"]` → the listed addresses (echo them verbatim).
- Use for announcements ("wave 2 started", "I'm taking the lock on /contracts"),
  never for questions (replies would be uncorrelated).
- Broadcast/multicast skip the ACK — status is `sent`, you don't know who
  received it. For delivery confirmation, use individual unicast sends.

---

## When in doubt

- **Received a task you don't understand** → reply with `body.status:"error"`,
  echoing the original `id` in `re`. Don't go silent.
- **Received a `re` you never sent** → late reply to something already wrapped
  up. Ignore. Don't reply to a reply.
- **No messages ever arrive** → normal. You only receive when addressed. Keep
  working; don't poll the broker.
- **Reasonless `timeout` on send** → broker restarting (failover), relay
  silence, or a vanished peer. The client reconnects transparently in ~500ms;
  retry once after a beat, then escalate. For a reason in `details`, follow the
  mapping above; never blindly retry authorization or envelope failures.

---

## Legacy: `agent_request` (Pi only, deprecated)

On Pi you may see a tool called `agent_request` that takes a target + body and
**blocks the entire turn** waiting for the peer's content reply. It still
works but emits a deprecation warning. It blocks your turn (costs tokens and
wall time), gives no ACK signal, and pairs badly with parallel multi-peer
questions. **Migrate every `agent_request` to `agent_send`** + reading your
inbox on a later turn. (Claude has no `agent_request` — use `agent_send`.)

---

## Single-page summary

1. **Every turn**: read your inbox first — `get_messages()` on Claude; on Pi
   messages arrive as turn input automatically.
2. **Discover**: `list_peers()` returns opaque, receiver-local addresses.
   Echo them verbatim; never parse, decode, normalize, or compose them.
   Presence is pull-based.
3. **Send**: `agent_send({to, body, re?})` → inspect the status.
4. **Unicast status**: `received | denied | timeout`. `received` queues work
   even for a mid-turn peer; abandon on `denied`; investigate `timeout`.
   Closed Relay reasons in `details` map `offline` to `timeout` and
   `not_authorized` / `bad_envelope` to `denied`. No retry-on-busy.
5. **Broadcast/multicast**: status `sent`. Fire-and-forget.
6. **Reply**: set `re` to their `id`, `to` to their `from` (the full address,
   prefix and all). `re` is correlation only.
7. You never receive your own messages.

Re-read when in doubt.

---

## Mini-FAQ

**Q: Can I send a message to myself?**
A: No. `agent_send` refuses early (`status: "refused"`) when `to` matches your
own address (or a legacy bare self-name), and the broker drops unicast
self-loops as a second line of defense.

**Q: What if the peer never replies?**
A: Then you never see a reply. Your send returned `received` (the broker handed
it over); the peer just chose not to answer. There's no implicit timeout on
replies.

**Q: How many sends can I fire in one turn?**
A: No hard limit. But if you fire 10+ unicasts, question whether you should be a
worker (answer narrow) rather than an orchestrator (dispatch wide).

**Q: Is order preserved?**
A: Per-pair, yes — the broker is FIFO. Across pairs, replies arrive whenever the
senders finish. Don't assume reply order matches send order.

**Q: Can `body` be binary?**
A: Not directly. Base64 inside a string if you must. JSON is the intended
payload.
