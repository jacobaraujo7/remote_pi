// Reconhecimento de frames de stack por runtime e a decisão "é do projeto?".
// O primeiro frame do projeto entra no fingerprint e vira o `arquivo:linha`
// que a UI mostra, então errar aqui polui a aba inteira: em dúvida, NÃO é
// do projeto.

import 'package:path/path.dart' as p;

import '../../../domain/entities/telemetry_event.dart';

// Dart/Flutter: `#1      CartService.add (package:app/cart/cart_service.dart:87:22)`
final _dart = RegExp(r'^#\d+\s+(.+?)\s+\((.+?)(?::(\d+))?(?::(\d+))?\)\s*$');
// Dart test runner: `package:app/cart/cart_service.dart 87:22  CartService.add`
final _dartTest = RegExp(
  r'^\s*((?:package:|dart:|file:|/|[A-Za-z]:\\)?\S+\.dart)\s+(\d+)(?::(\d+))?\s+(.+)$',
);
// Node: `    at addItem (/src/orders.ts:42:11)` | `    at /src/x.js:1:2`
final _node = RegExp(
  r'^\s+at\s+(?:(.+?)\s+\()?((?:file://|node:|[A-Za-z]:\\|/|\.{0,2}/)?[^():]+?):(\d+)(?::(\d+))?\)?\s*\{?\s*$',
);
// Python: `  File "app.py", line 12, in main`
final _python = RegExp(r'^\s+File "(.+?)", line (\d+)(?:, in (.+))?$');
// Rust backtrace: `             at ./src/main.rs:12:5` | panic header
final _rust = RegExp(r'^\s+at\s+(\S+\.rs):(\d+)(?::(\d+))?$');
// Go: `        /app/main.go:12 +0x1d`
final _go = RegExp(r'^\s+(\S+\.go):(\d+)(?:\s+\+0x[0-9a-f]+)?$');

/// Interpreta uma linha como frame; `null` se não for.
TelemetryFrame? parseFrame(
  String line, {
  List<String> projectRoots = const [],
  List<String> projectFrames = const [],
}) {
  RegExpMatch? m;
  String? file, fn;
  int? ln, col;
  if ((m = _dart.firstMatch(line)) != null) {
    fn = m!.group(1);
    file = m.group(2);
    ln = _int(m.group(3));
    col = _int(m.group(4));
  } else if ((m = _node.firstMatch(line)) != null) {
    fn = m!.group(1);
    file = m.group(2);
    ln = _int(m.group(3));
    col = _int(m.group(4));
  } else if ((m = _python.firstMatch(line)) != null) {
    file = m!.group(1);
    ln = _int(m.group(2));
    fn = m.group(3);
  } else if ((m = _dartTest.firstMatch(line)) != null) {
    file = m!.group(1);
    ln = _int(m.group(2));
    col = _int(m.group(3));
    fn = m.group(4);
  } else if ((m = _rust.firstMatch(line)) != null) {
    file = m!.group(1);
    ln = _int(m.group(2));
    col = _int(m.group(3));
  } else if ((m = _go.firstMatch(line)) != null) {
    file = m!.group(1);
    ln = _int(m.group(2));
  } else {
    return null;
  }
  if (file == null || file.isEmpty) return null;
  final inProject = isProjectFile(
    file,
    projectRoots: projectRoots,
    projectFrames: projectFrames,
  );
  return TelemetryFrame(
    raw: line.trimRight(),
    file: inProject ? normalizeProjectPath(file, projectRoots) : file,
    line: ln,
    column: col,
    function: fn?.trim(),
    inProject: inProject,
  );
}

/// `true` se a linha parece continuação de stack (frame ou marcador).
bool looksLikeStackLine(String line) =>
    parseFrame(line) != null ||
    line.trim() == '<asynchronous suspension>' ||
    RegExp(r'^\s+\.\.\.\s*\d*\s*(more|frames|elided)').hasMatch(line) ||
    RegExp(r'^\s+at\s+<anonymous>').hasMatch(line);

final _frameworkPkgs = {
  'flutter',
  'flutter_test',
  'flutter_web_plugins',
  'test',
  'test_api',
  'test_core',
  'matcher',
  'stack_trace',
  'async',
  'stream_channel',
  'collection',
  'meta',
  'vector_math',
  'characters',
  'sky_engine',
};

int? _int(String? s) => s == null ? null : int.tryParse(s);

/// Decide se um caminho de frame pertence ao código do workspace.
bool isProjectFile(
  String file, {
  List<String> projectRoots = const [],
  List<String> projectFrames = const [],
}) {
  var f = file;
  if (f.startsWith('file://')) f = Uri.parse(f).toFilePath();
  if (f.startsWith('dart:') || f.startsWith('node:')) return false;
  if (f.contains('node_modules') ||
      f.contains('.pub-cache') ||
      f.contains('/flutter/packages/') ||
      f.contains('site-packages') ||
      f.contains('/.cargo/registry/') ||
      f.contains('/rustlib/') ||
      f.startsWith('/usr/') ||
      f.startsWith('<')) {
    return false;
  }
  if (f.startsWith('package:')) {
    final name = f.substring(8).split('/').first;
    return !_frameworkPkgs.contains(name);
  }
  if (p.isAbsolute(f) || RegExp(r'^[A-Za-z]:\\').hasMatch(f)) {
    if (projectRoots.isEmpty) return false;
    final nf = p.normalize(f);
    return projectRoots.any((r) => p.isWithin(p.normalize(r), nf));
  }
  // Relativo: `lib/x.dart`, `src/db.ts`, `./src/x.js`, `test/a_test.dart`
  final rel = f.startsWith('./') ? f.substring(2) : f;
  if (projectFrames.any(rel.startsWith)) return true;
  return !rel.startsWith('..');
}

/// Caminho curto pra UI/fingerprint: `package:app/x.dart` → `lib/x.dart`,
/// absoluto sob uma root → relativo à root, `./src/x` → `src/x`.
String normalizeProjectPath(String file, List<String> projectRoots) {
  var f = file;
  if (f.startsWith('file://')) f = Uri.parse(f).toFilePath();
  if (f.startsWith('package:')) {
    final rest = f.substring(8);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : 'lib/${rest.substring(slash + 1)}';
  }
  if (p.isAbsolute(f)) {
    final nf = p.normalize(f);
    for (final r in projectRoots) {
      final nr = p.normalize(r);
      if (p.isWithin(nr, nf)) return p.relative(nf, from: nr);
    }
    return f;
  }
  return f.startsWith('./') ? f.substring(2) : f;
}
