# Agent Orchestration — Gallery app

## Approved behavior

A normal Gallery document tab (`agents.orchestration`, versioned JSON) with Boxes/Graph and its own inspector, alongside unchanged terminal/dock visuals. One active document and app tab per worktree; alternate documents reuse the tab. Copying a document creates independent blank shells; configured CLIs only start explicitly. Newly created terminals are discovered in the owning worktree even while the view tab is closed. X removes definitions; external removal of live definitions requires Close or Keep and restore.

## Source / dependency audit

- Base main: a69fe71b7022e2ba31c002063fb582a7c11746e6, verified directly again during implementation.
- #269, moregola, main ← feature/grafo-terminals: selective source for graph domain, telemetry, CLI/hooks, native lifecycle fix and widgets. Its current checks are green on Windows, macOS ARM/Intel and CLI Linux/macOS/Windows. Keep open; do not mark superseded before complete replacement coverage is proven and a successor link exists.
- #257, cfbraun, main ← feat/cockpit-status-line-ctrltab: independent focus/status/Ctrl-Tab change. Preserve; Jacob coordinates overlap before merge.
- #267, pretodev, main ← feat/text-editor-engine-excepts: independent specialized-preview/editor routing change. Preserve; `.orchestration` is routed explicitly, without importing that PR wholesale.
- Personal/open-source repository; BTN does not apply, per global AGENTS scope.

## Implementation and owners

Codex: portable document/controller, serialized document creation/open/load per worktree, local bindings, Gallery entry, dockable view, terminal destination resolution, passive configuration and explicit session actions. File IO uses captured project/host identity. Native terminal views remain exclusively in their original docks. Closing the view does not stop the controller or terminals. Clean-exit paths wait for queued document writes before flushing local state.

moregola: user acceptance of the new daily workflow on Windows. Jacob: code review and coordination of overlapping PRs. macOS manual validation: moregola to arrange a real Mac; no host is available yet.

## Validation record

- Windows: local native debug build passed. Directed Flutter suite: 98 tests passed, including portable copies, concurrent/repeated load, discovery, local binding restoration, pending/accepted/declined removals, failed saves, dock destination, Ghostty/xterm lifecycle, attachments, hooks, metrics and five component renders.
- Directed analysis passed before final creation/open serialization changes; final directed run pending.
- Rust CLI: final fmt/Clippy/tests pending on this branch; source includes the already green #269 fix.
- Clean checkouts: new CI workflow covers Windows, macOS ARM and macOS Intel with native tests and builds; macOS app build is universal and unsigned for validation only. Results pending publication of this branch.
- Manual macOS: pending, no machine available. Includes native menus, Cmd+C/V/F, clipboard/drag, trackpad, Retina, fullscreen and window lifecycle. CI does not replace this acceptance.
- Images are actual production-component renders with fictional sessions and a fixture tab strip; they are not native desktop screenshots. See cockpit/review/agent-orchestration/README.md.

## Next step

Codex to finish final validation, push feature/agent-orchestration-gallery and prepare the PR with these images and an explicit validation matrix. Keep #269 open until coverage and platform acceptance are complete. moregola then evaluates the new flow; Jacob reviews the successor.

## User evaluation before publication

- User requested a local run with the latest sessions before any PR. PR publication is on hold for that evaluation; no successor PR has been created.
- Implementation committed locally as d8f7978f; isolated-storage helper selectively restored from #269 as 20405802 for the local trial.
- Windows directed analysis is clean; 98 targeted tests passed plus 5 storage-path tests. Windows native debug build passed before the storage-helper restoration; refreshed build in progress.
- Latest PR269 profile was copied only after the user confirmed closing that app: 13 project records, 3 realms, 24 layout records, 34 saved terminal descriptors and 11 agent resume identifiers. Source profile remains unchanged.
- Trial install: %LOCALAPPDATA%/Programs/Cockpit Agent Orchestration; dedicated profile: %LOCALAPPDATA%/Cockpit-Agent-Orchestration. Shortcut in Desktop and Start menu. Codex to verify writes use that profile before handing over; moregola owns flow evaluation.
- First launch exposed that main lacked the isolated-root helper. The just-launched trial was stopped and corrected; no PR was published.

- Final local run verified: build 20405802 compiled successfully; app responding from the dedicated install; two layouts were rewritten with `orchestrationBindings` under the isolated profile at 11:34 (local machine time), proving the migrated profile is actually in use. No Flutter error recorded after this boot. PR remains on hold for moregola's evaluation.

## Evaluation adjustment — single-click navigation

- User requested that clicking a Boxes row takes them to its terminal. Boxes now selects and reveals/focuses the bound real terminal on a single click; drag handles remain reorder-only, and Graph single-click selection remains independent.
- Added the assertion to the actual app-component render test; existing drag regression remains applicable. Local build update pending; PR still on hold for evaluation.
- The earlier crash report has not been reproduced: process remains alive and the app currently renders the orchestration and adjacent terminals. No new Flutter exception/dump was registered. The only native crash event found was the old PR269 app on close (coremessaging.dll, 0xc0000005, 11:28). No claim of a crash fix.

