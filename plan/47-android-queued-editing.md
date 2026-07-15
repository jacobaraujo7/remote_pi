# 47 — Android queued follow-ups and steer consumption (as built)

**Status:** As-built documentation for `feed4e5c7b08ed4bf1b75db19bd10d19f8621bb4`; this is not an implementation plan.

**Goal:** Record the shipped Android/Pi behavior accurately: Android has one Send action; while Pi is working, Send follows the Pi SDK `steer` path; the explicit Android-owned queued-message protocol/state exists and can be displayed/edited when received, but the composer does not provide a separate action to create queued messages.

**Sources:** the implementation at `feed4e5c7b08ed4bf1b75db19bd10d19f8621bb4` and the confirmed product decision that Android keeps one CLI-style Send/steer action with no separate Queue button.

## Scope and non-goals

- This artifact describes existing behavior only; it proposes no application, extension, relay, or protocol change.
- Android exposes a **single Send** action. There is no separate Queue button or queue-creation action in `InputBar`.
- `onSetQueued` remains a passed-through optional callback, but `InputBar` does not invoke it. It is not a user-facing composer capability.
- Queued-message wire commands and state are implemented independently of that missing composer action. Other callers of `SyncService.queueMessage` or the wire protocol can use them.
- Queues are in-memory, Android-owned, text-only follow-ups. They are not Pi/TUI SDK internal queues and are not durable across Pi process/relay teardown.
- Images use the existing `user_message` path, including steer delivery while working; the explicit `queued_message_set` protocol is text-only.
- Sent-message editing and mutation of Pi/TUI queues are outside this artifact.

## Architecture and state ownership

`SyncService` owns app transport and local queued-message state. `ChatViewModel` observes it and `ChatPage` passes state/callbacks to `InputBar`. The extension owns its module-local `AndroidQueuedItem[]` and broadcasts the canonical `queued_message_state` to active owners.

A queued item uses its own `id` as the drained `user_message` id. A successful drain first removes and broadcasts queue state, then performs the SDK handoff, then echoes a normal `user_message` to every active owner. If the SDK call throws synchronously, the extension restores the item and broadcasts an `internal_error`; later provider/runtime failures are handled by the existing turn/error flow.

## UX (actual Android behavior)

1. **No text or image content:** the idle composer shows the microphone action; the working composer shows Stop. Queued previews, if state exists, render above the composer.
2. **Text or image content:** the same Send button calls `onSend`. This includes an image with an empty caption. There is no alternate queue affordance.
3. **While working:** the hint is `Steer current response…`; typed Send follows `ChatViewModel.sendMessage` and `SyncService.sendMessage`. The app's existing working-state logic supplies `streaming_behavior: "steer"` for a send during a working turn, and the extension also defensively infers steering when room metadata says working.
4. **Queued state received from Pi:** every `QueuedMsg` renders as a preview above the composer. An editable preview can be tapped: the app sends `queued_message_clear` for that item and puts its text back in the composer. Its clear control also sends targeted clear. A read-only preview has neither edit nor clear control.
5. **Stop:** while working with typed content, the existing inline Stop control remains reachable beside Send.

The queued preview copy says `Queued. Tap to edit.` for editable items and `Queued follow-up.` for read-only items. This display/edit support must not be read as evidence of a separate Queue button.

## Steering lifecycle

### Send and SDK delivery

- The wire model has `streaming_behavior?: "steer"` on `user_message` and its echo.
- For any app `user_message`, the extension calls `_wakeAgent(..., "steer")`, which maps to Pi SDK `sendUserMessage(content, { deliverAs: "steer" })`. This matches the CLI-style steer delivery semantics and safely handles the race where the SDK is busy before the relay mirror is updated.
- The extension treats explicit `streaming_behavior === "steer"` or room metadata `working === true` as a steering send. For non-empty trimmed text, it tracks the accepted message id/text in `_pendingSteers` before broadcasting the echoed message with `streaming_behavior: "steer"`.
- An image-only steer with an empty caption is marked as steering by the app but is not added to `_pendingSteers`, because `_trackPendingSteer` ignores empty trimmed text. Therefore it does not receive a per-message `steer_consumed` acknowledgement through this text-matching path. This is a known as-built edge, not a claim that image steering is unsupported.

### Per-message `steer_consumed`

When Pi reports a persisted/started user message, the extension consumes one tracked, non-empty-text pending steer (matching trimmed text when possible, otherwise the oldest pending entry) and broadcasts:

```json
{ "type": "steer_consumed", "id": "<steer-message-id>" }
```

Both `message_start` and `message_end` can observe the persisted user message. `_lastConsumedSteerText` prevents the duplicate observation from consuming a second pending steer. On `agent_end`, that duplicate guard is reset.

