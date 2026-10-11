---
name: cockpit-design
description: Create or edit a file the human will open inside Cockpit: a live `.panel` dashboard or tool (HTML with the `cockpit()` bridge), an `.html` preview, a `.kanban` board, a `.notebook` of notes, a `.ckp` pane layout, or a `.http` request file. Use before writing any of these, even a quick one: it carries the design rules, the bundled CSS and libraries, and the file formats. Not for running queries or commands (cockpit-cli, cockpit-db).
---

# cockpit-design — files the human reads

The human opens these files in Cockpit tabs. A rough first version is a cost
to them, not a draft: follow the rules below **before** writing, then open the
result with `cockpit open <file>` so they see it.

## Pick the format

| You want to show | Write | Format |
|---|---|---|
| live data, buttons that run commands, a dashboard | `.panel` | `references/panel.md` |
| a static page, a report | `.html` (preview, JS off) | same CSS and `--ckp-*` as `.panel` |
| a plan, a roadmap, work in progress | `.kanban` | `references/kanban.md` |
| findings, decisions, notes over time | `.notebook` | `references/notebook.md` |
| terminals to open for a project | `.ckp` | `references/ckp.md` |
| an API call the human can re-run | `.http` | `references/http.md` |
| a query the human can re-run | `.dbq` | `references/dbq.md` |

## Design rules (`.panel` and `.html`)

1. **Start from `cockpit.css`.** First line of `<head>`:
   `<link rel="stylesheet" href="/__cockpit__/cockpit.css">`. It themes
   tables, buttons, inputs, `.card`, `.stat`, `.badge`, `.row/.col/.grid`,
   `.tabs`. Write your own CSS only for what it does not cover, in one small
   `<style>` block.
2. **Only theme colors.** Every color comes from `var(--ckp-*)` (`--ckp-bg`,
   `--ckp-bg-raised`, `--ckp-text`, `--ckp-text-secondary`, `--ckp-text-muted`,
   `--ckp-border`, `--ckp-accent`, `--ckp-ok`, `--ckp-warn`, `--ckp-error`).
   Never a literal hex: the human switches themes and your page must follow.
3. **One anatomy.** Header row (`.row.between`): title on the left, status
   text and actions on the right. Body in `.grid` / `.grid-2` of `.card`s.
   Errors in a `<pre class="error">` at the bottom, never inline in the data.
4. **Three states, always**: loading (`status` text or `.skeleton`), empty
   (`.muted` sentence, never a blank area), error (the `r.error` text).
5. **Numbers are `.stat`s** (`.value` + `.label`), tables are `<table>`,
   identifiers are `<code>`. No number inside a paragraph.
6. **Bundled libraries, never a CDN**: `/__cockpit__/petite-vue.js` for state,
   `/__cockpit__/chart.js` for charts (colors from `cockpit.theme`),
   `/__cockpit__/marked.js` for markdown. `tailwind.js` only for a truly
   custom layout.
7. **One file per tool**, sub-pages via `cockpit.route` (hash routing), not a
   second file.
8. **Density over decoration.** 13px base, 12px gaps, no hero sections, no
   gradients, no icons-as-images. If it looks like a landing page, remove.

## Checklist before saving

- [ ] `cockpit.css` linked first; no literal colors; one `<style>` block or none
- [ ] header row with title + status + actions; `.grid` of `.card`s
- [ ] loading, empty and error states present
- [ ] every `cockpit(...)` result checks `r.ok` and shows `r.error`
- [ ] opened with `cockpit open <file>` and looked at the result (ask the human
      what they see if you cannot)

For `.kanban`, `.notebook`, `.ckp`, `.http` and `.dbq` the rules are in each
reference: they are plain text formats the app renders, so **edit the file
with your normal tools, keep diffs small, never reformat the whole file**.
