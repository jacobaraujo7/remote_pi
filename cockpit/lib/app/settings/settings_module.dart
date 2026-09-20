import 'package:cockpit/app/cockpit/ui/remote/remote_hosts_controller.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/neovim_settings_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Feature **Configurações** — `path: '/settings'` (rota empilhada por cima do
/// shell via `pushNamed`; o shell continua na base da pilha). Os ViewModels são
/// page-scoped (`provide`): nascem ao abrir a tela e morrem (`dispose`) ao
/// fechar.
Module buildSettingsModule() => createModule(
  path: '/settings',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.fade,
      provide: (s) => s
        // Hosts remotos (plano 58): singleton do cockpit_module (já carregado
        // — cockpit é a rota inicial). Observado aqui pela aba "Remote hosts"
        // (a MESMA instância que a rail). Usa addListenable com **dispose
        // no-op**: `addChangeNotifier` daria `vm.dispose()` no pop desta rota
        // e mataria o singleton compartilhado ("used after disposed" ao
        // reabrir Settings ou no próximo rebuild da rail). O dono é o
        // cockpit_module (rota base, nunca sai da pilha).
        ..addListenable<RemoteHostsController>(
          () => inject<RemoteHostsController>(),
          (vm) => vm,
          (_) {},
        )
        // Resolve SystemPermissions do core upward (page-scoped enxerga core).
        ..addChangeNotifier<NotificationsViewModel>(NotificationsViewModel.new)
        ..addChangeNotifier<NeovimSettingsViewModel>(
          NeovimSettingsViewModel.new,
        ),
      child: (context, state) => SettingsPage(
        initialTab: state.arguments is SettingsTab
            ? state.arguments as SettingsTab
            : null,
      ),
    );
  },
);
