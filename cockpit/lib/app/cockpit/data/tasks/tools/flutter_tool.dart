import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/preview_url_scan.dart';
import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';
import 'package:cockpit/i18n/strings.g.dart';

/// Roda um executável e devolve o [ProcessResult]. Injetável nos testes.
typedef FlutterCommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Adaptador Flutter/FVM. Única borda que conhece `flutter run`, `flutter devices`
/// e as pastas de plataforma. O restante do Cockpit fala com [DeviceRunTool].
class FlutterTool implements DeviceRunTool, RunSessionTool {
  const FlutterTool({
    this.runProcess,
    this.deviceTimeout = const Duration(seconds: 20),
  });

  final FlutterCommandRunner? runProcess;
  final Duration deviceTimeout;

  @override
  String get id => 'flutter';

  static const _flutterBins = {
    'flutter',
    'flutter.bat',
    'flutter.cmd',
    'flutter.exe',
  };
  static const _fvmBins = {'fvm', 'fvm.bat', 'fvm.cmd', 'fvm.exe'};

  /// Opções globais do `flutter` que consomem o token seguinte.
  static const _valueOptions = {
    '--packages',
    '--local-engine',
    '--local-engine-src-path',
    '--local-engine-host',
    '--local-web-sdk',
  };

  static const _platformDirs = {
    'android': DevPlatform.android,
    'ios': DevPlatform.ios,
    'macos': DevPlatform.macos,
    'linux': DevPlatform.linux,
    'windows': DevPlatform.windows,
    'web': DevPlatform.web,
  };

  @override
  ParsedDevCommand? match(String command, List<String> args) {
    final tokens = [command, ...args];
    if (tokens.isEmpty) return null;

    final invocation = <String>[];
    var i = 0;
    final base = _basename(tokens[0]);
    if (_fvmBins.contains(base)) {
      invocation.add(tokens[0]);
      i = _skipFlags(tokens, 1);
      if (i >= tokens.length) return null;
      if (tokens[i] == 'spawn') {
        invocation.add(tokens[i]);
        i++;
        if (i >= tokens.length || tokens[i].startsWith('-')) return null;
        invocation.add(tokens[i]);
        i++;
      }
      if (i >= tokens.length || !_flutterBins.contains(_basename(tokens[i]))) {
        return null;
      }
      invocation.add(tokens[i]);
      i++;
    } else if (_flutterBins.contains(base)) {
      invocation.add(tokens[0]);
      i = 1;
    } else {
      return null;
    }

    final flutterArgsStart = i;
    while (i < tokens.length) {
      final token = tokens[i];
      if (token == '--') {
        i++;
        break;
      }
      if (token == '-d' || token == '--device-id') {
        i += 2;
        continue;
      }
      if (token.startsWith('--device-id=')) {
        i++;
        continue;
      }
      if (token.startsWith('-')) {
        i += _valueOptions.contains(token) ? 2 : 1;
        continue;
      }
      break;
    }

    final sub = i < tokens.length ? tokens[i] : null;
    final operation = switch (sub) {
      'run' => DevOperation.runOnDevice,
      'build' => DevOperation.buildForPlatform,
      _ => DevOperation.other,
    };
    return ParsedDevCommand(
      toolId: id,
      operation: operation,
      invocation: invocation,
      buildPlatform: sub == 'build' ? _buildPlatform(tokens, i + 1) : null,
      explicitDeviceId: _lastDeviceId(tokens, flutterArgsStart),
    );
  }

  @override
  Future<Set<DevPlatform>> platforms(String cwd) async {
    if (cwd.isEmpty) return const {};
    final found = <DevPlatform>{};
    for (final entry in _platformDirs.entries) {
      if (await Directory(joinPath(cwd, entry.key)).exists()) {
        found.add(entry.value);
      }
    }
    return found;
  }

  @override
  Future<List<DevDevice>> devices(String cwd, ParsedDevCommand command) async {
    final enabled = await platforms(cwd);
    if (enabled.isEmpty || command.invocation.isEmpty) return const [];
    try {
      final result = await _run(command.invocation.first, [
        ...command.invocation.skip(1),
        'devices',
        '--machine',
      ], workingDirectory: cwd).timeout(deviceTimeout);
      if (result.exitCode != 0) return const [];
      final stdout = result.stdout;
      if (stdout is! String) return const [];
      return _parseDevices(stdout, enabled);
    } on Object {
      return const [];
    }
  }

