# Agent Orchestration

Open **Gallery → Agent Orchestration** to create `agents.orchestration` in the active worktree. Each document opens as an independent normal tab, movable between docks. Boxes and Graph appear above its own terminal multiplexer, with tabs and splits below. Ordinary workspace terminals and docks keep their existing interface.

Implementation status: the scoped UI and lifecycle are integrated in this checkpoint. Version-2 startup restoration is wired and covered by directed tests; legacy-profile migration, contextual CLI and shortcut/hook routing are still under implementation. Do not install this checkpoint over an existing profile or treat it as the completed isolation correction.

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

Each file has its own app instance, even within the same worktree. Opening the same file reveals its existing tab; opening another file creates another independent instance. The app never captures existing or newly opened workspace terminals. Only explicit creation inside the app and definitions loaded from that document create owned shells. Gallery activation starts a fresh document with one blank shell; loading a valid empty document leaves it empty. Worktrees where the app was never activated receive no automatic document.

Closing an internal terminal with X removes its box and planned connections. Closing the app tab asks to end its owned terminals; cancel preserves them. Closing Cockpit preserves definitions and local restoration metadata. External removal of a live definition asks whether to close its terminal or restore the definition. Invalid files and failed saves preserve sessions and the last valid configuration and show an error; Reload retries.

New terminal opens within this app's internal multiplexer, without changing the outer dock tree. Boxes single-click reveals and focuses the owned terminal. The drag handle only reorders. Graph single-click reveals without keyboard focus; double-click / Go to terminal focuses it. Internal terminal tabs cannot be dragged into an outer dock or another orchestration instance. Move the whole app tab to reposition it among outer docks. The inspector stays inside the app, including its narrow overlay mode.

## Local state and compatibility

Bindings, child session descriptors and the internal tree/focus belong to the local app instance, under its worktree layout. Selection, view mode, inspector width and terminal-area fractions are local: defaults are 60% for Boxes and 35% for Graph. They do not enter the portable file. Renaming through the file tree retargets the existing instance. Legacy documents and external sessions must be preserved; the ownership correction starts with a new file instead of importing old bindings. Version-2 restoration validates all bindings and pane placements before creating processes, retains snapshots on failure, and retries only missing sessions. Local startup metadata may resume saved CLI conversations; portable-file loading never does. Legacy-profile migration and actual desktop restoration acceptance remain pending before a profile upgrade is ready.

Theme, fonts, terminal engines and platform infrastructure remain shared. App state is logically isolated by owner, not sandboxed from the operating system. No global Terminals/Boxes/Graph switch is added. Native platform controls remain unchanged.

Local files are watched. Active document controllers also check for external changes every five seconds, through the captured local/remote file service, while the app instance remains open, including when its tab is hidden. Reload remains available for an immediate retry. Relative directories must stay inside the worktree; absolute paths and `..` segments are rejected before creating shells. Source view remains available through Open as source.


## Live feedback and role suggestions

Boxes and Graph display the CLI detected in the bound terminal, independently of the configured tool. Narrow box rows keep the CLI below the name; the inspector shows it above configuration. Unknown detection is shown explicitly. Attention badges use only the instance's owned terminals and waiting status; revealing and focusing an internal terminal acknowledges only its own unread result. Owned completions do not set global badges, play sounds or send OS notifications. New owned terminals join the instance subscriptions immediately, without Reload. Context/process telemetry refreshes periodically; session status and CLI changes are event-driven.

A selected box without a role prompts the user to configure it. In its inspector, **Ask agent for role** sends a metadata question to that terminal's running CLI when idle. It neither starts another CLI nor runs during work or an approval prompt. The response is a bounded JSON reply in an OS temporary file, correlated by a fresh request identifier. Local WSL paths use the existing converter. Remote replies use the original host's file service; their temporary file content is cleared afterward. No response paths or runtime identifiers go into the portable document.

The suggested role appears as a preview. **Use suggestion** fills the editable role; **Save** confirms it. Discarding or closing the inspector does not save it. A changed document, terminal, CLI or conversation rejects a late reply. Missing/invalid replies show an error and leave manual configuration available.


Visual subscriptions and graph telemetry pause while the app tab is hidden; the mounted view keeps its state. Returning refreshes metrics and reads current session state. View updates are grouped per frame, and unchanged session metadata does not rebuild the view. Background document synchronization continues to reconcile external changes.


Hidden tab bodies keep their last valid dimensions while a dock or window is resized. Only displayed terminals track each new grid size; hidden terminals resize once when shown. Inactive workspaces follow the same rule. The cache is presentation-only and does not enter the portable file.
