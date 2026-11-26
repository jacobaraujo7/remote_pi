# 72 — Mermaid no preview de markdown

## Contexto

O preview de `.md` do Cockpit (macOS/Windows) é uma webview com o pipeline do
plano 58: markdown-it → DOMPurify → morphdom, assets locais em
`cockpit/assets/md_preview/`, inlined sob nonce numa CSP restritiva
(`web_markdown_preview.dart` → `_composePage`). Hoje blocos ```` ```mermaid ````
aparecem como código cru. "Mermaid no preview" estava listado como próximo
plano no 58.

Escopo: **só Mermaid** (todos os tipos de diagrama que a lib suporta).
KaTeX/matemática fica para plano futuro. Linux (fallback `gpt_markdown`, sem
webview) fica de fora: o bloco segue como código.

## Estrutura esperada

```
cockpit/assets/md_preview/
├── mermaid.min.js        # NOVO — vendorizado (versão fixa, build UMD/IIFE que define window.mermaid)
├── preview.html          # + slot __JS_MERMAID__ (ou injeção lazy, ver passo 2)
├── preview.js            # + fence mermaid, render pós-morphdom, cache por hash, tema, erro
└── preview.css           # + estilos do container/erro do diagrama
cockpit/lib/app/cockpit/ui/widgets/web_markdown_preview.dart  # carrega/injeta o mermaid
```

## Passos

1. **Vendorizar o Mermaid**: baixar `mermaid.min.js` (última estável 11.x, build
   que expõe `window.mermaid` sem ESM/dynamic import — os diagramas lazy-chunked
   não funcionam sem rede, conferir que o bundle é self-contained). Registrar a
   dependência no plano 37 (regra do cockpit).
   *Aceite*: arquivo em `assets/md_preview/`, versão anotada num comentário/README
   do diretório e no plano 37.

2. **Carregamento sem pesar todo `.md`**: o Mermaid é ~3 MB. Não inlinear no
   esqueleto de toda página. Preferir injeção lazy: quando o markdown contém um
   fence `mermaid`, o Dart (ou o JS pedindo ao Dart via handler) injeta o script
   uma vez por página (`evaluateJavascript` do conteúdo, que não passa pela CSP
   de `<script>` do documento — confirmar no WKWebView e no WebView2). Se a
   injeção lazy não funcionar sob a CSP, cair para inline com nonce e medir o
   custo de abertura.
   *Aceite*: abrir `.md` sem mermaid não carrega o script (verificável por
   `typeof window.mermaid === 'undefined'`); com mermaid, renderiza.

3. **Fence → placeholder**: em `preview.js`, sobrescrever a regra `fence` do
   markdown-it para `info === 'mermaid'` gerando
   `<div class="ckp-mermaid" data-src-hash="<hash>"><pre>…código escapado…</pre></div>`
   (o código escapado é o fallback visível enquanto não renderiza / se falhar).
   Adicionar `data-src-hash` ao `ADD_ATTR` do DOMPurify.
   *Aceite*: o placeholder sobrevive ao sanitize.

4. **Render pós-morphdom com cache**: depois do `morphdom`, para cada
   `.ckp-mermaid` não renderizado, `mermaid.render(id, src)` → SVG inserido
   dentro do container. Cache `hash → svg` em memória. No `morphdom`, usar
   `onBeforeElUpdated` para **pular** containers cujo `data-src-hash` não mudou
   (senão cada tecla no editor reverte o SVG para o `<pre>` e o diagrama pisca).
   Render serializado (fila), descartando resultado obsoleto se o conteúdo
   mudou durante o render.
   *Aceite*: editar texto fora do diagrama não re-renderiza nem pisca; editar o
   diagrama atualiza só ele; scroll preservado.

5. **Configuração e segurança**: `mermaid.initialize({ startOnLoad: false,
   securityLevel: 'strict', theme: 'base', themeVariables: … })`. O SVG entra
   depois do DOMPurify (gerado pela lib em modo strict); não passar o SVG pelo
   sanitize do HTML (ele quebra `foreignObject`/estilos).
   *Aceite*: `click`/links JS do mermaid não executam; HTML do markdown continua
   sanitizado como antes.

6. **Tema**: `themeVariables` derivadas das variáveis `--ckp-*` já injetadas
   (fundo, texto, borda, acento, fonte). Em `setTheme`, re-inicializar, limpar o
   cache e re-renderizar os diagramas visíveis.
   *Aceite*: diagrama legível nos temas claro e escuro; trocar tema atualiza sem
   recarregar a página.

7. **Erro de sintaxe**: se `mermaid.render` rejeitar, mostrar caixa discreta de
   erro (mensagem da lib crua, que é texto de terceiro) + o código-fonte, sem
   quebrar o resto do preview e sem deixar o SVG de erro "bomba" do mermaid
   pendurado no `body`. O rótulo da caixa vem traduzido: passar a string do Dart
   (`context.t`) para a página junto com o tema/conteúdo — chave nova nos
   **quatro** `lib/i18n/*.i18n.json` + `dart run slang`.
   *Aceite*: diagrama inválido mostra erro localizado; os demais renderizam.

8. **Visual**: container centralizado, `max-width: 100%`, SVG responsivo,
   overflow horizontal com scroll no container para diagramas largos.
   *Aceite*: `flowchart LR` largo não estoura a largura do pane.

## Verificação

- Documento de teste com flowchart (com `subgraph` e `<br/>`), stateDiagram-v2,
  sequenceDiagram, gantt, erDiagram e um diagrama inválido.
- Caso real: `docs/reference/etl-scs-fluxo-5min.md` (projeto do usuário, print da
  conversa) — flowchart LR com subgraph + stateDiagram-v2.
- Tema claro/escuro, edição ao vivo (Código ↔ Preview e split), scroll.
- `flutter analyze` limpo + `flutter test`.

## DoD

- [x] `mermaid.min.js` vendorizado e registrado no plano 37
- [x] Carregamento lazy (ou inline medido e justificado)
- [x] Fence `mermaid` renderiza SVG no preview (macOS)
- [x] Sem flicker em edição: cache por hash + skip no morphdom
- [x] Tema claro/escuro via `--ckp-*`, troca ao vivo
- [x] Erro de sintaxe localizado (en/pt-BR/es/zh) sem quebrar o preview
- [x] `securityLevel: 'strict'`, sanitize do HTML inalterado
- [ ] `flutter analyze` + `flutter test` verdes (analyze ok; test: 2048 ok, 7 falhas fora do preview — http runner/sockets, golden htop, anexos, telemetria — não investigadas)
- [x] E2E manual no macOS com o documento de teste

> Implementado 2026-11-18 (Mermaid 11.17.2, injeção lazy via `evaluateJavascript`).
> Validado em harness Chromium headless e no app macOS pelo usuário (2026-11-18).

## Próximos planos

- KaTeX (`$…$` / `$$…$$`) no preview
- Syntax highlight nos blocos de código do preview webview
- Exportar diagrama como SVG/PNG (menu de contexto)
