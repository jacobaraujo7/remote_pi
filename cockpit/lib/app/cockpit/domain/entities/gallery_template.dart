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
    baseName: 'panel',
    extension: 'panel',
    iconAsset: 'assets/file_icons/cockpit-panel.svg',
    content:
        '---\n'
        'title: Panel\n'
        'reload: true\n'
        '---\n'
        '<!doctype html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '  <meta charset="utf-8">\n'
        '  <title>Panel</title>\n'
        '  <style>\n'
        '    body { font-family: system-ui, sans-serif; margin: 2rem;\n'
        '           background: var(--ckp-bg); color: var(--ckp-text); }\n'
        '    button { padding: 6px 12px; }\n'
        '    pre { background: var(--ckp-code-bg); padding: 12px; border-radius: 6px; }\n'
        '  </style>\n'
        '</head>\n'
        '<body>\n'
        '  <h1>Panel</h1>\n'
        '  <p>Buttons here run Cockpit CLI commands on this machine:\n'
        '     <code>await cockpit("exec git status")</code>,\n'
        '     <code>await cockpit("db query main \'select 1\'")</code>,\n'
        '     <code>await cockpit("list-tabs --json")</code>.</p>\n'
        '  <button onclick="run()">git status</button>\n'
        '  <pre id="out"></pre>\n'
        '  <script>\n'
        '    async function run() {\n'
        '      const r = await cockpit("exec git status --short");\n'
        '      document.getElementById("out").textContent =\n'
        '        r.ok ? (r.stdout || "(clean)") : r.error;\n'
        '    }\n'
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
  diagram(
    baseName: 'diagram',
    extension: 'md',
    iconAsset: 'assets/file_icons/mermaid.svg',
    content:
        '# Diagram\n'
        '\n'
        'Mermaid fences render as diagrams in the preview. Ask the agent to draw\n'
        'a flow, a sequence, a class model or a Gantt chart here.\n'
        '\n'
        '```mermaid\n'
        'flowchart LR\n'
        '  A[Idea] --> B{Decision}\n'
        '  B -->|yes| C[Build]\n'
        '  B -->|no| D[Park it]\n'
        '```\n',
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
