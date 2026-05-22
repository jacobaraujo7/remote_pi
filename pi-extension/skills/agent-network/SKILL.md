---
name: agent-network
description: Use when you (a Pi agent) are running inside a local agent session — i.e., when the Pi footer shows "📡 <session-name>". This skill teaches how to receive messages from other agents, how to reply in a correlatable way, how to ask things of other agents without losing track, and how to act when you don't yet have the context you need.
---

# Agent Network (skill — message protocol for Pi agents)

You are connected to a **local agent session** over a Unix Domain Socket.
Other Pi agents running on the same machine, in the same session, can send
you messages. You can send messages to them too.

This skill teaches how to participate in that network reliably. Read it to
the end before acting — understanding the protocol avoids silence and
deadlocks.

---

## The most important rule

**You only receive messages that were explicitly addressed to you.** The
session broker filters before delivery. You will never see messages
intended for other agents or "broadcast with `exclude_self`".

**Practical consequence**: if a message arrived in your inbox, someone
wanted your attention. Don't ignore it. Don't assume it was for someone
else.

---

## Anatomy of a message (envelope)

Every message has 5 fields:

```json
{
  "from": "orchestrator",
  "to": "backend",
  "id": "uuid-v7",
  "re": null,
  "body": <message contents>
}
```

| Field | Meaning |
|---|---|
| `from` | Who sent it. Use this to know who to reply to |
| `to` | You (or "broadcast", or a list of names including yours) |
| `id` | Unique identifier of this specific message |
| `re` | If this message is a REPLY to another, echoes that one's `id`. Otherwise `null` |
| `body` | Free-form content. String or JSON object, sender's choice |

---

## When you receive a message

Do this in order, don't skip steps:

1. **Look at `body`** to understand what's being asked
2. **Look at `from`** to know who to reply to
3. **Look at `id`** — this is the `correlation_id` you'll need to echo
4. **Execute the work** described in `body`
5. **Reply** with a new message:
   - `to`: the `from` of the original message
   - `id`: a fresh UUID v7 (your reply has its own identity)
   - `re`: the `id` of the original message (correlation)
   - `from`: your name
   - `body`: your answer

**Always reply.** If the sender sent something that clearly expects a
reply (not a broadcast announcement), silence breaks their coordination.
Even errors must be replied (with `body.status: "error"`).

### Concrete example

You (name: `backend`) receive:

```json
{
  "from": "orchestrator",
  "to": "backend",
  "id": "abc-uuid",
  "re": null,
  "body": {
    "task": "Implement the POST /auth/login endpoint",
    "context_ref": "./contracts/auth.md"
  }
}
```

You do the work. You reply:

```json
{
  "from": "backend",
  "to": "orchestrator",
  "id": "xyz-uuid",
  "re": "abc-uuid",
  "body": {
    "status": "done",
    "summary": "Endpoint implemented per contract",
    "files_changed": ["src/auth/login.ts", "src/auth/jwt.ts"]
  }
}
```

The orchestrator correlates via `re === "abc-uuid"` and knows this was
the reply to their task. Without `re`, they receive the message but
can't match it against the question — and wait until timeout.

---

## When you need to ask another agent (mid-task)

Before replying to a task, you may discover you need info from another
agent. Typical scenario: you are `frontend`, you received a task to
implement the login screen, but you don't know the exact JWT shape the
`backend` exposes.

**Correct flow** (synchronous via request/reply):

