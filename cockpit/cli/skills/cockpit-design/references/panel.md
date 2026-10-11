# `.panel` files


A `.panel` file is a **live HTML page** with a bridge to the app: the tab runs
the page in a web view and injects `window.cockpit`, so buttons and scripts in
it can run Cockpit CLI verbs and shell commands on this machine. Use it as a
playground: a quick dashboard to validate something, a form that triggers a
task, a status board that polls `git`/`db`. One file, no server, no ports.

Write it with your normal file tools (`cockpit open x.panel` puts it in front
of the human). The open tab reloads by itself when you save. The file is a
plain HTML document with an optional YAML frontmatter on top:

```html
---
title: Repo status     # tab label (default: file name)
reload: true           # reload the page when the file changes (default true)
cwd: .                 # working dir for exec/CLI calls, relative to this file
---
<!doctype html>
<meta charset="utf-8">
<style>body { background: var(--ckp-bg); color: var(--ckp-text) }</style>
<button onclick="run()">git status</button>
<pre id="out"></pre>
<script>
async function run() {
  const r = await cockpit("exec git status --short");
  document.getElementById("out").textContent = r.ok ? r.stdout : r.error;
}
</script>
```

The bridge is one function. `await cockpit("<line>")` runs `cockpit <line>`
exactly as you would type it in a tab, and resolves to
`{ok, code, stdout, stderr, json, error}`: `json` is the parsed stdout when
the verb printed JSON (`list-tabs --json`, `db query`, `exec --json`),
`error` is the stderr (or the exit code) when `ok` is false. Anything the CLI
can do, a panel can do: `db query main 'select ...'`, `exec npm test`,
`send --tab-id t3 --enter 'make'`, `run-task npm:dev`, `note add ...`.
`cockpit.on("theme", vars => ...)` fires when the app theme changes;
`cockpit.theme` holds the current `--ckp-*` CSS variables (`--ckp-bg`,
`--ckp-text`, `--ckp-text-muted`, `--ckp-border`, `--ckp-code-bg`,
`--ckp-link`, `--ckp-accent`), already set on `:root` so plain CSS can use
them (also `--ckp-bg-raised`, `--ckp-text-secondary`, `--ckp-border-strong`,
`--ckp-accent-soft`, `--ckp-accent-text`, `--ckp-ok`, `--ckp-warn`,
`--ckp-error`). Relative assets (`<img src="chart.png">`,
`<script src="app.js">`) resolve inside the file's folder only. External links
open in the OS browser. There is no allowlist: a panel can run anything the
human could run in a tab, so only put in it what you would type yourself.

### Bundled libraries (`/__cockpit__/…`) — no network, no build step

The app ships a small set of libraries and serves them at the reserved path
`/__cockpit__/<name>`. Use these instead of a CDN: they work offline, are the
same version on every machine, and never touch the user's repo. Prefer them for
anything beyond a plain page.

| URL | What | Use it for |
|---|---|---|
| `/__cockpit__/cockpit.css` | classless base styles + a few utilities, themed by `--ckp-*` | **always include it first**: tables, buttons, inputs, `.card`, `.stat`, `.badge`, `.row/.col/.grid`, `.tabs` look native and follow the app theme |
| `/__cockpit__/petite-vue.js` | petite-vue 0.4 (Vue syntax, 6 KB, `PetiteVue.createApp`) | reactive state, lists, forms, conditional views. Default choice for any interactive panel |
| `/__cockpit__/chart.js` | Chart.js 4 (UMD, `new Chart(canvas, cfg)`) | dashboards: line/bar/pie over `db query` / `exec` output |
| `/__cockpit__/marked.js` | marked 15 (`marked.parse(md)`) | render markdown from notes, results, README |
| `/__cockpit__/tailwind.js` | Tailwind v4 browser build (runtime JIT, ~250 KB) | only when you want utility classes instead of `cockpit.css`; heavier to load |

`cockpit.route` gives hash routing for multi-page panels in one file:
`cockpit.route.path` (`"/"`, `"/job/3"`), `cockpit.route.go("/job/3")`,
`cockpit.route.match("/job/:id")` → `{id:"3"}` or `null`, and
`cockpit.on("route", r => ...)` on every change. Use `<a href="#/job/3">` for
links. Do not link to another `.panel` file: navigation to a second file
renders it as raw HTML (its frontmatter is only read for the opened tab).

Minimal reactive dashboard (copy this shape):

```html
---
title: Git dashboard
---
<!doctype html>
<meta charset="utf-8">
<link rel="stylesheet" href="/__cockpit__/cockpit.css">
<script src="/__cockpit__/petite-vue.js"></script>
<script src="/__cockpit__/chart.js"></script>
<div v-scope="App()" @vue:mounted="load" v-cloak>
  <div class="tabs">
    <button :class="{active: page==='/'}" @click="cockpit.route.go('/')">Status</button>
    <button :class="{active: page==='/log'}" @click="cockpit.route.go('/log')">Log</button>
  </div>
  <div v-if="page==='/'" class="grid">
    <div class="card stat"><span class="value">{{ files.length }}</span><span class="label">changed files</span></div>
    <div class="card"><canvas id="chart"></canvas></div>
  </div>
  <table v-else><tr v-for="l in log"><td class="mono">{{ l }}</td></tr></table>
  <p v-if="error" class="error">{{ error }}</p>
</div>
<script>
function App() {
  return {
    page: cockpit.route.path, files: [], log: [], error: '',
    async load() {
      cockpit.on('route', r => { this.page = r.path; });
      const st = await cockpit('exec git status --short');
      if (!st.ok) { this.error = st.error; return; }
      this.files = st.stdout.split('\n').filter(Boolean);
      const lg = await cockpit('exec git log --oneline -20');
      this.log = lg.ok ? lg.stdout.split('\n').filter(Boolean) : [];
      new Chart(document.getElementById('chart'), { type: 'bar',
        data: { labels: ['changed'], datasets: [{ data: [this.files.length],
          backgroundColor: cockpit.theme['--ckp-accent'] }] } });
    },
  };
}
PetiteVue.createApp().mount();
</script>
```

Rules of thumb: `cockpit.css` first, petite-vue for state, one `.panel` per
tool, hash routes for sub-pages, `cockpit.theme['--ckp-*']` for chart colors
(re-draw on `cockpit.on('theme')`). Reach for `tailwind.js` only when the
layout is genuinely custom; for a data dashboard the base CSS is enough.
