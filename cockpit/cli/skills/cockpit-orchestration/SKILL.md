---
name: cockpit-orchestration
description: Explain, create or edit Cockpit Agent Orchestration .orc documents and use their Boxes, Graph and owned terminals. Use for the Gallery orchestration app, portable agent layouts and optional terminal roles. The .ckp pane-layout format is a separate feature.
---

# Agent Orchestration in Cockpit

Use the user's language. For explanation-only requests, describe the flow without
editing files, starting tools or creating sessions.

## Open and arrange an orchestration

- **Gallery > Agent Orchestration** creates `agents.orc` at the worktree root
  (a free numbered name if it already exists). The default contains **three
  blank terminals**, named Terminal 1, Terminal 2 and Terminal 3, with no role,
  configured tool or model. No agent starts automatically.
- Open any `.orc` file in Cockpit to get its app tab. The content is versioned
  JSON. Legacy `.orchestration` files remain readable. An explicitly empty
  document stays empty; opening an existing file does not add default terminals.
- **Open as JSON** in the file-tree menu, app-tab menu or app toolbar opens
  the source in the configured text editor while preserving the app and its
  terminals. In a Cockpit source tab, **Open as orchestration** returns to the
  existing app. Save source edits to synchronize; invalid JSON preserves the
  last valid configuration and reports an error.
- Each file owns its terminals. Several files may be open in the same worktree.
  Reopening the same file reveals its existing tab. Workspace terminals and
  other orchestrations are not captured or imported.
- The top area offers **Boxes | Graph**, with internal terminal tabs and splits
  below. Move the whole app tab between outer docks to keep the orchestration
  beside ordinary workspace terminals. Internal terminal tabs stay in their app.
- Inside a terminal, Ctrl-Tab / Ctrl-Shift-Tab cycles that internal pane.
  Contextual New Terminal/Split and tab-selection menu actions stay in the app.
- In Boxes, a row click reveals/focuses its terminal. Use the drag handle to
  reorder rows. In Graph, one click selects/reveals; double-click or **Go to
  terminal** gives keyboard focus. Configuration stays in the app's inspector.

## Configure and run

A terminal is a box even without a role. Name, role, tool and model are optional
configuration; saving them or loading the file does not run a CLI. **Start CLI**,
restart, compact and handoff are explicit actions. **New terminal** adds an owned
blank shell and definition without changing the outer workspace dock tree.

If a role is missing, the user can ask the agent already running in that terminal
for a suggestion. Keep the suggestion uncommitted until the user accepts it and
saves. Do not start an agent or submit a role question just because a field is
empty. Connected CLI/status comes from that terminal, not the configured tool.

Notifications, unread acknowledgements, observed activity and temporary subagents
belong to this app instance. Temporary children are linked to their parent terminal
and are not permanent terminal definitions. Do not use a workspace-wide tab list
to populate or resolve an orchestration document.

## Existing CLI inside an owned terminal

Use `cockpit list-tabs --json` to identify this app's terminals, then the existing
`send --tab-id`, `read-tab`, `new-tab` and `close-tab` commands. `read-tab`/`close-tab` names resolve
inside the same app; ambiguous names require an exact returned terminal ID.
`new-tab --split h` opens a side-by-side internal split. A new terminal has no
role or configured agent until the user chooses them.

The CLI carries its originating tab independently of its destination. Do not
change `COCKPIT_TAB_ID` to impersonate another terminal or use a global tab list
to populate this document. A closed or unknown origin is rejected rather than selecting another
workspace. Project data tools use the sender's worktree and host. Commands that
replace global layouts or manage other workspaces are outside this app's scope.

## Portable file

To create a file directly, use unique stable box IDs and relative worktree
subdirectories. This is the default three-terminal shape:

```json
{
  "version": 1,
  "boxes": [
    {"id":"terminal-1","title":"Terminal 1","role":"","harness":"","model":"","directory":".","x":80,"y":190},
    {"id":"terminal-2","title":"Terminal 2","role":"","harness":"","model":"","directory":".","x":360,"y":190},
    {"id":"terminal-3","title":"Terminal 3","role":"","harness":"","model":"","directory":".","x":640,"y":190}
  ],
  "links": []
}
```

Array order is the Boxes order. `x`/`y` are Graph positions. A planned connection
is `{"from":"terminal-1","to":"terminal-2"}` in `links`; endpoints must exist.
Preserve existing IDs while editing. Leave `harness` and `model` blank unless
requested; use the inspector for supported tool/model options.

Directories resolve against the destination worktree, not the source machine.
Use `.` for its root; absolute paths and `..` are rejected. Copying the file to
another worktree creates independent blank shells for its definitions. It never
reuses the source processes or starts/resumes a configured agent.

Keep runtime terminal/process IDs, conversation IDs, history, credentials,
metrics and local pane/focus preferences out of this file. Those belong to local
app state. Do not add startup commands to the JSON.

## Save, close and recover

Edits synchronize automatically; Reload retries errors. Adding a definition
creates its missing owned shell without starting its tool. Closing an internal
terminal with X removes its definition and planned links. An external edit that
removes a live definition asks whether to end the terminal or restore it.

Closing the app tab confirms ending its owned terminals. Closing Cockpit preserves
local restoration data. Invalid files or failed writes preserve sessions and the
last valid configuration; report the error instead of presenting changes as saved.

The `cockpit orchestrate <file.ckp>` command applies an outer pane layout; it is
not the opener or file format for this Gallery app. Use `.orc` for this feature.
