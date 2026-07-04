import 'package:flutter/foundation.dart';

/// Pontes globais entre o shell (page-scoped) e handlers que vivem acima da
/// rota — atalhos de teclado (`main`/`AppRoot`, sempre na cadeia de foco) e o
/// menu nativo (`PlatformMenuBar`, fora da árvore de rotas). Cada ponte é `null`
/// enquanto o `CockpitPage` não estiver montado; os menus/atalhos checam antes
/// de disparar. O `CockpitPage` registra os handlers no `initState` e limpa no
/// `dispose`.

/// ⌘L/Ctrl+L → foca o input do agente focado.
VoidCallback? requestFocusActiveComposer;

/// Menu **Cockpit → Configurações…** (⌘,) → empilha a rota `/settings`. Vive
/// numa ponte porque o `flutter_modular` v7 navega só via `context.pushNamed`, e
/// o menu nativo roda fora da árvore de rotas (sem `BuildContext`).
VoidCallback? requestOpenSettings;

/// Menu **Arquivo → Abrir projeto…** → abre o seletor de pasta e adiciona o
/// projeto (mesmo fluxo do botão "+" do rail).
VoidCallback? requestOpenProject;

/// Menu **Cockpit → Verificar atualizações…** → dispara um check imediato do
/// self-updater (Sparkle/WinSparkle) e, se já houver download pronto, instala.
VoidCallback? requestCheckForUpdates;