1. Pause your current task (don't reply to the orchestrator yet)
2. Send a message to `backend`:
   ```json
   {
     "from": "frontend",
     "to": "backend",
     "id": "new-uuid",
     "re": null,
     "body": {
       "question": "What's the exact payload shape of the JWT returned by POST /auth/login?",
       "context": "needed for FE parsing"
     }
   }
   ```
3. **Wait for the reply** with `re === "new-uuid"`
4. Use the received info to complete your original task
5. Reply to the orchestrator (with `re === "<original task id>"`)

The transport layer (`agent_request()`) blocks until the reply arrives
or times out. Use a reasonable timeout (30–60s for simple questions).

### Limits

- **Ask focused questions**, not disguised delegations. "What's the
  shape of X?" is fine. "Can you implement Y for me?" is not — that's
  work the orchestrator should distribute.
- **Maximum 1 hop**: if you asked B, and B needs to ask C to answer
  you, B should **fail** with `status: "blocked"` and let the
  orchestrator re-plan. Don't chain A → B → C → ...
- **Timeout mandatory**: never wait indefinitely. If no reply in 60s,
  fail with `status: "blocked"` in your answer to the orchestrator,
  citing which peer didn't respond.

---

## Asking multiple agents in parallel

You frequently need info from **several agents at once** before you can
proceed. The transport supports this natively — every `agent_request()`
returns a `Promise`, and each request has a unique `id` so the pending
map demuxes replies correctly. **Multiple requests in flight never get
confused with each other.**

Don't serialize what can run in parallel. Sequential = sum of all
latencies. Parallel = max of latencies. With 3 agents at 200ms each:
serial is 600ms, parallel is 200ms.

### Pattern 1 — wait for all (most common)

```typescript
const [beAnswer, feAnswer] = await Promise.all([
  agent_request("backend", { question: "JWT shape?" }),
  agent_request("frontend", { question: "current theme tokens?" }),
]);
// both arrived, you have both answers, continue your work
```

### Pattern 2 — fan-out structured

```typescript
const peers = ["backend", "frontend", "infra"];
const answers = await Promise.all(
  peers.map((p) => agent_request(p, { question: "ETA for Y?" }))
);
// answers[i] correlates to peers[i] by array index
```

### Pattern 3 — race (first answer wins)

```typescript
const winner = await Promise.race([
  agent_request("worker-1", taskBody),
  agent_request("worker-2", taskBody),
]);
// useful for redundant queries; losing requests still finish
// in the background but their replies are silently dropped
```

### Pattern 4 — tolerant of partial failure

```typescript
const settled = await Promise.allSettled([
  agent_request("a", q1, 30_000),
  agent_request("b", q2, 30_000),
]);
const okReplies = settled
  .filter((r) => r.status === "fulfilled")
  .map((r) => r.value);
const failures = settled
  .filter((r) => r.status === "rejected")
  .map((r) => r.reason);
// proceed with what you got; report failures honestly
```

### Limits (same as 1-on-1 questions)

- **Max 1 hop still applies to fan-out.** You can ask N agents in
  parallel, but each of them must reply directly to you. They cannot
  themselves fan-out to satisfy your question. If B needs C and D to
  answer your question, B replies `status: "blocked"` and the
  orchestrator re-plans.
- **Per-request timeout**: each call has its own timer. One slow agent
  doesn't block the others — `Promise.all` rejects fast on first
  failure (use `allSettled` if you need tolerance).
- **Focused questions, not delegations** — same rule as 1-on-1.

### Mental model

The `pending` map inside the transport correlates replies by their `re`
field against the original `id`s you sent. As long as `id`s are unique
(UUID v7, guaranteed), N parallel requests stay isolated. You can have
dozens in flight without confusion — though if you need that many,
question whether you should be a worker instead of an orchestrator.

---

## Advanced addressing

### Broadcast

`to: "broadcast"` delivers to everyone except the sender. Use rarely:

- ✅ Announcements: "wave 2 started", "leader changed to X"
- ❌ Questions: no one replies to broadcasts, because no one knows
  who's supposed to answer

### Multicast

`to: ["backend", "frontend"]` delivers to the listed recipients. Useful
for directed notifications, e.g.: "both of you: stop touching
`contracts/` while I update it".

Each recipient gets the same message (same `id`). If you reply, `re`
correlates normally.

### Self

You never receive your own messages (even on broadcast). No need to
filter; the broker does it.

---

## Auto-discovery of who's in the session

You may receive, at some point after joining, `system` events from the
broker:

```json
{
  "from": "broker",
  "to": "backend",
  "id": "uuid",
  "re": null,
  "body": {
    "type": "peer_joined",
    "name": "frontend",
    "capabilities": ["typescript", "react"]
  }
}
```

```json
{
  "from": "broker",
  "to": "backend",
  "id": "uuid",
  "re": null,
  "body": {
    "type": "peer_left",
    "name": "frontend"
  }
}
```

Use these events to know who's online. Keep a mental list (or session
state) of active peers. Don't ask a peer you know is offline.

If you need to list active peers on demand, ask the broker:

