# Agent Orchestration

Open **Gallery → Agent Orchestration** to create `agents.orc` in the active worktree. Each document opens as an independent normal tab, movable between docks. Boxes and Graph appear above its own terminal multiplexer, with tabs and splits below. Ordinary workspace terminals and docks keep their existing interface.

Implementation status: scoped UI/lifecycle, version-2 restoration, legacy-profile migration, owned hooks/CLI/notifications and private file presentation are implemented and covered by directed tests. Real Windows acceptance includes independent docks, portable linked worktrees, cold restoration/order, private files, passive tool configuration and public terminal disposal. Legacy-profile cold upgrades, remaining desktop UI/clipboard cases, actual model conversations and real macOS acceptance remain pending; keep the PR in draft until its validation matrix is completed. Do not upgrade an active profile while its terminals are running.

## Edit the JSON source

Use **Open as JSON** in the file-tree context menu, orchestration-tab menu or orchestration toolbar. This opens the same file in the configured text editor, leaving the app and its terminals intact. The Cockpit editor highlights it as JSON and supports the normal save and unsaved-change confirmation flow. In its tab menu, **Open as orchestration** returns to the existing app without closing an unsaved source buffer. Saved changes synchronize through the existing document reconciliation; invalid JSON preserves the last valid configuration and sessions. Both `.orc` and legacy `.orchestration` support these actions.

## Portable document

The JSON format has `version: 1`, an ordered `boxes` array, and planned `links` (`from`/`to` box IDs). Each box has `id`, `title`, optional-role `role`, `harness`, `model`, canvas `x`/`y`, and `directory` (a relative POSIX path under the worktree, default `.`). Box IDs are stable definitions, not terminal IDs. Root-level extension fields are preserved.

```json
{
  "version": 1,
  "boxes": [
    {"id": "api", "title": "API", "role": "Backend", "harness": "codex", "model": "", "directory": ".", "x": 80, "y": 190}
  ],
  "links": []
}
```

Copying the document to another workspace/worktree creates independent blank shells for definitions without local bindings. Loading or editing the document never starts a configured CLI or sends a role prompt. Start CLI, compact and handoff remain explicit session actions. Session IDs, agent conversation IDs, processes, history, credentials and observed metrics are not exported.

The canonical extension is `.orc`; existing `.orchestration` files remain readable. Each file has its own app instance, even within the same worktree. Opening the same file reveals its existing tab; opening another file creates another independent instance. The app never captures existing or newly opened workspace terminals. Only explicit creation inside the app and definitions loaded from that document create owned shells. Gallery activation starts a fresh document with three blank shells; loading a valid empty document leaves it empty. Worktrees where the app was never activated receive no automatic document.

Closing an internal terminal with X removes its box and planned connections. Closing the app tab asks to end its owned terminals; cancel preserves them. Closing Cockpit preserves definitions and local restoration metadata. External removal of a live definition asks whether to close its terminal or restore the definition. Invalid files and failed saves preserve sessions and the last valid configuration and show an error; Reload retries.

New terminal opens within this app's internal multiplexer, without changing the outer dock tree. Boxes single-click reveals and focuses the owned terminal. The drag handle only reorders. Graph single-click reveals without keyboard focus; double-click / Go to terminal focuses it. Internal terminal tabs cannot be dragged into an outer dock or another orchestration instance. Move the whole app tab to reposition it among outer docks. The inspector stays inside the app, including its narrow overlay mode.

## Local state and compatibility

Bindings, child session descriptors and the internal tree/focus belong to the local app instance, under its worktree layout. Selection, view mode, inspector width and terminal-area fractions are local: defaults are 60% for Boxes and 35% for Graph. They do not enter the portable file. A local file-tree rename retargets the existing local instance while preserving its bindings; remote documents with the same path are excluded using their captured filesystem origin. Legacy documents and external sessions must be preserved; the ownership correction starts with a new file instead of importing old bindings. Version-2 restoration validates all bindings and pane placements before creating processes, retains snapshots on failure, and retries only missing sessions. Local startup metadata may resume saved CLI conversations; portable-file loading never does. Legacy-profile migration is implemented; actual desktop cold-upgrade/restoration acceptance remains pending before a profile upgrade is ready.

Theme, fonts, terminal engines and platform infrastructure remain shared. App state is logically isolated by owner, not sandboxed from the operating system. No global Terminals/Boxes/Graph switch is added. Native platform controls remain unchanged.

An open legacy app tab migrates to a new `agents-isolated-<suffix>.orc` file at the same worktree root. It starts with three blank owned shells and does not import old boxes, bindings, roles, outside terminals or conversations. Old files and the outer tab/split placement are preserved. Workspaces without an open legacy app tab do not get a new document automatically.

Migration reserves its destination in the local layout and verifies that checkpoint against disk before creating the file. Creation is exclusive; existing or uncertain partial files are preserved and a fresh destination is reserved. Interrupted creation can reuse a matching generated file without creating duplicates. The completed snapshot is checkpointed before owned shells are reconciled. A save/host failure shows an error and retains recovery data for Reload. Remote hosts need the `fs.create` capability; older hosts reject migration safely without falling back to an overwriting write. Ordinary file editing and layout saves retain their existing behavior.

Local files are watched. Active document controllers also check for external changes every five seconds, through the captured local/remote file service, while the app instance remains open, including when its tab is hidden. Reload remains available for an immediate retry. Relative directories must stay inside the worktree; absolute paths and `..` segments are rejected before creating shells. Source view remains available through Open as source.


## Live feedback and role suggestions

