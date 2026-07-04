import 'dart:io' show Platform;

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/core/ui/menu/app_menu_bar.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/clamping_scroll_behavior.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Raiz visual do app. Fica **abaixo** do `ModularApp` (que provê o router) e
/// **acima** do `ShadcnApp.router`. Lê o [SettingsController] app-scoped (provido
/// em `ModularApp.provide`, no `main`) via `context.watch` → trocar tema/fonte
/// repinta tudo. O router vem de `ModularApp.routerConfigOf(context)`.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    // "Tamanho da interface" = **zoom do app inteiro** (texto, panes, ícones,
    // app bar, terminal). Baseline 14 = 1.0x. Ver [_AppZoom].
    final uiScale = s.interfaceSize / 14.0;
    // Fonte de verdade dos menus (usada pelo menu nativo do macOS aqui e pela
    // barra desenhada da janela [WindowMenuBar] no Windows/Linux, montada na
    // barra de título do shell). `watch` no bridge do editor → o menu File
    // (Save/Discard/Format) reconstrói e re-habilita conforme a aba focada.
    final editor = context.watch<EditorMenuBridge>();
    final workspace = context.watch<WorkspaceMenuBridge>();
    final menus = buildAppMenus(controller, editor, workspace);
    final app = ShadcnApp.router(
      title: 'Cockpit',
      debugShowCheckedModeBanner: false,
      // Física de scroll CLAMP em todo o app (mata o bounce/overscroll estranho
      // do default BouncingScrollPhysics do shadcn). Ver ClampingScrollBehavior.
      scrollBehavior: const ClampingScrollBehavior(),
      theme: buildTheme(brightness: Brightness.light, settings: s),
      darkTheme: buildTheme(brightness: Brightness.dark, settings: s),
      themeMode: _themeMode(s.themeMode),
      routerConfig: ModularApp.routerConfigOf(context),
      builder: (context, child) {
        // Brightness efetiva (já resolvida pelo ShadcnApp via themeMode): monta os
        // tokens bespoke e os instala via CockpitTheme — alimenta
        // context.colors/typo/syntax em toda a árvore de rotas.
        final tokens = buildTokens(
          brightness: Theme.of(context).brightness,
          settings: s,
        );
        return CallbackShortcuts(
          // Atalhos globais (sempre na cadeia de foco): zoom (⌘=/⌘-/⌘0) e foco do
          // input (⌘L). CallbackShortcuts é aditivo (não quebra copiar/colar) e
          // funciona mesmo sem nada focado. Fora do macOS somamos os aceleradores
          // do menu (⌘,/⌘O etc): lá a barra é desenhada e não dispara teclas
          // sozinha; no macOS a barra nativa já dispara, então não duplicamos.
          bindings: {
            ..._zoomBindings(controller),
            ..._focusBindings(),
            if (!Platform.isMacOS) ...menuShortcuts(menus),
          },
          // macOS: barra de menu **nativa** do SO — o [AppMenuBar] envolve com um
          // `PlatformMenuBar`. Fica **abaixo** do `ShadcnApp` (dentro do builder,
          // com `View`/`MediaQuery` ancestrais): acima dele o `setMenus` do engine
          // não é aplicado. Windows/Linux: no-op aqui — a barra é desenhada na
          // barra de título do shell pelo [WindowMenuBar].
          child: AppMenuBar(
            menus: menus,
            child: _AppZoom(
              scale: uiScale,
              child: CockpitTheme(
                colors: tokens.colors,
                typo: tokens.typo,
                syntax: tokens.syntax,
                child: child ?? const SizedBox(),
              ),
            ),
          ),
        );
      },
    );
    return app;
  }

  ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// ⌘L / Ctrl+L → foca o input do agente focado (via ponte global, resolvida
  /// pelo `CockpitPage`). Fica aqui (não no shell) pra disparar mesmo quando o
  /// foco caiu num espaço vazio.
  Map<ShortcutActivator, VoidCallback> _focusBindings() {
    void focus() => requestFocusActiveComposer?.call();
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true): focus,
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): focus,
    };
  }

  /// Atalhos de zoom (tamanho da interface). `meta` = ⌘ (macOS); `control` = Ctrl
  /// (Windows/Linux). `=`/numpad+ aumenta, `-`/numpad- diminui, `0` reseta. Step
  /// de 1, limitado a 11..22 (igual ao stepper das Configurações).
  Map<ShortcutActivator, VoidCallback> _zoomBindings(
    SettingsController controller,
  ) {
    void by(double delta) {
      final next = (controller.settings.interfaceSize + delta).clamp(
        11.0,
        22.0,
      );
      controller.setInterfaceSize(next);
    }

    void reset() => controller.setInterfaceSize(14);

    return <ShortcutActivator, VoidCallback>{
      for (final mod in const [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.equal,
          meta: mod,
          control: !mod,
        ): () =>
            by(1),
        SingleActivator(
          LogicalKeyboardKey.numpadAdd,
          meta: mod,
          control: !mod,
        ): () =>
            by(1),
        SingleActivator(
          LogicalKeyboardKey.minus,
          meta: mod,
          control: !mod,
        ): () =>
            by(-1),
        SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          meta: mod,
          control: !mod,
        ): () =>
            by(-1),
        SingleActivator(LogicalKeyboardKey.digit0, meta: mod, control: !mod):
            reset,
      },
    };
  }
}

/// Zoom do **app inteiro**: lê o app num espaço lógico reduzido (`size/scale`) e
/// escala de volta com `FittedBox`, então tudo (texto, ícones, panes, app bar)
/// cresce junto — não só o texto. Vetores (texto/ícones) são re-rasterizados pelo
/// Skia (nítidos); bitmaps (imagens) interpolam. `scale == 1` é no-op.
class _AppZoom extends StatelessWidget {
  const _AppZoom({required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1.0).abs() < 0.001) return child;
    final mq = MediaQuery.of(context);
    final scaled = mq.size / scale;
    return MediaQuery(
      // Layout pensa numa tela menor (`size/scale`) → os elementos ocupam mais
      // dela; o `FittedBox` amplia pro tamanho real da janela. Uso FittedBox (e
      // não `Transform.scale` cru) porque ele **reporta o tamanho da janela** — o
      // Transform reportaria o tamanho lógico reduzido e um ancestral cortaria a
      // direita/baixo (Files e composer somindo). Gestos/hit-test são convertidos
      // pro espaço lógico automaticamente.
      data: mq.copyWith(size: scaled),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaled.width,
          height: scaled.height,
          child: child,
        ),
      ),
    );
  }
}