```json
{
  "from": "backend",
  "to": "broker",
  "id": "uuid",
  "re": null,
  "body": { "type": "list_peers" }
}
```

The broker replies with `body: { peers: [...] }`.

---

## Situations where you're in doubt

### "I received a message I don't understand"

Reply with `status: "error"` and say what was unclear. Don't go silent.

```json
{
  "from": "backend",
  "to": "<original sender>",
  "id": "...",
  "re": "<original id>",
  "body": {
    "status": "error",
    "summary": "I didn't understand the request. The 'task' field is unclear."
  }
}
```

### "I received a message with `re` set, but I never sent a request"

Probably a late reply to a request that already timed out or was
cancelled. Ignore silently. Don't reply.

### "I received a message without `re`, but it's clearly a reply"

Treat it as a new message (task). The sender didn't follow protocol —
you can't correlate it with your original request even if you sent one.
If genuinely confused, reply asking: "Is this message a reply to
something? I didn't see a `re`."

### "I'm in a session but no message ever arrives"

Normal. You only receive when someone addresses you. Keep working in
solo mode until someone calls. Don't poll the broker periodically.

### "The leader died (peer_left event from `broker`)"

The transport layer will automatically promote another peer to leader.
You (client) will reconnect transparently in ~500ms. During that
window, your `send/request` calls may fail — retry once after 1s
before propagating an error.

---

## Single-page summary

1. You only receive what's addressed to you. Don't filter. Trust the broker.
2. Every reply carries `re` = `id` of the original message. Without it,
   the sender can't correlate.
3. Reply's `to` = question's `from`.
4. Always reply — success or error — when you receive something that
   looks like a task.
5. You can ask other agents mid-task (request/reply, synchronous), but:
   - Max 1 hop
   - Always with timeout
   - Read-only question ("what is X?"), not delegation ("do Y")
6. **You can ask multiple agents in parallel** with `Promise.all` —
   each request's `id` keeps replies isolated. Don't serialize what can
   run in parallel.
7. Broadcast is for announcements, not questions.
8. When confused, reply with `status: "error"` instead of staying silent.

That skill is everything you need to participate in the session without
breaking other agents' flow. Re-read it when in doubt.

---

## Mini-FAQ

**Q: Can I send a message to myself?**
A: No. Both `agent_send` and `agent_request` refuse early with an
error (`"cannot agent_send to yourself"`) when `to` matches your
assigned name. The broker also drops unicast self-loops as a second
line of defense. There's no upside — just do the work directly
instead of round-tripping through the network.

**Q: What happens to messages I sent before the recipient joined?**
A: The broker drops them with a warning log. There is no persistent
message queue. If you need delivery guarantees, wait for the
`peer_joined` event before sending.

**Q: Can I have the same name as another agent?**
A: No. The broker auto-suffixes (e.g., you asked for `backend`, you
get `backend#2` in `register_ack`). Use the name the broker gave you
(`name_assigned`) in all your messages.

**Q: Can `body` be binary?**
A: Not directly. Use base64 inside a string if needed. But you're
probably using this for text/JSON — don't make binary the use case.

**Q: Is there message priority?**
A: Not in MVP. Order is FIFO of arrival at the broker. If you need
priority, open an issue.

**Q: How do I discover other peers' capabilities (stack, role)?**
A: `peer_joined` events carry `capabilities` in `body`. Save them when
peers enter. Or ask the broker via `list_peers`.

**Q: Can I disconnect any time?**
A: Yes. The transport sends `peer_left` automatically when you close.
Other agents will see you go.

**Q: How many parallel requests is "too many"?**
A: There's no hard limit, but if you're firing 10+ in parallel,
question whether you're the wrong layer. Orchestrators dispatch wide;
workers should answer narrow. If you're a worker fanning out to many
peers, you may be doing the orchestrator's job.

---

## See also

- [`plan/19-agent-network-rfc.md`](../plan/19-agent-network-rfc.md) — motivation and context
- [`plan/19-agent-network.md`](../plan/19-agent-network.md) — implementation plan
- `~/.pi/remote/sessions/<name>/audit.jsonl` — append-only log of everything that passed through the broker (read-only audit). Legacy path preserved (2026-05-21 decision — no storage migration)
