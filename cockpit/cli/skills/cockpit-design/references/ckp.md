# `.ckp` layout files


A `.ckp` file is a versionable YAML describing terminals to open in a
workspace — the Cockpit equivalent of a tmuxinator layout. One file = one
layout; the layout takes the file's name.

```yaml
# dev.ckp — lives anywhere in the project (usually the root)
autorun: worktree        # optional: auto-apply when a worktree of this
                         # workspace is created (the only autorun trigger)
panes:
  - name: Frontend       # required, unique; becomes the tab's stable label
    cwd: frontend        # relative to this file, forward slashes ONLY
    command: claude      # optional; typed into the shell after it boots
  - name: Backend
    cwd: backend
    split: right         # tab (default) | right (side by side) | down (stack)
    command: npm run dev
    platforms: [macos, linux]   # optional; omit = all OSes
```

Rules:
- `cwd` must be **relative** with `/` separators — absolute paths and `\`
  are rejected so the same committed file works on macOS, Linux and Windows.
- `split` is relative to the **previous pane created in this run**; if that
  one was skipped (merge), the next opens as a plain tab.
- `platforms` accepts a string or list of `macos`/`windows`/`linux`.
- In the app, right-click a `.ckp` file → **Open layout** does the same as
  `cockpit orchestrate` (replace); the app asks for confirmation only when a
  tab to be closed has a running process.

Apply one with `cockpit orchestrate <file.ckp> [--append]` (see cockpit-cli).
