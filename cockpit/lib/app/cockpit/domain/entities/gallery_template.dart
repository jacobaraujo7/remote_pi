/// Um "documento especial" do Cockpit que a aba Gallery sabe criar na raiz do
/// workspace: extensão própria + conteúdo inicial que já abre na tab certa
/// (`.dbq` → editor SQL, `.kanban` → quadro, `.ckp` → layout, `.http` →
/// cliente HTTP, `.html` → preview renderizado, `.cockpit/tasks.json` → aba
/// Tasks, `.env.cockpit` → variáveis injetadas nos terminais do workspace).
/// Título/descrição são i18n na UI; aqui só o que é dado.
enum GalleryTemplate {
  dbQuery(
    baseName: 'query',
    extension: 'dbq',
    iconAsset: 'assets/file_icons/database.svg',
    content: '-- limit: 100\nSELECT 1;\n',
  ),
  kanban(
    baseName: 'board',
    extension: 'kanban',
    iconAsset: 'assets/file_icons/todo.svg',
    content:
        '---\n'
        'columns: [Backlog, Doing, Done]\n'
        'labels: {bug: red, feature: blue}\n'
        '---\n'
        '\n'
        '## Backlog\n'
        '\n'
        '- [ ] First card <!-- id: k1 labels: feature -->\n'
        '\n'
        '## Doing\n'
        '\n'
        '## Done\n',
  ),
  notebook(
    baseName: 'welcome',
    extension: 'md',
    relativeDir: 'notes.notebook',
    fixedName: true,
    opensParent: true,
    iconAsset: 'assets/file_icons/cockpit-notebook.svg',
    content:
        '---\n'
        'title: Welcome\n'
        'tags: [agent]\n'
        'created: 2026-01-01T00:00\n'
        'updated: 2026-01-01T00:00\n'
        '---\n'
        '\n'
        'This folder is a **notebook**: one markdown file per note, each with a\n'
        '`tags:` list in its frontmatter. Agents write notes here while they work;\n'
        'you read, tag and edit them. Obsidian opens the same folder as-is.\n',
  ),
  html(
    baseName: 'view',
    extension: 'html',
    iconAsset: 'assets/file_icons/html.svg',
    content:
        '<!doctype html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '  <meta charset="utf-8">\n'
        '  <title>View</title>\n'
        '  <style>\n'
        '    body { font-family: system-ui, sans-serif; margin: 2rem; }\n'
        '  </style>\n'
        '</head>\n'
        '<body>\n'
        '  <h1>Hello from Cockpit</h1>\n'
        '  <p>Ask the agent to draw anything here — a mind map, a diagram, a chart.</p>\n'
        '</body>\n'
        '</html>\n',
  ),
  panel(
    baseName: 'dashboard',
    extension: 'panel',
    iconAsset: 'assets/file_icons/cockpit-panel.svg',
    // Espelho de cli/skills/cockpit-design/templates/dashboard.panel (plano 69):
    // o teste gallery_panel_template_sync_test garante que os dois sao iguais.
    content:
        '---\n'
        'title: Dashboard\n'
        'reload: true\n'
        'cwd: .\n'
        '---\n'
        '<!doctype html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '  <meta charset="utf-8">\n'
        '  <title>Dashboard</title>\n'
        '  <link rel="stylesheet" href="/__cockpit__/cockpit.css">\n'
        '  <script src="/__cockpit__/petite-vue.js"></script>\n'
        '  <script src="/__cockpit__/chart.js"></script>\n'
        '</head>\n'
        '<body>\n'
        '  <div class="page" v-scope="App()" @vue:mounted="load" v-cloak>\n'
        '    <!-- 1. toolbar: title · status · actions -->\n'
        '    <div class="toolbar">\n'
        '      <h1>Repository</h1>\n'
        '      <span class="status">{{ status }}</span>\n'
        '      <button @click="load" :disabled="loading">Refresh</button>\n'
        '    </div>\n'
        '\n'
        '    <!-- 2. numbers as stats -->\n'
        '    <div class="kpis">\n'
        '      <div class="card stat"><span class="value">{{ changed.length }}</span><span class="label">changed files</span></div>\n'
        '      <div class="card stat"><span class="value">{{ commits.length }}</span><span class="label">recent commits</span></div>\n'
        '      <div class="card stat"><span class="value">{{ branch || \'—\' }}</span><span class="label">branch</span></div>\n'
        '    </div>\n'
        '\n'
        '    <!-- 3. body grid: chart + table -->\n'
        '    <div class="grid-2">\n'
        '      <div class="card">\n'
        '        <h3>Changes by kind</h3>\n'
        '        <canvas id="chart" height="180"></canvas>\n'
        '      </div>\n'
        '      <div class="card">\n'
        '        <h3>Recent commits</h3>\n'
        '        <div v-if="loading" class="col"><div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div></div>\n'
        '        <p v-else-if="!commits.length" class="empty">No commits yet.</p>\n'
        '        <table v-else>\n'
        '          <tr v-for="c in commits" :key="c.sha"><td><code>{{ c.sha }}</code></td><td class="truncate">{{ c.msg }}</td></tr>\n'
        '        </table>\n'
        '      </div>\n'
        '    </div>\n'
        '\n'
        '    <!-- 4. errors at the bottom, never inline -->\n'
        '    <pre v-if="error" class="error">{{ error }}</pre>\n'
        '  </div>\n'
        '\n'
        '  <script>\n'
        '    function App() {\n'
        '      let chart = null;\n'
        '      return {\n'
        '        loading: false, status: \'\', error: \'\', branch: \'\', changed: [], commits: [],\n'
        '\n'
        '        async load() {\n'
        '          if (!this._themed) { this._themed = true; cockpit.on(\'theme\', () => this.draw()); }\n'
        '          this.loading = true; this.status = \'loading…\'; this.error = \'\';\n'
        '          // Every call checks r.ok and surfaces r.error.\n'
        '          const st = await cockpit(\'exec git status --porcelain\');\n'
        '          if (!st.ok) { this.fail(st.error); return; }\n'
        '          this.changed = st.stdout.split(\'\\n\').filter(Boolean);\n'
        '          const br = await cockpit(\'exec git branch --show-current\');\n'
        '          this.branch = br.ok ? br.stdout.trim() : \'\';\n'
        '          const lg = await cockpit(\'exec git log --oneline -15\');\n'
        '          this.commits = lg.ok\n'
        '            ? lg.stdout.split(\'\\n\').filter(Boolean).map(l => ({ sha: l.slice(0, 7), msg: l.slice(8) }))\n'
        '            : [];\n'
        '          this.loading = false;\n'
        '          this.status = \'updated \' + new Date().toLocaleTimeString();\n'
        '          this.draw();\n'
        '        },\n'
        '\n'
        '        fail(message) { this.loading = false; this.status = \'\'; this.error = message; },\n'
        '\n'
        '        // Chart colors come from the theme; redraw when it changes.\n'
        '        async draw() {\n'
        '          await new Promise(requestAnimationFrame);\n'
        '          const el = document.getElementById(\'chart\');\n'
        '          if (!el) return;\n'
        '          const kinds = {};\n'
        '          for (const l of this.changed) { const k = l.slice(0, 2).trim() || \'?\'; kinds[k] = (kinds[k] || 0) + 1; }\n'
        '          if (chart) chart.destroy();\n'
        '          chart = new Chart(el, {\n'
        '            type: \'bar\',\n'
        '            data: { labels: Object.keys(kinds), datasets: [{ data: Object.values(kinds), backgroundColor: cockpit.theme[\'--ckp-accent\'] }] },\n'
        '            options: { plugins: { legend: { display: false } },\n'
        '              scales: { x: { ticks: { color: cockpit.theme[\'--ckp-text-muted\'] }, grid: { display: false } },\n'
        '                        y: { ticks: { color: cockpit.theme[\'--ckp-text-muted\'], precision: 0 }, grid: { color: cockpit.theme[\'--ckp-border\'] } } } },\n'
        '          });\n'
        '        },\n'
        '      };\n'
        '    }\n'
        '    PetiteVue.createApp().mount();\n'
        '  </script>\n'
        '</body>\n'
        '</html>\n',
  ),
  httpRequest(
    baseName: 'requests',
    extension: 'http',
    iconAsset: 'assets/file_icons/http.svg',
    content:
        '### Ping\n'
        'GET https://httpbin.org/get\n'
        'Accept: application/json\n',
  ),
  tasks(
    baseName: 'tasks',
    extension: 'json',
    relativeDir: '.cockpit',
    fixedName: true,
    iconAsset: 'assets/file_icons/console.svg',
    content: _tasksExample,
  ),
  layout(
    baseName: 'dev',
    extension: 'ckp',
    iconAsset: 'assets/branding/cockpit_logo.png',
    content:
        '# Pane layout — apply with right-click → Open layout,\n'
        '# or `cockpit orchestrate dev.ckp` from a tab.\n'
        '# autorun: worktree   # apply automatically on new worktrees\n'
        'panes:\n'
        '  - name: Shell\n'
        '    cwd: .\n'
        '  - name: Agent\n'
        '    cwd: .\n'
        '    split: right\n'
        '    command: claude\n',
  ),
  workspaceEnv(
    baseName: '',
    extension: 'env.cockpit',
    fixedName: true,
    iconAsset: 'assets/branding/cockpit_logo.png',
    content:
        '# Environment for every terminal Cockpit opens in this workspace.\n'
        '# One KEY=VALUE per line. No interpolation, no multiline.\n'
        '# New tabs pick up changes; running shells keep the old values.\n'
        '# Kept out of git via .git/info/exclude when created from Cockpit.\n'
        '\n'
        '# API_EMAIL=me@example.com\n'
        '# API_TOKEN=\n',
  );

