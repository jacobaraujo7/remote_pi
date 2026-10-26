# `.kanban` files


A `.kanban` file is a **markdown board**: the app renders it as columns and
cards, but it stays plain markdown on disk. There is no `cockpit kanban`
verb and you do not need one — **edit the file with your normal file tools**.
The open tab reloads by itself as soon as you save.

Use `cockpit open board.kanban` to put it in front of the human.

```markdown
---
title: Roadmap                                   # the tab's label
columns: [Backlog, Doing, Review, Done]          # documentation; `##` is what counts
labels: {relay: orange, bug: red, ui: purple}    # name -> palette color
---

## Doing

- [ ] Túnel SSH no host <!-- id: k3 labels: relay, infra -->
      Free markdown note, indented under the title.

      <!-- comment: 2026-09-07T08:30 -->
      Newest comment.

      <!-- comment: 2026-09-06T19:22 -->
      Older comment.

## Done

- [x] Absorver o plugin de PTY <!-- id: k1 -->
```

Rules that matter when you write one:
- **Columns are `##` headings**; cards are top-level `- [ ]` / `- [x]` items
  under them. Order in the file is the order on screen.
- **The last column means done.** The app keeps `[x]` in sync with position,
  so move a card *and* flip its checkbox together — a `[x]` sitting in
  `Backlog` is the one inconsistency the human will see.
- **Ids are optional.** Write cards without `<!-- id: -->`; the app injects one
  the first time the card is moved from the UI. Keep an id you find — it is
  how the card is tracked across edits.
- **Labels** are `labels: a, b` inside the card's HTML comment, and only get a
  color if the frontmatter declares one. An undeclared label still works (grey).
- **Notes** are the indented lines right under the title, up to the first
  comment marker.
- **Comments** are blocks opened by `<!-- comment: <ISO minute> -->`, indented
  like the note. **Newest first**: insert a new one directly *above* the
  existing ones (right after the note), so file order is reading order.
- **Anything the parser does not model survives.** A stray paragraph inside a
  column shows up as a read-only card instead of being dropped, and no edit
  the app makes ever rewrites the whole file — so your formatting, comments and
  blank lines stay put.

Two things to prefer:
- Writing a `.kanban` beats reporting a plan in chat when the human should be
  able to follow it later: the board is a file they can open, drag and commit.
- Editing the file beats driving the UI. Keep the diff small (the app does the
  same — a card move is a three-line diff), and never reformat the whole file.
