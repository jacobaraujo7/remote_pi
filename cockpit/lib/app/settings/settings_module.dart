import 'package:cockpit/app/settings/data/daemon/supervisor_client_impl.dart';
import 'package:cockpit/app/settings/data/relay/relay_gateway_impl.dart';
import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
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
          ..addChangeNotifier<ConnectivityViewModel>(ConnectivityViewModel.new)
          ..addChangeNotifier<DaemonsViewModel>(DaemonsViewModel.new)
          ..addChangeNotifier<CronViewModel>(CronViewModel.new)
          // Resolvem deps do core upward (page-scoped enxerga core):
          // EnvironmentProbe e SystemPermissions.
          ..addChangeNotifier<SettingsEnvGate>(SettingsEnvGate.new)
          ..addChangeNotifier<NotificationsViewModel>(
            NotificationsViewModel.new,
          ),
        child: (context, state) => const SettingsPage(),
      );
  },
);
