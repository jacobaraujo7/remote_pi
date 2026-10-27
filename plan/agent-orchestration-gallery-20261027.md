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