  @override
  DevDevice? prefer(
    HostOs host,
    Set<DevPlatform> platforms,
    List<DevDevice> devices,
  ) {
    DevDevice? firstOf(DevPlatform platform) {
      if (!platforms.contains(platform)) return null;
      for (final device in devices) {
        if (device.platform == platform) return device;
      }
      return null;
    }

    final native = switch (host) {
      HostOs.macos => DevPlatform.macos,
      HostOs.windows => DevPlatform.windows,
      HostOs.linux => DevPlatform.linux,
    };
    final nativeHit = firstOf(native);
    if (nativeHit != null) return nativeHit;

    final mobileOnly =
        platforms.isNotEmpty &&
        platforms.every(
          (platform) =>
              platform == DevPlatform.android || platform == DevPlatform.ios,
        );
    if (host == HostOs.macos && mobileOnly) {
      final ios = firstOf(DevPlatform.ios);
      if (ios != null) return ios;
    }

    for (final device in devices) {
      if (platforms.contains(device.platform)) return device;
    }
    return null;
  }

  /// `The Flutter DevTools debugger and profiler on macOS is available at: …`
  static final _devtoolsUrlPattern = RegExp(
    r'Flutter DevTools[^\n]*?available at:?\s*(https?://\S+)',
  );

  /// `A Dart VM Service on iPhone is available at: http://127.0.0.1:52914/xK3pQ=/`
  static final _vmServiceUrlPattern = RegExp(
    r'(?:Dart VM Service|Observatory)[^\n]*?is available at:?\s*(https?://\S+)',
  );

  @override
  DevSessionHint? inspectOutput(ParsedDevCommand command, String text) {
    if (command.operation != DevOperation.runOnDevice) return null;
    final joined = joinWrappedPreviewLines(text);
    final devtools = _captureUrl(_devtoolsUrlPattern, joined);
    final vmService = _captureUrl(_vmServiceUrlPattern, joined);
    if (devtools == null && vmService == null) return null;
    final chosen = devtools ?? vmService;
    return DevSessionHint(
      sessionUrl: chosen != null && _serviceUriComplete(chosen) ? chosen : null,
      consumedUrls: [?devtools, ?vmService],
    );
  }

  @override
  TaskRunAction? action(
    ParsedDevCommand command, {
    required String sessionUrl,
  }) {
    if (command.operation != DevOperation.runOnDevice) return null;
    final url = _openableSessionUrl(sessionUrl);
    if (url == null) return null;
    return TaskRunAction(
      id: 'devtools',
      label: t.cockpit.tasksPanel.openDevTools,
      icon: 'devtools',
      url: url,
    );
  }

