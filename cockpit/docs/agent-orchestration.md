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

New terminal uses the last available terminal dock outside the orchestration dock, or creates a split to its right. Single-click selects a box; double-click / Go to terminal reveals and focuses the real terminal tab. The inspector stays inside the app's pane, including its narrow overlay mode.

## Local state and compatibility

Bindings are keyed by worktree/project identity and document path in the local workspace layout. Renaming through the file tree updates that path. On first creation, the Gallery offers to import saved #269 graph configuration, box order, positions and links. Current terminal tabs are included either way without creating duplicates. Global Terminals/Boxes/Graph modes are not used. Existing terminal/dock visuals and native platform controls remain unchanged.

Local files are watched; remote files use the existing remote file service and the app's Reload action. Relative directories must stay inside the worktree; absolute paths and `..` segments are rejected before creating shells. Source view remains available through Open as source.
