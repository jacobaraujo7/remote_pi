import 'package:app/config/dependencies.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/i18n/strings.g.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plan 31 — open the v2 SSOT boxes + WIPE the volatile runtime box BEFORE
  // anything subscribes (#3 / Risk 2).
  await LocalBoxes.init();
  await setupDependencies();
  // Plan 59 — i18n. Pin to English for now: only 'en' is wired end-to-end.
  // pt-BR and es translation files live in lib/i18n/ but are not exposed in
  // the UI yet (the selector is hidden until a second locale is supported).
  LocaleSettings.setLocaleSync(AppLocale.en);
  // Eagerly construct the SSOT writer so it's consuming the channel from boot
  // (messages can arrive before the chat screen mounts).
  injector.get<SyncService>();
  runApp(const RemotePiApp());
}

class RemotePiApp extends StatefulWidget {
  const RemotePiApp({super.key});

  @override
  State<RemotePiApp> createState() => _RemotePiAppState();
}

class _RemotePiAppState extends State<RemotePiApp> with WidgetsBindingObserver {
  late final _router = buildRouter(
    injector.get<PairingStorage>(),
    injector.get<ConnectionManager>(),
    injector.get<Preferences>(),
    injector.get<OwnerIdentityBridge>(),
    injector.get<MeshSyncService>(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeDependencies();
    super.dispose();
  }

  /// Plan 24 — keep the mesh poll timer aligned with the app's
  /// foreground lifecycle. Polling runs ONLY while resumed; in
  /// inactive/paused/hidden/detached we cancel so we don't drain the
  /// battery (and we'll resync via `pullOnDemand` on the next resume +
  /// boot path).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final meshSync = injector.get<MeshSyncService>();
    switch (state) {
      case AppLifecycleState.resumed:
        meshSync.startPolling();
        // ignore: unawaited_futures
        meshSync.pullOnDemand();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        meshSync.stopPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(
          value: injector.get<Preferences>(),
        ),
        ChangeNotifierProvider<SessionSelection>.value(
          value: injector.get<SessionSelection>(),
        ),
        // Shell layout state — lets the adaptive shell collapse the split
        // into a single centered pane on zero-state Home (no Pi / empty).
        ChangeNotifierProvider<ShellLayout>.value(
          value: injector.get<ShellLayout>(),
        ),
      ],
      // Theme is reactive: toggling the mode in Settings notifies
      // [Preferences] → this Consumer rebuilds → MaterialApp swaps theme.
      child: Consumer<Preferences>(
        builder: (context, prefs, _) => TranslationProvider(
          child: MaterialApp.router(
            title: 'Remote Pi',
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: prefs.themeMode,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
            // Issue #114 — user-chosen text size. Applied here rather than by
            // scaling `AppTypography`'s base sizes so the many per-widget
            // `copyWith(fontSize: …)` overrides scale too. `TextScaler.linear`
            // REPLACES the platform scaler, which is deliberate: Flutter can't
            // read iOS's per-app Text Size anyway (it only reads the global
            // accessibility setting), so honoring both would compound them.
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: prefs.fontScale.factor,
              maxScaleFactor: prefs.fontScale.factor,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