  const GalleryTemplate({
    required this.baseName,
    required this.extension,
    required this.iconAsset,
    required this.content,
    this.relativeDir = '',
    this.fixedName = false,
    this.opensParent = false,
  });

  /// `true` = o documento é a **pasta** (`relativeDir`), não o arquivo: após
  /// criar, abre a tab da pasta (caderno `.notebook`).
  final bool opensParent;

  /// Subpasta (relativa à raiz) onde o arquivo mora; vazio = raiz. A pasta é
  /// criada quando falta.
  final String relativeDir;

  /// `true` = o nome é contrato do app (ex.: `.cockpit/tasks.json` é o único
  /// que a aba Tasks lê): se já existe, **abre** o existente em vez de criar
  /// um `-2`.
  final bool fixedName;

  /// Nome sugerido sem extensão (`dev` → `dev.ckp`, `dev-2.ckp` se já existe).
  final String baseName;
  final String extension;

  /// Asset colorido do card (SVG do tema de ícones ou o logo do Cockpit).
  final String iconAsset;

  /// Conteúdo inicial do arquivo.
  final String content;

  /// `.env.cockpit` tem `baseName` vazio: o nome é só o "ponto + extensão".
  String get fileName =>
      baseName.isEmpty ? '.$extension' : '$baseName.$extension';

