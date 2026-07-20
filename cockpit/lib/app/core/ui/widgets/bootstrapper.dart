import 'dart:async';
import 'dart:io' show Platform;

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/bootstrap_error_view.dart';
import 'package:cockpit/app/core/ui/widgets/loading_screen.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';
import 'package:cockpit/main.dart'; // for WindowStateKeeper
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

class CockpitBootstrapper extends StatefulWidget {
  const CockpitBootstrapper({super.key});

  @override
  State<CockpitBootstrapper> createState() => _CockpitBootstrapperState();
}

class _CockpitBootstrapperState extends State<CockpitBootstrapper> {
  bool _initialized = false;
  Object? _error;
  dynamic _appModule;
  SettingsController? _settings;
  Box<dynamic>? _winBox;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    try {
      // 1. Fast loading of settings and window state bounds.
      Hive.init(await StorageLocation.hiveDir());
      final settingsBox = await Hive.openBox<dynamic>(
        HiveSettingsStore.boxName,
      );
      final settings = SettingsController(HiveSettingsStore(settingsBox));
      await settings.load();

      final winBox = await Hive.openBox<dynamic>('window_state');

      if (mounted) {
        setState(() {
          _settings = settings;
          _winBox = winBox;
        });
      }

      // 2. Setup the window bounds and show the window immediately.
      // At this point, the widget tree is rendering the default loading screen
      // (either light or dark depending on loaded preferences).
      await _setupWindow(winBox);

      // 3. Perform slow initialization tasks in the background.
      final Future<void> initTask = (() async {
        // Resolve the user's login shell
        await resolveLoginShell();

        // Kill orphaned processes from previous runs
        await PiProcessRegistry.cleanOrphans();
        await LspProcessRegistry.cleanOrphans();

        // Install hooks in settings.json (idempotent, non-fatal)
        unawaited(
          ClaudeHookInstallerImpl().ensureInstalled().then((r) {
            r.fold(
              (_) {},
              (e) => debugPrint('[claude-hook] install falhou: $e'),
            );
          }),
        );

        // Resolve configuration and build Modular AppModule
        final config = await PiSpawnConfig.resolve();
        _appModule = await buildAppModule(config: config);
      })();

      // Enforce a minimum delay of 2 seconds for visual comfort
      await Future.wait([initTask, Future.delayed(const Duration(seconds: 2))]);

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
        });
      }
    }
  }

  /// Esconde a barra nativa e restaura o último tamanho E posição da janela.
  Future<void> _setupWindow(Box<dynamic> winBox) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    await windowManager.ensureInitialized();
    final w = (winBox.get('width') as num?)?.toDouble() ?? 1280;
    final h = (winBox.get('height') as num?)?.toDouble() ?? 720;
    final x = (winBox.get('x') as num?)?.toDouble();
    final y = (winBox.get('y') as num?)?.toDouble();
    final options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      minimumSize: const Size(720, 480),
      size: Size(w, h),
      center: x == null || y == null,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (x != null && y != null) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final s = _settings?.settings ?? const AppSettings();
      return ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness: Brightness.dark, settings: s),
        builder: (context, child) {
          final tokens = buildTokens(brightness: Brightness.dark, settings: s);
          return CockpitTheme(
            colors: tokens.colors,
            typo: tokens.typo,
            syntax: tokens.syntax,
            child: child ?? const SizedBox(),
          );
        },
        home: BootstrapErrorView(
          error: _error!,
          onRetry: () {
            setState(() {
              _error = null;
              _settings = null;
              _winBox = null;
            });
            _initApp();
          },
        ),
      );
    }

    if (!_initialized) {
      final s = _settings?.settings ?? const AppSettings();
      final Brightness brightness;
      if (s.themeMode == AppThemeMode.dark) {
        brightness = Brightness.dark;
      } else if (s.themeMode == AppThemeMode.light) {
        brightness = Brightness.light;
      } else {
        brightness = View.of(context).platformDispatcher.platformBrightness;
      }

      final tokens = buildTokens(brightness: brightness, settings: s);

      final mode = switch (s.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

      return ShadcnApp(
        title: 'Cockpit',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness: Brightness.light, settings: s),
        darkTheme: buildTheme(brightness: Brightness.dark, settings: s),
        themeMode: mode,
        home: const LoadingScreen(),
        builder: (context, child) {
          return CockpitTheme(
            colors: tokens.colors,
            typo: tokens.typo,
            syntax: tokens.syntax,
            child: child ?? const SizedBox(),
          );
        },
      );
    }

    return WindowStateKeeper(
      box: _winBox!,
      child: ModularApp(
        module: _appModule,
        provide: (s) => s
          ..addChangeNotifier<SettingsController>(() => _settings!)
          ..addChangeNotifier<EditorMenuBridge>(EditorMenuBridge.new)
          ..addChangeNotifier<WorkspaceMenuBridge>(WorkspaceMenuBridge.new),
        child: const AppRoot(),
      ),
    );
  }
}
