import 'dart:io';

import 'package:cockpit/config/dependencies.dart';
import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:cockpit/routing/router.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  // Preferências carregadas ANTES do primeiro frame → o app já abre no tema
  // salvo (sem flash de tema errado).
  final settings = buildSettingsController();
  await settings.load();
  await _setupWindow();
  runApp(CockpitApp(router: buildRouter(), settings: settings));
}

/// Esconde a barra nativa (temos a customizada). macOS/Windows/Linux.
Future<void> _setupWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    // Esconde os botões nativos do macOS — usamos os nossos desenhados.
    windowButtonVisibility: false,
    minimumSize: Size(720, 480),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class CockpitApp extends StatelessWidget {
  const CockpitApp({super.key, required this.router, required this.settings});

  final GoRouter router;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    // O controller fica ACIMA do MaterialApp → trocar tema/fonte repinta tudo,
    // e a tela de Configurações o consome via Provider.
    return ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: Consumer<SettingsController>(
        builder: (context, controller, _) {
          final s = controller.settings;
          return MaterialApp.router(
            title: 'Cockpit',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(brightness: Brightness.light, settings: s),
            darkTheme: buildTheme(brightness: Brightness.dark, settings: s),
            themeMode: _themeMode(s.themeMode),
            routerConfig: router,
          );
        },
      ),
    );
  }

  ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
