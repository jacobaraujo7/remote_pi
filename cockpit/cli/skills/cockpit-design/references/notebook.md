# `.notebook` folders


A folder whose name ends in `.notebook` is a **notebook**: one markdown file
per note, each with a small YAML frontmatter. The app shows the folder as a
single item in the file tree and opens it as a notes tab — notes grouped by
tag on the left, the note on the right. Obsidian opens the same folder as-is.

Write notes here while you work when the human should be able to read them
later: findings, decisions, open questions, a summary of what you changed.
Prefer **many short notes with tags** over one long file.

```markdown
---
title: Túnel SSH no host
tags: [relay, agent]
created: 2026-09-07T10:12
updated: 2026-09-07T11:40
---

Body in plain markdown.
```

The easy way is the verb — it writes the frontmatter for you, picks a unique
file name (`2026-09-07-tunel-ssh-no-host.md`) and refreshes the open tab:

```sh
cockpit note add notes.notebook --title "Túnel SSH no host" --tag relay \
  --body "Porta 2222 fechada no firewall; abri via ufw."
cockpit note add notes.notebook --title "Resumo da sessão" --body - <<'NOTE'
- Corrigi o parser do .kanban
- Falta: testes do watcher
NOTE
cockpit note list notes.notebook          # title  [tags]  path
```

Rules that matter:
- `--tag` may repeat. The **`agent` tag is always added** by the verb — it is
  how the human tells your notes from theirs. Keep it if you edit a note by
  hand.
- A note without frontmatter still works (title = file name, no tag), so
  editing an existing `.md` with your normal file tools is fine. The tab
  reloads by itself.
- The **file name never changes** when the title changes; the title is
  metadata. Don't rename files to "fix" titles.
- Keep the frontmatter keys as they are (`title`, `tags`, `created`,
  `updated`); the app rewrites only those lines and leaves the body untouched.
- **Link notes with `[[Title]]`** (exact title, case-insensitive). The app
  renders it as a clickable chip and lists backlinks on the target note. Use
  it to connect a finding to the decision it led to, or a summary to the
  notes it summarizes.
- Images: put files under `_assets/` inside the notebook and reference them
  as `![](_assets/name.png)` — the app draws them inline.