  String? _captureUrl(RegExp pattern, String text) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    return _usableHttpUrl(match.group(1)!);
  }

  /// http(s) com host. Descarta pontuação grudada no fim da linha do Flutter.
  static String? _usableHttpUrl(String raw) {
    var value = raw.trim();
    while (value.isNotEmpty && '.,);'.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return value;
  }

  /// URL pronta para o browser. Recusa um serviço cortado no meio (sem `/ws`
  /// ou sem a barra final) e percent-encode a query `uri`, para o `=` do
  /// token não ser lido como separador.
  static String? _openableSessionUrl(String raw) {
    final usable = _usableHttpUrl(raw);
    if (usable == null || !_serviceUriComplete(usable)) return null;
    return _encodeServiceQuery(usable);
  }

  static bool _serviceUriComplete(String pageUrl) {
    final service = _serviceUriOf(pageUrl);
    if (service == null) return false;
    switch (service.scheme) {
      case 'ws':
      case 'wss':
        return service.path.endsWith('/ws');
      case 'http':
      case 'https':
        return service.path.endsWith('/');
      default:
        return false;
    }
  }

  static Uri? _serviceUriOf(String pageUrl) {
    final at = pageUrl.indexOf('uri=');
    final raw = at < 0 ? pageUrl : pageUrl.substring(at + 4).split('&').first;
    final String decoded;
    try {
      decoded = Uri.decodeFull(raw);
    } on FormatException {
      return null;
    }
    final uri = Uri.tryParse(decoded);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  /// `?uri=ws://…/token=/ws` vira `?uri=ws%3A%2F%2F…%2Ftoken%3D%2Fws`.
  /// O DevTools decodifica quando vê `%3A%2F%2F`. Idempotente.
  static String _encodeServiceQuery(String pageUrl) {
    const marker = 'uri=';
    final at = pageUrl.indexOf(marker);
    if (at < 0) return pageUrl;
    final valueStart = at + marker.length;
    final amp = pageUrl.indexOf('&', valueStart);
    final value = amp < 0
        ? pageUrl.substring(valueStart)
        : pageUrl.substring(valueStart, amp);
    if (value.contains('%3A%2F%2F') || value.contains('%3a%2f%2f')) {
      return pageUrl;
    }
    final encoded = Uri.encodeComponent(value);
    return pageUrl.replaceRange(
      valueStart,
      amp < 0 ? pageUrl.length : amp,
      encoded,
    );
  }

  @override
  List<String> withDevice(List<String> args, String deviceId) {
    final found = _deviceFlags(args);
    if (found.length == 1 && found.single == deviceId) return args;
    final stripped = <String>[];
    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if (token == '-d' || token == '--device-id') {
        i++;
        continue;
      }
      if (token.startsWith('--device-id=')) continue;
      stripped.add(token);
    }
    return [...stripped, '-d', deviceId];
  }

  /// Sem runner injetado, o comando roda no shell de login — o mesmo caminho
  /// das tasks. O processo GUI não herda a PATH em que `flutter`/`fvm` estão.
  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final custom = runProcess;
    if (custom != null) {
      return custom(executable, arguments, workingDirectory: workingDirectory);
    }
    final command = _shellJoin([executable, ...arguments]);
    if (Platform.isWindows) {
      final shell = Platform.environment['ComSpec'] ?? 'cmd.exe';
      return Process.run(
        shell,
        ['/c', command],
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    }
    return Process.run(
      await resolveLoginShell(),
      ['-ilc', command],
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  static String _shellJoin(List<String> parts) =>
      parts.map(_shellQuote).join(' ');

  static String _shellQuote(String value) {
    if (Platform.isWindows) {
      if (value.isNotEmpty && !value.contains(RegExp(r'[\s"]'))) return value;
      return '"${value.replaceAll('"', r'\"')}"';
    }
    if (value.isNotEmpty && !RegExp(r'''[\s"'$`\\]''').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _basename(String command) {
    final normalized = command.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash == -1 ? normalized : normalized.substring(slash + 1);
    return name.toLowerCase();
  }

  static int _skipFlags(List<String> tokens, int start) {
    var i = start;
    while (i < tokens.length && tokens[i].startsWith('-')) {
      i++;
    }
    return i;
  }

  static DevPlatform? _buildPlatform(List<String> tokens, int start) {
    for (var i = start; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '-d' || token == '--device-id') {
        i++;
        continue;
      }
      if (token.startsWith('-')) {
        if (_valueOptions.contains(token)) i++;
        continue;
      }
      return switch (token) {
        'apk' || 'appbundle' || 'aar' => DevPlatform.android,
        'ios' || 'ipa' => DevPlatform.ios,
        'macos' => DevPlatform.macos,
        'linux' => DevPlatform.linux,
        'windows' => DevPlatform.windows,
        'web' => DevPlatform.web,
        _ => null,
      };
    }
    return null;
  }

  /// Último `-d` / `--device-id` a partir de [start]. O Flutter usa o último.
  static String? _lastDeviceId(List<String> tokens, int start) {
    String? id;
    for (var i = start; i < tokens.length; i++) {
      final token = tokens[i];
      if ((token == '-d' || token == '--device-id') && i + 1 < tokens.length) {
        id = tokens[i + 1];
        i++;
      } else if (token.startsWith('--device-id=')) {
        id = token.substring('--device-id='.length);
      }
    }
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static List<String> _deviceFlags(List<String> args) {
    final ids = <String>[];
    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if ((token == '-d' || token == '--device-id') && i + 1 < args.length) {
        ids.add(args[i + 1]);
        i++;
      } else if (token.startsWith('--device-id=')) {
        ids.add(token.substring('--device-id='.length));
      }
    }
    return ids;
  }

  static List<DevDevice> _parseDevices(
    String stdout,
    Set<DevPlatform> enabled,
  ) {
    final start = stdout.indexOf('[');
    final end = stdout.lastIndexOf(']');
    if (start < 0 || end < start) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(stdout.substring(start, end + 1));
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final devices = <DevDevice>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      if (item['isSupported'] == false) continue;
      final platform = _platformOf(item['targetPlatform']);
      if (platform == null || !enabled.contains(platform)) continue;
      final name = item['name'];
      devices.add(
        DevDevice(
          id: id,
          name: name is String && name.isNotEmpty ? name : id,
          platform: platform,
        ),
      );
    }
    return devices;
  }

  static DevPlatform? _platformOf(Object? target) {
    if (target is! String) return null;
    final value = target.toLowerCase();
    if (value.startsWith('android')) return DevPlatform.android;
    if (value == 'ios') return DevPlatform.ios;
    if (value == 'darwin') return DevPlatform.macos;
    if (value.startsWith('linux')) return DevPlatform.linux;
    if (value.startsWith('windows')) return DevPlatform.windows;
    if (value.startsWith('web')) return DevPlatform.web;
    return null;
  }
}
