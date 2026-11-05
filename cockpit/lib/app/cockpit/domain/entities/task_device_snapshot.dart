import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';

/// O que a linha da task precisa para desenhar o seletor, sem conhecer a ferramenta.
class TaskDeviceSnapshot {
  const TaskDeviceSnapshot({
    required this.offered,
    required this.loading,
    required this.unavailable,
    required this.canStart,
    required this.devices,
    this.selectedId,
    this.selectedName,
  });

  /// Task que não executa em device: a linha não mostra o ícone e o start segue
  /// o caminho genérico.
  static const hidden = TaskDeviceSnapshot(
    offered: false,
    loading: false,
    unavailable: false,
    canStart: true,
    devices: [],
  );

  /// `true` quando o comando suporta escolha de device.
  final bool offered;

  /// Ainda não há uma listagem. O play segue habilitado: o start espera a lista.
  final bool loading;

  /// Há um id escolhido (manual ou explícito no comando) que não está na lista.
  final bool unavailable;

  /// `false` quando já sabemos que não dá para executar num device compatível.
  final bool canStart;

  final List<DevDevice> devices;

  /// Id efetivo: preferência manual, senão `-d` do comando, senão prioridade.
  final String? selectedId;

  /// Nome amigável quando o id está na lista atual. Fora dela, null.
  final String? selectedName;
}

/// Como o start deve chamar o runner.
class TaskLaunchPlan {
  const TaskLaunchPlan({required this.blocked, this.argsOverride});

  /// Task genérica, ou workspace remoto: o runner resolve o argv sozinho.
  static const plain = TaskLaunchPlan(blocked: false);

  /// Execução em device sem um device compatível disponível. Não iniciar.
  static const blockedRun = TaskLaunchPlan(blocked: true);

  final bool blocked;

  /// Argv completo (profile já aplicado). Null mantém a resolução do runner.
  final List<String>? argsOverride;
}
