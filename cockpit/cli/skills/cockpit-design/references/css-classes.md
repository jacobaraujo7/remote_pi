# `cockpit.css` — classes you get for free

Link it first: `<link rel="stylesheet" href="/__cockpit__/cockpit.css">`. Bare
elements (`h1`…`h4`, `p`, `a`, `code`, `pre`, `table`, `button`, `input`,
`select`, `textarea`, `label`) are already themed. Classes below are the only
layout you should need; reach for a `<style>` block only after.

## Page anatomy

| Class | Use |
|---|---|
| `.page` | the content column: max width, vertical gaps. Wrap everything in it |
| `.toolbar` | header row: `<h1>` left (truncates), `.status` text, then buttons |
| `.kpis` | a responsive row of `.card.stat` tiles |
| `.grid` / `.grid-2` / `.grid-3` | body grids of `.card`s (collapse on narrow panes) |
| `.split` | list + detail: `.list` (scrolls, `.item`, `.item.active`) and a detail `.card` |
| `.row` / `.col` / `.between` / `.grow` / `.wrap` | flex helpers |
| `.tabs` | tab strip of `<button>`s, `.active` marks the current one |

## Pieces

| Class | Use |
|---|---|
| `.card` | bordered raised box |
| `.stat` with `.value` + `.label` | one number, big, with its caption |
| `.badge` (`.ok` `.warn` `.error` `.accent`) | small pill |
| `.status-dot` (`.ok` `.warn` `.error` `.running`) | 8 px dot; `.running` pulses |
| `.kv` | `<dl>` as key/value grid (`<dt>` muted, `<dd>` value) |
| `.empty` | the empty state: a dashed box with a muted sentence |
| `.skeleton` | loading placeholder bar (shimmers); stack 2 or 3 in a `.col` |
| `.muted` / `.secondary` / `.mono` / `.truncate` / `.scroll` / `.right` / `.center` | text helpers |
| `button.primary` / `button.danger` / `.btn` (for `<a>`) | button variants |

## Colors

Only `var(--ckp-*)`: `--ckp-bg`, `--ckp-bg-raised`, `--ckp-text`,
`--ckp-text-secondary`, `--ckp-text-muted`, `--ckp-border`,
`--ckp-border-strong`, `--ckp-code-bg`, `--ckp-link`, `--ckp-accent`,
`--ckp-accent-soft`, `--ckp-accent-text`, `--ckp-ok`, `--ckp-warn`,
`--ckp-error`. For Chart.js read them from `cockpit.theme['--ckp-accent']`
and redraw on `cockpit.on('theme', …)`.
