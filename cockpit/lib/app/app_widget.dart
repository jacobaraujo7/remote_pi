import 'dart:io' show Platform;

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
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
    final app = ShadcnApp.router(
      title: 'Cockpit',
      debugShowCheckedModeBanner: false,
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
          // funciona mesmo sem nada focado.
          bindings: {..._zoomBindings(controller), ..._focusBindings()},
          child: _AppZoom(
            scale: uiScale,
            child: CockpitTheme(
              colors: tokens.colors,
              typo: tokens.typo,
              syntax: tokens.syntax,
              child: child ?? const SizedBox(),
            ),
          ),
        );
      },
    );
    // Menu nativo do sistema (barra superior). O `PlatformMenuBar` só renderiza
    // nativamente no macOS — nas outras plataformas ele apenas repassa o `child`
    // (menu embutido em janela fica pra depois, se necessário). Fica **acima** do
    // `ShadcnApp` porque os itens são serializados pro SO, não desenhados na
    // árvore Flutter; as ações usam pontes globais (`app_intents.dart`) resolvidas
    // pelo `CockpitPage`, `null`-safe enquanto o shell não estiver montado.
    if (!Platform.isMacOS) return app;
    return PlatformMenuBar(menus: _menus(controller), child: app);
  }

  /// Estrutura do menu nativo. Só as duas primeiras (App/Arquivo) têm ações
  /// próprias; o resto reusa itens providos pelo SO (about/quit/hide/janela).
  List<PlatformMenuItem> _menus(SettingsController controller) {
    void zoom(double delta) => controller.setInterfaceSize(
      (controller.settings.interfaceSize + delta).clamp(11.0, 22.0),
    );

    return <PlatformMenuItem>[
      // 1ª entrada = menu do app (macOS rotula com o nome do app).
      PlatformMenu(
        label: 'Cockpit',
        menus: <PlatformMenuItem>[
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformMenuItem(
                label: 'Configurações…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: () => requestOpenSettings?.call(),
              ),
              PlatformMenuItem(
                label: 'Verificar atualizações…',
                onSelected: () => requestCheckForUpdates?.call(),
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hide,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hideOtherApplications,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.showAllApplications,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Arquivo',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Abrir projeto…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
            ),
            onSelected: () => requestOpenProject?.call(),
          ),
        ],
      ),
      // Zoom sem acelerador aqui de propósito: os atalhos ⌘=/⌘-/⌘0 já vivem no
      // `CallbackShortcuts` (funciona em qualquer plataforma). Duplicar o key
      // equivalent no menu dispararia a ação duas vezes no macOS.
      PlatformMenu(
        label: 'Visualizar',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Aumentar tamanho',
            onSelected: () => zoom(1),
          ),
          PlatformMenuItem(
            label: 'Diminuir tamanho',
            onSelected: () => zoom(-1),
          ),
          PlatformMenuItem(
            label: 'Tamanho padrão',
            onSelected: () => controller.setInterfaceSize(14),
          ),
        ],
      ),
      const PlatformMenu(
        label: 'Janela',
        menus: <PlatformMenuItem>[
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
        ],
      ),
    ];
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
