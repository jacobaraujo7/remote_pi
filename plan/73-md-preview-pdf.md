# 73 — Baixar o preview de markdown como PDF

## Contexto

O preview de `.md` (webview, plano 58) agora renderiza Mermaid (plano 72). O
usuário quer um botão para **baixar o documento renderizado como PDF**, com os
diagramas, no mesmo visual do preview. Branch `feat/md-preview-pdf`, criada a
partir de `feat/md-preview-mermaid` (o PR do Mermaid ainda não foi mergeado;
este PR vai empilhado sobre ele).

Escopo: macOS (alvo principal) e Windows se a API existir no plugin. Linux
(fallback `gpt_markdown`, sem webview) fica sem o botão.

## Estrutura esperada

- Botão "Baixar PDF" na barra inferior do FileViewer de markdown, ao lado do
  toggle **Pré-visualização | Código-fonte** (só aparece quando o preview
  webview está disponível). Ícone + tooltip traduzidos.
- Ação no `WebMarkdownPreview` (ou num controller exposto por ele) que gera o
  PDF a partir da página já renderizada.
- Diálogo nativo de salvar, nome sugerido `<arquivo>.pdf` na pasta do `.md`.

## Passos

1. **Investigar a API de PDF**: `InAppWebViewController.createPdf()`
   (WKWebView `createPDF` no macOS; conferir se o fork Windows
   `flutter_inappwebview_windows` implementa — WebView2 tem `PrintToPdf`).
   Se `createPdf` só gera uma página longa sem quebra (comportamento do
   `WKWebView.createPDF`), avaliar `printCurrentPage`/`NSPrintOperation` com
   `saveToURL` para obter paginação A4 de verdade. Decidir e justificar no
   result file.
   *Aceite*: PDF paginado (A4, margens) com texto selecionável.

2. **CSS de impressão**: `@media print` em `preview.css`: fundo branco e texto
   escuro independentemente do tema do app (ou respeitar o tema — escolher e
   justificar; recomendação: tema claro para impressão), `break-inside: avoid`
   em diagramas Mermaid, blocos de código, tabelas e imagens; sem scrollbars;
   diagrama largo encolhe para caber na largura da página (sem cortar).
   Se o tema muda para impressão, os diagramas Mermaid precisam ser
   re-renderizados com o tema claro antes de gerar o PDF e voltar depois.
   *Aceite*: diagramas inteiros, legíveis e sem cortes no PDF.

3. **Esperar o render**: garantir que a fila de render do Mermaid esvaziou
   (expor uma promise/flag em `window.__cockpit`) antes de gerar o PDF.
   *Aceite*: documento com vários diagramas sai completo no PDF.

4. **Salvar**: diálogo nativo de salvar (usar o que o app já usa para
   salvar arquivo; se não houver, `file_selector` — registrar dependência no
   plano 37). Toast/feedback de sucesso com ação "Abrir" e de erro (erro
   tipado traduzido na UI, conforme as regras de i18n do cockpit).
   *Aceite*: arquivo salvo onde o usuário escolheu; cancelar não faz nada.

5. **i18n**: rótulos, tooltip e mensagens nos quatro `lib/i18n/*.i18n.json` +
   `dart run slang`.

## Verificação

- `cockpit/docs/mermaid-preview-e2e.md` e um `.md` longo com tabelas, código e
  imagens relativas → PDF paginado, diagramas inteiros.
- Tema escuro do app → PDF continua legível.
- `flutter analyze` limpo + `flutter test`.

## DoD

- [x] Botão "Baixar PDF" no preview de markdown (macOS; Windows se suportado)
- [x] PDF paginado A4, texto selecionável, diagramas Mermaid inteiros
- [x] `@media print` legível independente do tema
- [x] Diálogo de salvar + feedback de sucesso/erro traduzido
- [x] i18n nos 4 locales
- [ ] `flutter analyze` + `flutter test` (analyze ok; test: 2322 ok, 11 falhas fora do código tocado — 9 por dylib quickjs não carregar no runner local)
- [x] E2E manual no macOS

> Implementado 2026-11-18: macOS via `printCurrentPage` + `NSPrintOperation`
> (A4, save sem painel), paleta clara forçada no print, Mermaid redesenhado
> numa cópia só de impressão; escrita via tmp + rename atômico. Windows sem
> botão (fork do plugin não expõe PDF). E2E no app ok (2026-11-18).

## Próximos planos

- Windows: expor `Page.printToPDF` (CDP) no fork `flutter_inappwebview_windows`

- Exportar também `.html` standalone
- PDF do preview de `.panel`/HTML