- Single-click update c5de43ae applied locally: 12 relevant tests passed, directed analysis clean, Windows debug build passed. User confirmed closing; the old process remained alive, so Codex backed up the saved state and ended only that trial instance before replacing binaries. The same isolated profile was reopened under Flutter; process responding and layout writes verified at 11:53. No new PR published. Next: moregola evaluates single-click terminal focus.


## Evaluation fix — moving a terminal into the orchestration dock

- User supplied the exact trigger: drag a terminal into another dock, including the dock containing Agent Orchestration. The trial became unresponsive and reached approximately 6.45 GB. Diagnostics show `TerminalRenderBox.attach` subscribing to an already disposed `frameChanges` notifier in flterm. This is distinct from the earlier PR269 native close event.
- Reproduced the identical stack in a Windows native widget regression using the production `AdaptiveTerminalPane` before applying the fix. A global terminal key alone does not prevent the deactivate/activate cycle when changing docks.
- Codex moved tab bodies into stable workspace-level hosts, keyed by session. Dock operations now update geometry and visibility, including when the source dock disappears; native views and focus nodes remain mounted. Existing tab strips, splits and drop targets are retained. Explicitly reuse the session-owned Ghostty scroll controller. No flterm override or dependency change.
- The regression uses real `PaneDropZone` drag targets and Ghostty/xterm adapters. It covers an actual drag into the orchestration dock, removal of the emptied source dock, twelve repeated moves, preservation of terminal/app elements and history, and keyboard focus after clicking the moved terminal. Added it to the Windows/macOS ARM/macOS Intel CI matrix.
- Windows: 40 directed tests passed and full `flutter analyze --no-pub` passed. Analysis also exposed a missing `wslProcessId` getter in the Neovim test fake and six small lint issues; these are corrected, and the relevant tests pass. Refreshed native debug build pending installation.
- Current isolated state and capped diagnostics were backed up under `%LOCALAPPDATA%/Cockpit-Agent-Orchestration/backups/freeze-dock-20261027-123935` before stopping only the frozen trial. Preserve this current profile for the update; do not recopy the older PR269 profile.
- PR audit repeated directly against `jacobaraujo7/remote_pi`: #269 remains open as the selective source (moregola; retain until successor coverage is established); #257 remains independent (Jacob; preserve its focus/status work); #267 remains independent (pretodev; preserve editor routing). Codex owns this fix and local rerun. moregola owns the next Windows acceptance test. No successor PR until that evaluation. Manual macOS remains pending a real machine, with moregola arranging availability.

- Local update completed: Windows debug build passed (60.1 s), installed snapshot hash verified against the build, and code commit `9a6a2abd` reopened at 12:52 using the unchanged current isolated profile. Resumed session-start events observed. Process 59576 responding, approximately 718 MB, and no Flutter errors in the fresh diagnostic log after startup. The capped original log and previous-run marker are preserved in the freeze backup. User acceptance of the desktop drag remains the next step; this local rerun is not macOS acceptance.


## Evaluation feedback — attention, connected CLI and automatic refresh

- User requested notification indicators in Boxes/Graph, visible connected CLI, automatic updates, and consulting the existing agent for a role suggestion with human confirmation.
- Added shared waiting/unseen-result badges. CLI labels now come from the terminal's detected runtime rather than its configured box tool, including narrow rows and the inspector. Graph status prefers current terminal events over cached telemetry.
- Replaced the one-time merged terminal-list snapshot with a listener bridge that rebinds on additions/removals. Existing/new sessions update immediately. Document polling every five seconds complements local watching and supplies automatic remote reload; it skips unchanged content and retries dirty saves without replacing local configuration. Polling belongs to the document controller and stops on disposal.
- Missing roles have a configure prompt. The inspector can ask the idle connected agent for a suggestion using a correlated, bounded JSON reply in temporary storage. Suggestions stay outside the portable document until explicitly accepted and saved. Concurrent requests coalesce; changed targets reject stale answers. Tests do not send messages into the user's real agents; actual agent-response acceptance remains with moregola.
- Validation: 41 targeted tests passed, including dynamic subscriptions, external changes, save retries, reply correlation/cancellation, suggestion confirmation, narrow CLI/notification UI, component renders and Ghostty/xterm dock lifecycle. Full Flutter analysis clean. Windows debug build passed (63.5 s). No dependency override or lockfile change.
- Applied 96 updated libraries to the existing trial via Flutter hot reload, preserving PID 59576 and live sessions. The process remained responsive. Stage the fresh build for the next shortcut launch without overwriting the running process's mapped snapshot. Codex owns packaging and validation; moregola owns user acceptance. No PR publication before acceptance.
- Audit refreshed directly: #269 (moregola) remains the selective reference and stays open; #257 (cfbraun) owns independent status-line/rotation/focus work; #267 (pretodev) owns editor/preview routing. Reviewed their file lists: shared VM/page/i18n areas require integration care, but neither supplies these orchestration session subscriptions or badges. Preserve both, no wholesale branch incorporation. Jacob remains the intended reviewer of the successor.
- A separate pre-update log entry at 12:53 reports `NeovimSettingsViewModel.check` notifying after disposal. It predates this metadata reload and did not freeze the app. Codex to triage that settings lifecycle separately; do not claim it fixed here. macOS manual validation remains pending a machine; moregola to arrange one.
