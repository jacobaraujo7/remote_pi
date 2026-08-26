# 61 — Cockpit: agente controla o navegador embutido (ler/clicar/digitar)

## Contexto

O plano 58 deu ao Cockpit um navegador embutido (`flutter_inappwebview`,
WKWebView no macOS) e `cockpit browse <url>` — mas é **fire-and-forget**: abre
ou naviga a aba e não devolve nada. O agente (`pi --mode rpc`, rodando dentro
de um pane) não tem como ler o conteúdo da página nem interagir com ela —
diferente da extensão Claude para Chrome (`claude-in-chrome`), que expõe
`navigate`/`read_page`/`find`/`computer`/`form_input` porque controla o Chrome
via **Chrome DevTools Protocol** (`chrome.debugger`).

Esse CDP não existe pra nós: WKWebView (macOS, plataforma first do Cockpit)
não expõe um protocolo de automação público a apps terceiros. WebView2
(Windows) é Chromium e teria CDP via `CallDevToolsProtocolMethodAsync`, mas
`flutter_inappwebview` não repassa isso hoje — ficaria dependente de platform
channel próprio, só no Windows. Por isso este plano assume **injeção de JS**
(`evaluateJavascript`) como mecanismo único e multiplataforma (macOS +
Windows), aceitando a limitação conhecida: eventos disparados por
`dispatchEvent` são `isTrusted: false` — funcionam na esmagadora maioria dos
sites, mas não enganam uma checagem explícita de `event.isTrusted`.

### Decisões fechadas nesta conversa (2026-08-26)

| # | Decisão |
|---|---|
| **A** | Mecanismo = injeção de JS via `evaluateJavascript`, não CDP nem `CGEventPost`. `CGEventPost`/`SendInput` (clique OS-level, `isTrusted: true`) descartado nesta fase: precisa permissão de Acessibilidade no macOS e move o cursor real do usuário — intrusivo demais pro ganho |
| **B** | Superfície = **subcomandos novos da CLI interna** (`cockpit browser ...`), no mesmo padrão de `cockpit db`/`cockpit browse`/`cockpit orchestrate`. **Não** é um sistema de plugins/extensões genérico — ver "Fora de escopo" abaixo |
| **C** | `BrowserSession` passa a expor o `InAppWebViewController` da aba (hoje preso no `State` de `browser_pane.dart`), pra o `CockpitCliHandler` alcançar o webview vivo. Sem isso nenhum subcomando novo funciona |
| **D** | `read` devolve só elementos **interativos e visíveis** (link, button, input, textarea, select, `[role=button]`, `[onclick]`, `[tabindex]`) com um id efêmero — não a árvore DOM inteira. Full DOM fica atrás de `--full` (custo de payload) |
| **E** | Ids de elemento são **efêmeros e por-sessão de read**: um `click`/`type` só é válido contra o `read` mais recente daquela aba. `read` de novo invalida os ids antigos (mesmo risco que Claude-in-Chrome tem com página mudando sob o pé) |

## Estrutura esperada

```
cockpit/
├── cli/src/commands.rs             # + subcomandos `browser read|click|type|screenshot|eval`
└── lib/app/cockpit/
    ├── domain/
    │   └── browser_element.dart    # BrowserElement {id, role, text, rect} — contrato do `read`
    ├── data/browser/
    │   └── browser_bridge.js       # script injetado: scan de interativos, click/type/serialize
    └── ui/
        ├── session/
        │   └── browser_session.dart        # + expõe controller vivo (ver decisão C)
        └── viewmodels/
            └── cockpit_cli_handler.dart     # + cases: browser-read, browser-click, browser-type,
                                              #   browser-screenshot, browser-eval
```

## Passos

### 1. Expor o `InAppWebViewController` fora do widget

- `BrowserSession` ganha um campo/callback pro controller (setado em
  `onWebViewCreated` de `browser_pane.dart`, limpo no `dispose`). Sessão já é
  o objeto que o `CockpitCliHandler` resolve por `projectId`/pane — só falta
  o controller nela.
- Guard: se a aba fechou ou nunca abriu, todo subcomando novo devolve erro
  tipado claro (`no browser tab open` / `tab was closed`), nunca crash de
  null.

**Aceite**: fechar a aba de navegador e rodar `cockpit browser read` devolve
erro JSON, não trava o handler nem o processo do agente.

### 2. `cockpit browser read [--pane-id] [--full]`

- Injeta `browser_bridge.js` (idempotente — reinjeta em todo `read`, não
  depende de estado sobrevivendo a navegação) e devolve a lista de elementos
  interativos visíveis: `{id, role, text, rect: {x,y,w,h}}`.
- `role` vem de `role` explícito, senão inferido da tag (`a`→link,
  `button`/`input[type=submit]`→button, `input`/`textarea`→textbox,
  `select`→combobox).
- Elemento fora do viewport ou com `display:none`/`visibility:hidden` não
  entra na lista default (`--full` inclui, pra debug).
- Saída JSON de uma linha, em inglês (CLI não se traduz — regra do
  CLAUDE.md do cockpit).

**Aceite**: `cockpit browser read` numa aba com um formulário simples lista
os campos e o botão de submit com ids estáveis dentro da mesma leitura;
reload da página muda os ids (não há promessa de estabilidade entre reads).

