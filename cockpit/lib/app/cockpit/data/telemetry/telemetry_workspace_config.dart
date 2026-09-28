// `.cockpit/telemetry.json` (plano 66): configuração OPCIONAL e versionável
// do workspace. Só configuração entra no repo; a base fica no cache local.
//
// {
//   "unwrap": ["^api-1\\s*\\| "],          // prefixos extras a remover
//   "ignore": ["DeprecationWarning: punycode"], // eventos descartados na entrada
//   "projectFrames": ["packages/"],         // caminhos relativos tratados como projeto
//   "proxy": { "listen": 3100, "upstream": "http://127.0.0.1:3000" }
// }

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class TelemetryProxyConfig {
  const TelemetryProxyConfig({required this.listen, required this.upstream});
  final int listen;
  final Uri upstream;
}

class TelemetryWorkspaceConfig {
  const TelemetryWorkspaceConfig({
    this.unwrap = const [],
    this.ignore = const [],
    this.projectFrames = const [],
    this.proxy,
  });

  static const empty = TelemetryWorkspaceConfig();

  final List<RegExp> unwrap;
  final List<RegExp> ignore;
  final List<String> projectFrames;
  final TelemetryProxyConfig? proxy;

  static String pathFor(String workspacePath) =>
      p.join(workspacePath, '.cockpit', 'telemetry.json');

  /// Lê o arquivo do workspace; ausente ou inválido = [empty] (nunca lança).
  static TelemetryWorkspaceConfig load(String workspacePath) {
    if (workspacePath.isEmpty) return empty;
    final f = File(pathFor(workspacePath));
    if (!f.existsSync()) return empty;
    try {
      return parse(f.readAsStringSync());
    } on Object {
      return empty;
    }
  }

  static TelemetryWorkspaceConfig parse(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(_stripComments(text));
    } on FormatException {
      return empty;
    }
    if (decoded is! Map) return empty;
    final m = decoded.cast<String, Object?>();
    List<RegExp> regexes(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is String && e.isNotEmpty) _regex(e),
          ].whereType<RegExp>().toList()
        : const [];
    TelemetryProxyConfig? proxy;
    final pm = m['proxy'];
    if (pm is Map) {
      final listen = int.tryParse('${pm['listen'] ?? ''}');
      final up = Uri.tryParse('${pm['upstream'] ?? ''}');
      if (listen != null && listen > 0 && up != null && up.hasScheme) {
        proxy = TelemetryProxyConfig(listen: listen, upstream: up);
      }
    }
    return TelemetryWorkspaceConfig(
      unwrap: regexes(m['unwrap']),
      ignore: regexes(m['ignore']),
      projectFrames: m['projectFrames'] is List
          ? [for (final e in m['projectFrames'] as List) e.toString()]
          : const [],
      proxy: proxy,
    );
  }

  static RegExp? _regex(String s) {
    try {
      return RegExp(s);
    } on FormatException {
      return null;
    }
  }

  /// JSONC leve: `//` fora de string e `/* */`.
  static String _stripComments(String s) => s
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'(?<!["\w:])//[^\n]*'), '');
}
