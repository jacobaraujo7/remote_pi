# 67 — Cockpit `.panel`: HTML sob demanda com ponte para a CLI

## Contexto

Queremos um playground: um agente (ou o usuário) escreve um arquivo HTML no
workspace, o Cockpit abre como aba viva, e botões dessa página executam
coisas na máquina. Sem TCP: a página fala com o app pela ponte in-process da
webview e o app despacha para a mesma CLI interna que os agentes já usam.

Decisões fechadas em conversa (2026-09-25), com base na pesquisa registrada na
memória `project_cockpit_panel_html_research`:

| # | Decisão |
|---|---|
| A | Arquivo **único** `nome.panel` = front-matter YAML entre `---` + HTML puro. Nada de pasta, nada de `.htmlx` |
| B | API do JS é **uma função**: `await cockpit("<linha da CLI>")`. A string é a mesma que se digitaria no terminal (`db query main 'select 1'`, `exec git status`). Sem manifesto, sem allowlist: ambiente local e controlado |
| C | Verbo novo **`cockpit exec <cmd...>`** (cwd = pasta do `.panel` por default, timeout, retorna `{ok, stdout, stderr, code}`) |
| D | MCP Apps **não** entra. Ponte própria, mínima |
| E | Paridade com a CLI: o handler **spawna o binário `cockpit`** com a string (cerca de 3 ms) em vez de reimplementar o parser do crate Rust em Dart. O que funciona no terminal funciona no botão |
| F | Tema: o app injeta as CSS variables `--ckp-*` no `:root` (e re-injeta na troca), o autor usa se quiser |
| G | `.html` continua preview com JS desligado; só `.panel` é runtime |
| H | Linux segue best-effort (webview do plugin é beta): degrada para "abrir no navegador do SO", sem ponte |

Reuso obrigatório: `web_markdown_preview.dart` (scheme `ckp-res`, CSP por nonce,
`UnzoomedNativeView`, push de tema), `flutter_inappwebview` já no pubspec,
`markdown_frontmatter.dart` (parser de front-matter), chokepoint de tipos em
`file_viewer_session.dart`/`pane_view.dart`, `gallery_panel.dart`,
`file_icon.dart`, `cli/text/skill.md`.

Fato verificado no plugin (macOS 1.1.2): o handler de scheme customizado
descarta o body do request e responde sem status/streaming. Por isso toda
chamada vai por `addJavaScriptHandler`, e o scheme serve só leitura de assets
relativos. Nenhum `addJavaScriptHandler` existe hoje em `lib/`.

## Formato do arquivo

