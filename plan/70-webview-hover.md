# 70 — Hover nos webviews do Cockpit (macOS e Windows)

## Contexto

Hover nunca funcionou nos webviews do Cockpit (preview de markdown/HTML,
`.panel`, navegador): CSS `:hover` não acende, cursor de link não muda, tooltip
não abre. Clique funciona. Sintoma intermitente ("só na borda", "só bem à
esquerda").

Diagnóstico em 2026-10-19, com plugin instrumentado e um WKWebView puro em
Swift como controle (memória `project_cockpit_webview_hover_desktop_drop`):

- **macOS**: o `DropTarget` do `desktop_drop` 0.5.0 é uma NSView que cobre a
  `FlutterView` inteira. O `hitTest` da janela devolve ela, e o WebKit descarta
  `mouseMoved` quando a view sob o cursor não é o próprio WKWebView. Com o
  `hitTest` devolvendo `nil` fora de um drag (PR MixinNetwork/flutter-plugins#436,
  publicado no `desktop_drop` 0.9.0 em 2026-10-16) o hover voltou. Validado no
  app debug.
- **Windows**: causa diferente, não testada. O `flutter_inappwebview_windows`
  0.6.0 renderiza o WebView2 como textura e reenvia o mouse por method channel:
  só `MOVE`, nunca `LEAVE`, um `invokeMethod` por pixel. A Microsoft documenta
  que em modo composição `CursorChanged` e hover popups exigem `Leave`.
- O engine do Flutter tem um problema vizinho (flutter/flutter#181257: Flutter
  pintando por cima da platform view rouba o hit test), sem fix previsto. Não
  era o caso aqui.

Bloqueio de versão: `desktop_drop` 0.9.x exige Dart SDK >= 3.13.5 (Flutter
3.47.5 traz 3.13.4) e `cross_file ^0.4` (`shadcn_flutter` 0.0.52 pede ^0.3.4;
0.0.54+ não depende mais). O beta 3.50.0 traz Dart 3.14.

Decisões:

| # | Decisão |
|---|---|
| A | Não deixar o hover refém do beta: absorver o `desktop_drop` 0.5.0 com o patch de `hitTest` em `cockpit/plugins/desktop_drop/` (padrão do `cockpit_pty`), **mantendo o nome do pacote** para o registrant gerado não mudar em nenhuma plataforma |
| B | Beta do Flutter numa branch própria, com E2E dos motores nativos antes de trocar o pin do CI |
| C | Windows: fork do `flutter_inappwebview_windows` pinado por **tag**, PR upstream em paralelo |

## Estrutura esperada

```
cockpit/plugins/desktop_drop/      # cópia 0.5.0 + patch macOS + README (origem/motivo/quando remover)
cockpit/pubspec.yaml               # desktop_drop: path: plugins/desktop_drop
.github/workflows/cockpit-release.yml, cockpit-server-release.yml   # FLUTTER_VERSION/channel (passo 2)
```

## Passos

### 1. Absorver o `desktop_drop` (macOS)

1. Copiar `desktop_drop-0.5.0` do pub-cache para `cockpit/plugins/desktop_drop/`, sem `example/`.
2. Patch em `macos/Classes/DesktopDropPlugin.swift` (`DropTarget`): flag `isDragging`; `hitTest` devolve `nil` quando falsa; `draggingEntered` liga; `draggingExited`, `performDragOperation` e `draggingEnded` desligam.
3. `pubspec.yaml`: `desktop_drop: path: plugins/desktop_drop`. Imports não mudam.
4. Registrar no plano 37 e na tabela de motores do `cockpit/CLAUDE.md`.

Aceite: `flutter analyze` limpo, `flutter test` igual à main; no app, `.panel`
com `:hover` segue o mouse; drop do Finder num terminal e na árvore continua
funcionando; CI dos três alvos verde.

### 2. Flutter beta 3.50

1. Beta instalado ao lado do stable (não trocar o SDK global antes do build passar).
2. Branch `chore/flutter-beta-3.50`: `flutter pub get`, `analyze`, `test`, `build macos`.
3. E2E manual dos motores: terminal Ghostty e xterm, preview markdown, `.panel`, DB (anaki), mídia (media_kit), updater.
4. Windows via CI (Impeller desligado lá por causa das texturas do WebView2).
5. Trocar `FLUTTER_VERSION`/`channel` nos dois workflows; release de teste.
6. Com Dart 3.14: `desktop_drop: ^0.9.1` e remover `plugins/desktop_drop` (se o shadcn travar por `cross_file`, bump para 0.0.55).

Aceite: tag de teste com os três alvos verdes e um dia de uso no macOS sem regressão.

### 3. Windows: hover no WebView2

1. Fork de `pichillilorenzo/flutter_inappwebview` (pacote `flutter_inappwebview_windows`), pin por tag em `dependency_overrides`.
2. Dart (`custom_platform_view.dart`): `onExit` no `MouseRegion` chama `_setCursorLeave()`; coalescer `_setCursorPos` por frame.
3. C++ (`in_app_webview.cpp`): `setCursorLeave()` envia `COREWEBVIEW2_MOUSE_EVENT_KIND_LEAVE` com `lastCursorPos_`; registrar no method channel.
4. Corrigir o null deref em `CallJsHandlerCallback::defaultBehaviour` (motivo de o `kPointerRelayScripts` ser macOS-only).
5. PR upstream; manter o fork até a release.

Aceite: numa máquina Windows, `:hover` segue o mouse, cursor vira `pointer` em
link, sair do webview limpa o hover; CPU em idle com o mouse parado não sobe.

## Definition of Done

- [x] Passo 1: `desktop_drop` absorvido com patch, hover funcionando no macOS, CI verde
- [x] Passo 2: Flutter beta 3.50 pinado no CI, release 2.1.18 verde nos 8 jobs
- [ ] Passo 3: fork do `flutter_inappwebview_windows` com `Leave` + coalescência (compila no CI desde 2.1.18; falta validar hover numa máquina Windows)

## Próximos planos

- Quando o stable trouxer Dart >= 3.13.5: remover `plugins/desktop_drop`.
- Quando o upstream do inappwebview publicar o fix: remover o override.
