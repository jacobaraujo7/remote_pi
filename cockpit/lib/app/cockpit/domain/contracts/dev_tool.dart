// Contratos de integração de ferramentas com tasks. O executor e a UI só
// conhecem estes tipos — qual binário, quais devices e como reescrever o argv
// mora na implementação (hoje, Flutter).

/// O que o comando faz em relação a um dispositivo ou plataforma.
///
/// - [runOnDevice]: executa a aplicação num device escolhível (`flutter run`).
/// - [buildForPlatform]: alvo de plataforma, sem escolha de device (`flutter build apk`).
/// - [other]: comando da ferramenta que não oferece seletor (`flutter test`).
enum DevOperation { runOnDevice, buildForPlatform, other }

/// Plataforma de execução reconhecida por uma ferramenta.
enum DevPlatform { android, ios, macos, linux, windows, web }

/// SO em que o Cockpit está rodando. Entra na prioridade automática.
enum HostOs { macos, windows, linux }

/// Comando que uma [DevTool] reconheceu. Imutável.
class ParsedDevCommand {
  ParsedDevCommand({
    required this.toolId,
    required this.operation,
    required List<String> invocation,
    this.buildPlatform,
    this.explicitDeviceId,
  }) : invocation = List<String>.unmodifiable(invocation);

  /// Id da ferramenta (`flutter`). Igual a [DevTool.id].
  final String toolId;

  final DevOperation operation;

  /// Plataforma implícita num build (`apk` → [DevPlatform.android]). Null
  /// quando o comando não fixa plataforma.
  final DevPlatform? buildPlatform;

  /// Device já presente no argv (`-d` / `--device-id`), se houver.
  final String? explicitDeviceId;

  /// Prefixo usado para invocar a ferramenta, sem o subcomando.
  /// Ex.: `['flutter']`, `['fvm', 'flutter']`, `['fvm', 'spawn', '3.24.0', 'flutter']`.
  final List<String> invocation;
}

/// Device que a ferramenta sabe executar. [id] é o valor passado ao processo.
class DevDevice {
  const DevDevice({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final DevPlatform platform;
}

/// Reconhece o argv de uma task. Devolve null se o comando não é desta ferramenta.
abstract class DevTool {
  String get id;

  ParsedDevCommand? match(String command, List<String> args);
}

/// Ferramenta que executa uma aplicação num device. Quem só identifica comandos
/// implementa [DevTool] e para por aí.
abstract class DeviceRunTool implements DevTool {
  /// Plataformas habilitadas no projeto em [cwd].
  Future<Set<DevPlatform>> platforms(String cwd);

  /// Devices compatíveis com o projeto, na ordem da ferramenta.
  Future<List<DevDevice>> devices(String cwd, ParsedDevCommand command);

  /// Escolha automática. Null se nenhum device compatível está disponível.
  /// Nunca devolve um device cuja plataforma não está em [platforms].
  DevDevice? prefer(
    HostOs host,
    Set<DevPlatform> platforms,
    List<DevDevice> devices,
  );

  /// Argv com exatamente um device [deviceId]. Se o argv já aponta para esse
  /// id, devolve a mesma lista. Caso contrário remove as flags de device e
  /// acrescenta `-d <id>`, preservando o resto.
  List<String> withDevice(List<String> args, String deviceId);
}

/// O que o output de uma execução revelou sobre a sessão da ferramenta.
///
/// [sessionUrl] é o alvo da ação manual (vazio se ainda não dá para abrir).
/// [consumedUrls] são URLs da ferramenta, não do app — o auto-open de preview
/// não pode tratá-las como dev server.
class DevSessionHint {
  const DevSessionHint({this.sessionUrl, this.consumedUrls = const []});

  final String? sessionUrl;
  final List<String> consumedUrls;
}

/// Ação contextual de uma execução, pronta para a linha da task.
///
/// A UI desenha [label] e [icon] e, no clique, abre [url]. Não interpreta o
/// comando.
class TaskRunAction {
  const TaskRunAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.url,
  });

  final String id;
  final String label;

  /// Token de ícone (`devtools`, `refresh`). A linha da task mapeia o token;
  /// um desconhecido cai no fallback de texto.
  final String icon;
  final String url;
}

/// Ferramenta que publica uma ação enquanto a aplicação está em execução.
/// Quem só identifica comandos implementa [DevTool] e para por aí.
abstract class RunSessionTool implements DevTool {
  /// Lê um trecho do output. Null se este comando não tem sessão, ou se o
  /// trecho ainda não traz uma URL utilizável.
  DevSessionHint? inspectOutput(ParsedDevCommand command, String text);

  /// Ação para [sessionUrl], ou null se a operação não oferece uma.
  TaskRunAction? action(ParsedDevCommand command, {required String sessionUrl});
}