### 3. `cockpit browser click <id>` e `cockpit browser type <id> "<texto>"`

- `click`: resolve o id contra o último mapeamento vivo daquela aba (mantido
  em memória do lado Dart, não recalculado do zero) e dispara
  `el.scrollIntoView()` + `dispatchEvent(new MouseEvent('click', {bubbles:
  true, cancelable: true, view: window}))`.
- `type`: foca o elemento, seta `.value`, dispara `input` e `change`. Para
  `contenteditable`, seta `textContent` e dispara `input`.
- Id desconhecido (leitura velha, elemento sumiu) → erro tipado
  `stale element id`, nunca silêncio.

**Aceite**: `read` → `click` no botão de um formulário de teste local
(`localhost`) e `type` num campo de texto produzem o mesmo efeito que um
clique/digitação humana na página; id de um `read` anterior (página já
navegou) falha com `stale element id`, não com exceção genérica.

### 4. `cockpit browser screenshot [--pane-id] [--out <path>]`

- Usa `InAppWebViewController.takeScreenshot()` (API já existente no
  `flutter_inappwebview`, plano 58 já traz a dependência). Sem `--out`,
  devolve base64 no JSON; com `--out`, grava PNG no path e devolve o path.

**Aceite**: rodar o comando numa aba carregada produz um PNG legível do
estado atual da página (não uma tela em branco/anterior).

### 5. `cockpit browser eval "<js>"` (escape hatch)

- Roda a expressão via `evaluateJavascript` e devolve o resultado
  serializável (string/number/bool/JSON) ou erro se não for serializável /
  lançar exceção JS.
- Documentar como último recurso — `read`/`click`/`type` cobrem o caso comum
  sem o agente precisar escrever seletor CSS na mão.

**Aceite**: `cockpit browser eval "document.title"` devolve o título da
página como string JSON.

### 6. Docs e skill

- Atualizar a skill `cockpit-cli` com os 5 subcomandos novos, exemplos de uso
  encadeado (`read` → pegar id → `click`).
- `docs/rpc-protocol.md` ou doc equivalente da CLI ganha uma seção "Browser
  control" com o contrato JSON de cada subcomando.

**Aceite**: alguém sem contexto prévio consegue, só lendo a skill, fazer um
agente preencher e submeter um formulário de teste numa página local.

## Fora de escopo (não é isto)

- **Sistema de plugins/extensões genérico** (manifest, terceiros carregando
  código, permissões por plugin). O padrão aqui é o mesmo já usado por
  `db`/`browse`/`orchestrate`: subcomando novo na mesma CLI Rust, mesmo
  binário. Só valeria revisitar como plugin system de verdade se aparecer um
  segundo consumidor real com necessidades diferentes do `pi` via shell —
  não é o caso hoje.
- **Clique OS-level (`CGEventPost`/`SendInput`)** — decisão A. Fica anotado
  como upgrade futuro *se* algum site relevante passar a exigir
  `isTrusted: true` (raro).
- **CDP no Windows via WebView2** — daria paridade maior com o
  `claude-in-chrome` (árvore de acessibilidade real, clique trusted) só
  naquela plataforma, mas é plataform channel novo e não resolve o macOS.
  Fica pra depois se o custo/benefício justificar suporte assimétrico.
- **Multi-tab / múltiplas abas de navegador simultâneas sob controle do
  agente** — os subcomandos operam na aba resolvida por `--pane-id` (mesmo
  roteamento de `cockpit db`), uma de cada vez.

## Definition of Done

- [x] `BrowserSession` expõe o `InAppWebViewController` vivo da aba (decisão C)
- [x] `cockpit browser read [--full]` lista elementos interativos visíveis com id/role/text/rect
- [x] `cockpit browser click <id>` dispara clique sintético válido contra o último `read`
- [x] `cockpit browser type <id> "<texto>"` funciona em input/textarea/contenteditable
- [x] `cockpit browser screenshot [--out]` via `takeScreenshot()`
- [x] `cockpit browser eval "<js>"` como escape hatch
- [x] Id de `read` velho falha com erro tipado (`stale element id`), nunca crash
- [x] Aba fechada/inexistente falha com erro tipado, nunca crash
- [x] Skill `cockpit-cli` e doc de protocolo atualizadas com os 5 subcomandos
- [ ] `flutter analyze` limpo + `flutter test` + testes wire da CLI (Rust) —
      **parcial**: `flutter analyze`/`flutter test` rodados e limpos (zero
      issues nos arquivos tocados; falhas pré-existentes em `core/terminal`
      não relacionadas). Os testes Rust (`cli/tests/wire.rs`, 12 casos novos)
      foram **escritos mas não executados** — este ambiente não tem
      `cargo`/`rustc` instalados (nem no PATH nem em `~/.cargo/bin`). Rodar
      `cargo test` no pane Cockpit antes de fechar este item.
- [ ] E2E manual: agente lê um formulário local, clica e digita, e o resultado
      bate com o que um humano faria manualmente

## Próximos planos (fora de escopo aqui)

- Clique OS-level (`CGEventPost`) como upgrade opt-in se `isTrusted` virar bloqueio real
- CDP via WebView2 no Windows, se surgir necessidade de paridade maior
- Revisitar "sistema de plugins genérico" se aparecer um segundo consumidor além do `pi`
