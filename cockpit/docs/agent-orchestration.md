# Agent Orchestration

Open **Gallery → Agent Orchestration** to create `agents.orchestration` in the active worktree. The app is a normal tab: drag it into any dock and keep terminals beside it. It has Boxes and Graph views; it never embeds another terminal view.

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

One document is active per worktree. Opening a different `.orchestration` file reuses the app tab and preserves existing terminals, including unrepresented terminals in the new document. Newly created terminals in that worktree are registered automatically, even if the app tab is closed. Editors, task-output views and temporary subagents are excluded. Worktrees where this app was never activated do not get a document automatically.

Closing a terminal with X removes its box and planned connections from the active document. Closing the app tab only hides the app. Closing Cockpit preserves definitions and local bindings. If an external edit removes a live terminal definition, the app asks whether to close it or keep it and restore the definition. Invalid files and failed saves preserve live sessions and show an error; Reload retries.

New terminal uses the last available terminal dock outside the orchestration dock, or creates a split to its right. In Boxes, a single click selects the box and reveals/focuses its real terminal tab. The drag handle only reorders. Graph selection remains separate from terminal focus; double-click / Go to terminal focuses the real tab. The inspector stays inside the app's pane, including its narrow overlay mode.

## Local state and compatibility

Bindings are keyed by worktree/project identity and document path in the local workspace layout. Renaming through the file tree updates that path. On first creation, the Gallery offers to import saved #269 graph configuration, box order, positions and links. Current terminal tabs are included either way without creating duplicates. Global Terminals/Boxes/Graph modes are not used. Existing terminal/dock visuals and native platform controls remain unchanged.

Local files are watched. Active document controllers also check for external changes every five seconds, through the captured local/remote file service, including after the app tab is closed. Reload remains available for an immediate retry. Relative directories must stay inside the worktree; absolute paths and `..` segments are rejected before creating shells. Source view remains available through Open as source.


## Live feedback and role suggestions

Boxes and Graph display the CLI detected in the bound terminal, independently of the configured tool. Narrow box rows keep the CLI below the name; the inspector shows it above configuration. Unknown detection is shown explicitly. Attention badges share the terminal's unseen-result flag and waiting status; opening the real terminal acknowledges results through the existing flow. New terminals join the live subscriptions immediately, without Reload. Context/process telemetry refreshes periodically; session status and CLI changes are event-driven.

A selected box without a role prompts the user to configure it. In its inspector, **Ask agent for role** sends a metadata question to that terminal's running CLI when idle. It neither starts another CLI nor runs during work or an approval prompt. The response is a bounded JSON reply in an OS temporary file, correlated by a fresh request identifier. Local WSL paths use the existing converter. Remote replies use the original host's file service; their temporary file content is cleared afterward. No response paths or runtime identifiers go into the portable document.

The suggested role appears as a preview. **Use suggestion** fills the editable role; **Save** confirms it. Discarding or closing the inspector does not save it. A changed document, terminal, CLI or conversation rejects a late reply. Missing/invalid replies show an error and leave manual configuration available.


Visual subscriptions and graph telemetry pause while the app tab is hidden; the mounted view keeps its state. Returning refreshes metrics and reads current session state. Foreground notifications are grouped per frame, and unchanged session metadata does not rebuild the view. Background document synchronization continues to reconcile external changes.
