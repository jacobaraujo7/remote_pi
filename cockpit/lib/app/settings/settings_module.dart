import 'package:cockpit/app/cockpit/ui/remote/remote_hosts_controller.dart';
import 'package:cockpit/app/settings/data/daemon/supervisor_client_impl.dart';
import 'package:cockpit/app/settings/data/relay/relay_gateway_impl.dart';
import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/neovim_settings_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Feature **Configurações** — `path: '/settings'` (rota empilhada por cima do
/// shell via `pushNamed`; o shell continua na base da pilha). Cobre Conectividade,
/// Daemon Agents e Agendamentos (cron).
///
/// O [SupervisorClientImpl] é **uma instância** sob dois contratos
/// ([DaemonSupervisor] + [CronGateway]) — mesmo control-plane UDS do
/// `pi-supervisord`. Os ViewModels são page-scoped (`provide`): nascem ao abrir a
/// tela e morrem (`dispose`) ao fechar. Pareamento/revoke sobem um `pi --mode rpc`
/// efêmero via `PairingGatewayFactory`/`RevokeGatewayFactory`, registradas no
/// **core** (root-owned — dependem do `PiSpawnConfig`, também do core) e injetadas
/// no `ConnectivityViewModel`.
Module buildSettingsModule() => createModule(
  path: '/settings',
  register: (c) {
    final supervisor = SupervisorClientImpl();
    c
      ..addSingleton<RelayGateway>(RelayGatewayImpl.new)
      ..addInstance<DaemonSupervisor>(supervisor)
      ..addInstance<CronGateway>(supervisor)
      ..route(
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
          ..addChangeNotifier<ConnectivityViewModel>(ConnectivityViewModel.new)
          ..addChangeNotifier<DaemonsViewModel>(DaemonsViewModel.new)
          ..addChangeNotifier<CronViewModel>(CronViewModel.new)
          // Resolvem deps do core upward (page-scoped enxerga core):
          // EnvironmentProbe e SystemPermissions.
          ..addChangeNotifier<SettingsEnvGate>(SettingsEnvGate.new)
          ..addChangeNotifier<NotificationsViewModel>(
            NotificationsViewModel.new,
          )
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