The app maps this event to `SteerConsumed` and calls `_clearSteeringLabel(id)`. Therefore `steer_consumed` clears the pending steering status for that exact message, not every pending steering label. The normal `agent_done` path also clears the label for the completed turn id.

## Explicit queued-message protocol/state

### Client to Pi extension

```jsonc
{ "type": "queued_message_set", "id": "msg-2", "text": "next prompt" }
{ "type": "queued_message_clear", "id": "clear-1", "target_id": "msg-2" }
{ "type": "queued_message_clear", "id": "clear-all" }
```

- `queued_message_set` trims text. Non-empty text upserts an Android-owned item by id; reusing an id replaces its text and preserves list position.
- An empty set clears the item whose id equals the request id.
- `queued_message_clear.target_id` removes one item. Omitting `target_id` removes all Android-owned items.

### Pi extension to app(s)

```jsonc
{
  "type": "queued_message_state",
  "id": "msg-2", // legacy first-item compatibility field
  "text": "next prompt", // legacy first-item compatibility field
  "items": [
    {
      "id": "msg-2",
      "text": "next prompt",
      "editable": true,
      "created_at": 1782250000000
    }
  ]
}

{ "type": "queued_message_state", "items": [] }
```

- The extension broadcasts the complete state after upsert, clear, drain, and eligible teardown/reset paths.
- `session_sync` sends `queued_message_state` to the requesting owner before `session_history`.
- The app parses plural `items`; if absent, it falls back to legacy `id`/`text` as one editable item with epoch creation time.
- `SyncService` maps protocol items into immutable `QueuedMsg` values and publishes them to `ChatViewModel`. It removes a local queued item when the corresponding echoed `user_message` arrives.

### Drain behavior and actual busy guard

The queue is drained by `_maybeDrainQueuedItem()` only when:

```ts
_currentTurnId === null && _myRoomMeta?.working !== true
```

This is the actual `_isBusyForQueueDrain()` implementation. `_compactionActive` is not an implementation state and must not be presented as a drain condition.

Drain is attempted from the upstream Pi lifecycle hooks:

- `agent_end`, after the extension broadcasts `agent_done`, clears `_currentTurnId`, flushes image previews, and resets the steer duplicate guard;
- `turn_end`, after it publishes room `working: false`; and
- `session_compact`, after it publishes room `working: false` and broadcasts the compaction event.

`session_before_compact` publishes `working: true`. This upstream working-state bracketing is why compaction blocks draining without a separate compaction boolean. The two ordinary lifecycle hooks allow either `agent_end`/`turn_end` order: drain happens only after both parts of the busy condition are false.

If `queued_message_set` arrives while idle, the extension drains it immediately. The SDK handoff still uses `deliverAs: "steer"`, but the echoed drained `user_message` intentionally omits `streaming_behavior`, so Android displays it as a normal follow-up rather than a pending steer.

`PROTOCOL.md` describes this as requiring no active compaction. In the as-built extension that condition is enforced through the room `working` bracket around compaction, not through a separate `_compactionActive` variable.

## As-built file map

| Area | Implemented files | Actual responsibility |
| --- | --- | --- |
| Protocol documentation | `PROTOCOL.md` | Documents queue commands/state, immediate idle drain, text-only scope, and SDK queue boundaries. |
| Extension protocol | `pi-extension/src/protocol/types.ts` | Defines queue commands, `QueuedMessageItem`, queue state, `streaming_behavior`, and `steer_consumed`. |
| Extension routing/lifecycle | `pi-extension/src/index.ts` | Owns queue state/drain, steer tracking/consumption, session-sync ordering, and lifecycle hooks. |
| App protocol | `app/lib/protocol/protocol.dart` | Parses/encodes queue messages and parses `SteerConsumed`. |
| App sync/domain | `app/lib/data/sync/sync_service.dart`, `app/lib/domain/session_state.dart` | Owns `QueuedMsg` state, queue commands, echoed-item removal, and per-id steering-label clearing. |
| App state/UI | `app/lib/ui/chat/states/chat_state.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/lib/ui/chat/chat_page.dart`, `app/lib/ui/chat/widgets/input_bar.dart` | Exposes queue state, renders previews, and keeps the composer to one Send action. |

## Task 1 — Protocol and state (implemented)

The implementation supplies plural queue state with legacy first-item fields; targeted and all-item clear commands; protocol parsing fallback; and `steer_consumed` parsing. `QueuedMessageItem.created_at` is epoch milliseconds. No queue mode or sent-message-edit protocol was added.

**Matching tests:** `app/test/protocol_test.dart` covers plural/legacy queued state, targeted clear encoding, and `steer_consumed` parsing.