  /// Caminho relativo à raiz, com a subpasta quando houver
  /// (`.cockpit/tasks.json`).
  String get relativePath =>
      relativeDir.isEmpty ? fileName : '$relativeDir/$fileName';

  /// Primeiro nome livre dado o conjunto de [taken] (basenames da raiz,
  /// comparados sem case): `dev.ckp`, `dev-2.ckp`, `dev-3.ckp`…
  String uniqueFileName(Iterable<String> taken) {
    final lower = taken.map((n) => n.toLowerCase()).toSet();
    if (!lower.contains(fileName.toLowerCase())) return fileName;
    for (var i = 2; ; i++) {
      final candidate = '$baseName-$i.$extension';
      if (!lower.contains(candidate.toLowerCase())) return candidate;
    }
  }
}

/// Modelo de `.cockpit/tasks.json` gerado pelo botão "Create tasks.json":
/// um exemplo de Flutter (watch + hot reload), Node e C#. O usuário edita os
/// `cwd`/comandos pro projeto dele. Ver `docs/tasks-json.md`.
const String _tasksExample = '''
{
  // .cockpit/tasks.json — Cockpit Task Run config (JSONC: // , /* */ and
  // trailing commas are allowed; they're stripped before parsing).
  // Lives at the workspace root you open in Cockpit. Detected tasks (npm
  // scripts, pubspec) appear automatically; this file adds/overrides them.
  // Full reference: cockpit/docs/tasks-json.md
  "tasks": [
    {
      "label": "Flutter Example", // shown in the Tasks list
      "cwd": "app", // run dir, relative to this file (monorepo-friendly)
      "command": "flutter", // base executable
      "args": ["run"], // base args, before the profile
      "kind": "watch", // "watch" = long-running (dev server); else "oneShot"
      // Optional: only show this task on some OSes — "macos" | "windows" |
      // "linux", as a string or array. Omitted -> visible everywhere.
      // "platforms": ["macos", "linux"],
      // Interactive keys -> buttons that write a key to the process stdin.
      // primary=true shows a fixed button; the rest go under a key menu.
      // icon: bolt | refresh | restart | stop (omit -> a chip with the key).
      "interactiveKeys": [
        { "key": "r", "label": "Hot reload", "icon": "bolt", "primary": true },
        { "key": "R", "label": "Hot restart", "icon": "restart", "primary": true },
        { "key": "p", "label": "Toggle debug paint" },
        { "key": "o", "label": "Toggle platform" }
      ],
      // Reload-on-save: `flutter run` doesn't reload on save by itself (that's
      // an IDE plugin) — Cockpit watches the files and fires `onChange`.
      "watch": {
        "paths": ["lib", "assets"], // dirs to watch (relative to cwd)
        "ignore": ["build", ".dart_tool"], // skip these (avoid loops)
        "onChange": "Hot reload", // an interactiveKey label, or "__restart__"
        "debounceMs": 300 // wait after a change before firing
      },
      // Drive the building/running badge by matching the output.
      "progressPatterns": [
        { "begin": "Performing hot reload", "end": "Reloaded .* in .*ms" },
        { "begin": "Performing hot restart", "end": "Restarted application in .*ms" }
      ],
      // Named arg/env variants, picked by the chip before Run (flavor /
      // dart-define just become args here — no stack-specific keys).
      "profiles": [
        { "name": "web", "args": ["-d", "chrome"] },
        { "name": "macos", "args": ["-d", "macos"] }
      ]
    },
    {
      // No "kind" -> defaults to "oneShot".
      "label": "Node Example",
      "cwd": "site",
      "command": "npm",
      "args": ["run", "dev"]
      // Browser auto-open. "preview": true (default) opens the first local URL
      // found in the output; false turns it off; a string opens that fixed URL
      // right at start.
      // "preview": "http://localhost:3000",
      // When it opens: "always" (default: start and restart), "start" (only on
      // start — Restart and the file watcher won't reopen it) or "never".
      // "previewOpen": "start",
    },
    {
      "label": "C# Example",
      "cwd": "api",
      "command": "dotnet",
      "args": ["watch", "run"],
      "kind": "watch"
    }
  ]
}
''';
