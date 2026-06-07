import 'package:cockpit/config/dependencies.dart';
import 'package:cockpit/routing/routes.dart';
import 'package:cockpit/ui/cockpit/cockpit_page.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/ui/cockpit/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/ui/settings/connectivity_viewmodel.dart';
import 'package:cockpit/ui/settings/daemons_viewmodel.dart';
import 'package:cockpit/ui/settings/settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Topologia de navegação. No MVP há só o shell do Cockpit; o `CockpitViewModel`
/// é provido aqui (o provider é dono do ciclo de vida → `dispose` mata as
/// sessões/processos vivos).
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: RoutePaths.shell,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.shell,
        builder: (context, state) => MultiProvider(
          providers: [
            ChangeNotifierProvider<CockpitViewModel>(
              create: (_) => buildCockpitViewModel()..init(),
            ),
            ChangeNotifierProvider<SetupViewModel>(
              create: (_) => buildSetupViewModel(),
            ),
          ],
          child: const CockpitPage(),
        ),
      ),
      // Tela cheia de Configurações (push) com transição em **fade**. O
      // SettingsController já está provido acima do MaterialApp, então a página
      // o consome direto.
      GoRoute(
        path: RoutePaths.settings,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          // As abas Conectividade e Daemon Agents têm ViewModels próprios;
          // providos aqui, cada um carrega sob demanda quando a aba abre.
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ConnectivityViewModel>(
                create: (_) => buildConnectivityViewModel(),
              ),
              ChangeNotifierProvider<DaemonsViewModel>(
                create: (_) => buildDaemonsViewModel(),
              ),
            ],
            child: const SettingsPage(),
          ),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
        ),
      ),
    ],
  );
}