## Task 2 — Extension queue routing and synchronization (implemented)

The extension routes `queued_message_set` and `queued_message_clear`, maintains `_queuedItems`, broadcasts canonical state to active owners, and emits state before history in `session_sync`. Reset/relay-close paths clear non-empty queue state.

**Matching tests:** `pi-extension/src/extension.test.ts` covers working-set broadcast to two owners, targeted clear, sync ordering, and immediate idle drain.

## Task 3 — Extension drain lifecycle and steering consumption (implemented)

Queued drain waits for the actual turn id and room-working guards, handles both `agent_end`/`turn_end` orders, restores an item when the SDK call throws synchronously, and echoes a successfully drained item as a normal `user_message`. It uses Pi SDK steer delivery for the handoff.

Pending steering with non-empty text is recorded for accepted steering sends and cleared one message at a time through `steer_consumed`, with duplicate `message_start`/`message_end` suppression. Reset and compaction behavior is supported directly by the cited source paths but does not have dedicated queue-specific tests in this commit.

**Matching tests:** `pi-extension/src/extension.test.ts` covers idle delivery via `{ deliverAs: "steer" }`, both lifecycle orders, restore after a synchronous throw, exact-text consumption for one pending steer, fallback consumption for one unmatched pending steer, and duplicate-hook suppression. It does not prove later-item selection or oldest-of-many fallback.

## Task 4 — App queue and steering state (implemented)

`SyncService` stores immutable `List<QueuedMsg>`, exposes it through `queuedStream`, sends queue commands when its APIs are called, removes a queued item on its normal echo, and clears a single steering label on `SteerConsumed`. `ChatViewModel` and `ChatReady` relay the list to the UI. The image-only empty-caption edge described above is not tracked by `_pendingSteers`, so this per-id acknowledgement applies to tracked text steers.

**Matching tests:** `app/test/data/sync/sync_service_test.dart` verifies that `steer_consumed` clears only the identified steering row; queue protocol parsing is covered in `app/test/protocol_test.dart`.

## Task 5 — Android composer and queued previews (implemented)

`InputBar` renders received queued previews and supports edit/clear for editable entries. It accepts `onSetQueued`, but contains no handler, icon, or control that calls it. Therefore Task 5 is complete only as preview/edit rendering and one-Send steering UX; it does **not** include a separate Queue button/action.

While streaming with text, `_ComposerActionButton` stays in send-text mode and invokes `onSend`; the same button is the steer-now control. The inline Stop affordance remains visible.

**Matching tests:** `app/test/ui/chat/input_bar_test.dart` verifies that streaming text uses the existing Send button for steer and does not call `onSetQueued`; tapping an editable preview clears it as part of edit; and read-only previews have no clear affordance. The test does not separately tap the dedicated editable-preview clear button. Empty-caption image Send behavior is covered by `app/test/ui/chat/attachment/input_bar_image_test.dart`.

## Task 6 — Historical verification targets

These are the relevant snapshot verification commands for the implementation; this documentation-only revision does not rerun or modify them:

```bash
cd pi-extension && pnpm typecheck
cd pi-extension && pnpm test
cd pi-extension && pnpm build
cd app && flutter test --reporter=compact
cd app && flutter build apk --debug
```

Focused checks corresponding to this behavior:

```bash
cd pi-extension && pnpm exec vitest run src/extension.test.ts -t 'queued|steer'
cd app && flutter test test/protocol_test.dart
cd app && flutter test test/data/sync/sync_service_test.dart
cd app && flutter test test/ui/chat/input_bar_test.dart
cd app && flutter test test/ui/chat/attachment/input_bar_image_test.dart
```

## Definition of Done

- Android has a single Send control; during a working turn it sends through the steer path. There is no separate Queue button/action.
- The extension uses Pi SDK `sendUserMessage(..., { deliverAs: "steer" })` for app sends, including queued-item handoff.
- `steer_consumed` is emitted per consumed tracked, non-empty-text steer and clears only that message's pending steering label in the app; the image-only empty-caption edge is recorded above.
- The explicit Android-owned queued-message set/clear/state protocol, multi-owner broadcast, legacy fields, and session-sync ordering are documented above.
- Queued previews may be displayed/edited/cleared from received state, but the main composer does not create queued messages.
- Queue drain uses `_currentTurnId` and room `working` state, with upstream `agent_end`, `turn_end`, and compaction hooks; it does not depend on `_compactionActive`.
- Idle queued sets drain immediately and echo a normal `user_message` without `streaming_behavior`.
- No Pi/TUI internal queue editing, sent-message editing, persistence, relay change, or separate queue-creation UI/action is claimed.