Boxes and Graph display the CLI detected in the bound terminal, independently of the configured tool. Narrow box rows keep the CLI below the name; the inspector shows it above configuration. Unknown detection is shown explicitly. Attention badges use only the instance's owned terminals and waiting status; revealing and focusing an internal terminal acknowledges only its own unread result. Owned completions do not set global badges, play sounds or send OS notifications. New owned terminals join the instance subscriptions immediately, without Reload. Context/process telemetry refreshes periodically; session status and CLI changes are event-driven.

A selected box without a role prompts the user to configure it. In its inspector, **Ask agent for role** sends a metadata question to that terminal's running CLI when idle. It neither starts another CLI nor runs during work or an approval prompt. The response is a bounded JSON reply in an OS temporary file, correlated by a fresh request identifier. Local WSL paths use the existing converter. Remote replies use the original host's file service; their temporary file content is cleared afterward. No response paths or runtime identifiers go into the portable document.

The suggested role appears as a preview. **Use suggestion** fills the editable role; **Save** confirms it. Discarding or closing the inspector does not save it. A changed document, terminal, CLI or conversation rejects a late reply. Missing/invalid replies show an error and leave manual configuration available.


Visual subscriptions and graph telemetry pause while the app tab is hidden; the mounted view keeps its state. Returning refreshes metrics and reads current session state. View updates are grouped per frame, and unchanged session metadata does not rebuild the view. Background document synchronization continues to reconcile external changes.


Hidden tab bodies keep their last valid dimensions while a dock or window is resized. Only displayed terminals track each new grid size; hidden terminals resize once when shown. Inactive workspaces follow the same rule. The cache is presentation-only and does not enter the portable file.

For real-agent and platform acceptance, use the [execution checklist](agent-orchestration-acceptance.md). It is a procedure, not a completed validation result.

## Agent skill

The CLI bundles `cockpit-orchestration` alongside its existing skills. It explains
`.orc`, the three unassigned default terminals, Boxes/Graph and internal tabs,
passive configuration, portability, independent instances and lifecycle rules.
`cockpit install-skill` distributes it through the existing harness installer;
`cockpit install-skill --list` lists the bundled files without installing them.
The skill is in `cli/skills/cockpit-orchestration/SKILL.md`.

## Owned live events

Local, sidecar and remote hook events resolve the exact owned terminal before
updating its app context. Status, context counters, child lifecycles, observed
messages and aliases do not enter the workspace graph or notification controller.
Same-named peers in another app cannot resolve a connection. Ambiguous own aliases
remain unresolved. Pending transcript replies are discarded after conversation
changes, SessionEnd, removal or disposal. Only known own transcripts are read;
owned contexts never enumerate the workspace's terminals for identity discovery.

Foreground badges acknowledge only the selected internal terminal while the app
and native window are focused. Background/minimized completions stay unread in
the app; they do not emit global badges, sound or OS notifications. Focus-source
subscriptions detach when the app is disposed.

Remote CLI labels can use their own main-session hooks, since a remote PID cannot
be probed locally. Child hooks cannot replace the parent's CLI identity; SessionEnd
clears it. Remote transcript paths are never opened as local files. Exact host hook
metrics remain supported; absent host transcript data stays unavailable. WSL
transcript fallback is likewise skipped on Windows instead of interpreting Linux
paths in the client namespace. Local restoration keeps owned conversation identity
and its known transcript path before the first startup hook; these fields remain
outside portable .orc documents.


CLI terminal controls now identify the originating tab independently of their
destination. From an owned shell, listing, reading, sending, creating/splitting
and closing operate inside that document's registry; they cannot select an
unrelated dock or app. Project data tools retain the original worktree/host.
Contextual new/split/selection/direction/close commands now use the app registry,
with private Ctrl-Tab navigation through both terminal engines. Terminal file links
and scoped CLI `open` use a private document presentation in the lower area. The
original terminal host remains mounted with rendering/input suspended while hidden;
returning to a box restores only its own terminal. Files use the originating
worktree/host/cwd captured before asynchronous operations, including reconnect.
Unsaved documents survive switching back to terminals and block replacement or
parent closure until Save/Discard/Cancel. Remote files use source-safe rendering;
remote live panel assets and media are not supported by the existing renderer.
Passing component/transport tests is not macOS desktop acceptance.

Telemetry wrapper open/ingest/close uses the original workspace and document owner,
independently of the selected project or a requested destination. Another .orc or
ordinary workspace terminal cannot ingest into or close that owned run. Closing
an origin during asynchronous run creation closes the newly opened run too.
Store-local run IDs remain unchanged; active lookups include the workspace so an
owned run cannot replace the app diagnostic run. OTLP child resource attributes
carry a qualified routing key, and ambiguous legacy IDs/service names are refused.
Error notices retain their originating document/terminal identity. None of this
runtime identity is written to the portable .orc.


## Native file opening

Windows executable file arguments and Finder open events use the same owned app
routing for `.orc` and legacy `.orchestration` files. Early events wait until the
workspace is restored; opening an already loaded document reveals its existing
app instead of duplicating sessions. The closest containing local worktree is
resolved independently of the selected workspace. Discovery already running is
awaited without starting another git reconciliation.

On Windows the runner forwards through its bundled authenticated CLI before
creating a Flutter engine. The helper uses the exact profile and build flavor,
ignores inherited terminal routing and never falls back to another flavor. This
avoids creating a secondary engine only to immediately tear down its plugins.
The installer provides OpenWith entries; macOS declares an Alternate JSON type.
These declarations preserve other default file handlers. macOS manual acceptance
remains required before merge.