```html
---
title: Status do repo        # título da aba (default: nome do arquivo)
reload: true                 # recarrega quando o arquivo muda em disco (default true)
cwd: .                       # cwd do exec, relativo ao .panel (default: pasta do arquivo)
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

Contrato de `cockpit(line)`: devolve Promise com o JSON que a CLI devolve para
aquele verbo (`db query` → linhas; `exec` → `{ok, stdout, stderr, code}`; erro
de parse → `{ok:false, error}`). Nunca rejeita a Promise por erro de negócio;
rejeita só se a ponte cair. `cockpit.on("theme", fn)` opcional para reagir à
troca de tema.

## Estrutura esperada

```
cockpit/
├── lib/app/cockpit/
│   ├── domain/entities/panel_document.dart      # front-matter tipado + html
│   ├── domain/services/panel_frontmatter_parser.dart
│   ├── ui/session/panel_session.dart            # PaneItem novo (path, revision, estado)
│   └── ui/widgets/panel_view.dart               # InAppWebView + ponte + tema
├── assets/panel/bridge.js                       # define window.cockpit (injetado no document start)
├── assets/file_icons/cockpit-panel.svg
├── cli/src/commands.rs                          # verbo exec
├── cli/text/skill.md                            # seção .panel
└── lib/i18n/*.i18n.json                         # gallery.panel.{title,description}, erros
```

## Passos

1. **Verbo `exec` na CLI e no handler.** `cockpit exec [--cwd d] [--timeout s] -- cmd args...` → JSON `{ok, stdout, stderr, code}`; no app, `case 'exec'` em `cockpit_cli_handler.dart` roda via `Process.run` com shell do perfil default.
   Aceite: `cockpit exec -- git status --short` num terminal do Cockpit imprime JSON em 1 linha; timeout devolve `ok:false`.

2. **Parser de front-matter + entidade.** Reusar `markdown_frontmatter.dart` (ou extrair o split para o core); campos `title`, `reload`, `cwd`; sem front-matter = defaults.
   Aceite: teste unitário com os três casos (completo, parcial, ausente) e com `---` dentro do HTML não sendo confundido.

3. **Tipo `.panel` no chokepoint.** `file_viewer_session`/`pane_view` abrem `PanelSession`; ícone `cockpit-panel.svg` registrado em `file_icon.dart` (`'panel': 'cockpit-panel'`); watcher de arquivo dispara `revision++` quando `reload: true`.
   Aceite: duplo clique em `x.panel` na árvore abre aba com título do front-matter; editar o arquivo recarrega.

4. **`panel_view.dart` com ponte.** `InAppWebView` com `initialData` = HTML pós-front-matter, `baseUrl` no scheme `ckp-panel://<sessionId>/` cuja raiz é a pasta do arquivo (copiar `_serveLocal`, trocando a raiz), `javaScriptEnabled: true`, `isInspectable` configurável, `UserScript` em `AT_DOCUMENT_START` com `bridge.js`, `addJavaScriptHandler('cockpit')` que spawna o binário `cockpit` em `~/.cockpit/bin` com env `COCKPIT_PANE_ID` e cwd do front-matter, e devolve o stdout parseado. Links http abrem no SO (igual ao preview).
   Aceite: o exemplo do formato acima funciona; `await cockpit("list-panes --json")` devolve o mesmo JSON do terminal; `img src="a.png"` relativo carrega.

5. **Tema.** Injetar `--ckp-*` no `:root` no `onLoadStop` e em `didChangeDependencies` (copiar `_pushTheme`); emitir `cockpit.on("theme")`.
   Aceite: trocar tema em Settings recolore um painel aberto sem reload.

6. **Galeria.** `GalleryTemplate.panel` com template = o exemplo do formato acima; strings em `gallery.panel.*` nos três i18n.
   Aceite: "New file" → card Panel cria `Untitled-1.panel` e abre como aba.

7. **Skill e docs.** Seção `.panel` em `cli/text/skill.md` (formato, contrato de `cockpit()`, `exec`, tema) e espelhar em `~/.claude/skills/cockpit-cli/SKILL.md`; nota em `cockpit/CLAUDE.md` (tabela de motores: "Panel").
   Aceite: `cockpit install-skill` publica a seção; um agente com a skill gera um `.panel` válido de primeira.

8. **Telemetria e Linux.** Cada chamada da ponte vira evento na base de Telemetria (plano 66) com o `.panel` e a linha executada; no Linux o tipo abre via `url_launcher` com aviso "bridge unavailable".
   Aceite: aba Telemetry mostra as chamadas; Linux não crasha.

9. **E2E macOS + Windows.** Painel de exemplo com `db query`, `exec` e `write` em outra aba; verificar foco/teclado (Cmd+W fecha a aba mesmo com a webview focada) e zoom.
   Aceite: checklist manual passa nos dois SOs.

## Definition of Done

- [x] `cockpit exec` na CLI e no handler, com timeout e JSON de saída
- [x] Front-matter parseado, `.panel` abre como aba com ícone próprio e reload por watcher
- [x] `window.cockpit(line)` devolve o JSON da CLI com paridade total
- [x] Assets relativos via scheme com raiz na pasta do arquivo
- [x] Tema injetado e reativo
- [x] Card na Galeria com template, i18n en/pt-BR/es
- [x] Skill (`cli/text/skill.md` + `~/.claude/skills/cockpit-cli`) e CLAUDE.md atualizados
- [ ] Chamadas logadas na Telemetria (ADIADO: a ingest é por run de processo; logar por clique poluiria a lista); Linux degrada sem crash (feito no widget, não testado)
- [x] `flutter analyze` limpo, testes de parser
- [ ] E2E manual macOS e Windows

## Estado (2026-09-25)

Implementado no pane Cockpit em sessão solo (sem commit). Pendente: E2E no app (abrir `.panel` da Galeria, clicar, trocar tema, editar o arquivo e ver recarregar), Windows, e decidir a telemetria.

## Riscos

- Foco/atalhos engolidos pelo `NSView` (composição híbrida): mitigar com `keydown` não tratado encaminhado ao host pelo mesmo handler.
- Spawn por clique (Node/Python no `exec`) custa até ~30 ms; aceitável para dashboard.
- Secure context: em scheme customizado não há `crypto.subtle`/clipboard; se aparecer necessidade, usar host `localhost` no scheme.

## Próximos planos

- Backend próprio por painel (CGI / socket Unix) se um dia o `exec` não bastar.
- Painel em remoto (plano 58): handler encaminha a linha ao `cockpit-server`.

## Adendo 2026-09-27 — libs embarcadas em `/__cockpit__/`

Decisão em conversa: nada de microframework próprio nem CDN. O app embarca
libs em `assets/panel/lib/` e o `_serveLocal` responde o prefixo reservado
`/__cockpit__/<nome>` a partir do `rootBundle` (mesma URL em macOS/Windows/
Linux, mesma versão em todo workspace, zero rede, nada copiado pro repo do
usuário). O prefixo com underscores duplos torna colisão com pasta real do
usuário praticamente impossível; se houver, a regra do app ganha.

| Arquivo | Lib | Por quê |
|---|---|---|
| `cockpit.css` | nosso, classless + utilities sobre `--ckp-*` | dashboard nasce com cara do app e segue o tema |
| `petite-vue.js` | petite-vue 0.4.1 (IIFE) | sintaxe Vue, 17 KB, sem build; é o que LLM escreve com mais acerto em arquivo único |
| `chart.js` | Chart.js 4.4.7 (UMD) | gráficos de dashboard |
| `marked.js` | marked 15.0.7 | markdown de notas/resultados |
| `tailwind.js` | @tailwindcss/browser 4.1.7 | opcional, JIT em runtime (~250 KB); pra layout custom |

Descartados: React (JSX exige build; sem JSX vira `h()` ilegível), Vue
completo (60 KB pra ganhar SFC que não existe em arquivo único), Alpine
(equivalente ao petite-vue, mas a sintaxe Vue é mais conhecida).

Bridge ganhou `cockpit.route` (hash routing: `path`, `params`, `go`, `match`,
evento `route`) e o tema exporta mais variáveis (`--ckp-bg-raised`,
`--ckp-text-secondary`, `--ckp-border-strong`, `--ckp-accent-soft`,
`--ckp-accent-text`, `--ckp-ok`, `--ckp-warn`, `--ckp-error`). Navegar entre
dois `.panel` continua fora: o front-matter só é lido no `initialData`.

- [x] `_serveBundled` no `panel_view.dart` + `assets/panel/lib/` no pubspec
- [x] `cockpit.css` + `cockpit.route` no `bridge.js`
- [x] Skill (`cli/text/skill.md`) documenta a tabela e um dashboard mínimo
- [ ] E2E: abrir `.panel` com petite-vue + chart offline e trocar tema
