import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';

/// Conexões do workspace em `.cockpit/databases.json` (versionado) +
/// `.cockpit/databases.local.json` (gitignored, override por nome) + sqlites
/// **detectados** no repo por magic header (`SQLite format 3\0`).
class DbConnectionStoreImpl implements DbConnectionStore {
  const DbConnectionStoreImpl();

  static const _dirName = '.cockpit';
  static const _fileName = 'databases.json';
  static const _localFileName = 'databases.local.json';

  /// Profundidade máxima do scan de sqlites (raiz = 0).
  static const _scanDepth = 3;

  /// Diretórios nunca varridos (build/artefatos; dot-dirs são pulados sempre).
  static const _skipDirs = {'build', 'node_modules', 'Pods', 'target'};

  static const _sqliteExts = {'db', 'sqlite', 'sqlite3', 'db3'};
  static const _sqliteMagic = 'SQLite format 3';

  @override
  Future<List<DbConnection>> load(String workspaceRoot) async {
    final registered = await _readFile(
      File('$workspaceRoot/$_dirName/$_fileName'),
      DbConnectionOrigin.registered,
    );
    final local = await _readFile(
      File('$workspaceRoot/$_dirName/$_localFileName'),
      DbConnectionOrigin.local,
    );

    // Merge por nome: local sobrepõe registrado.
    final byName = <String, DbConnection>{
      for (final c in registered) c.name: c,
      for (final c in local) c.name: c,
    };

    // Detectados: não duplicar path já registrado nem nome já usado.
    final knownPaths = byName.values
        .where((c) => c.engine == DbEngine.sqlite)
        .map((c) => _normalize(workspaceRoot, c.sqlitePath))
        .toSet();
    for (final path in await _detectSqlites(workspaceRoot)) {
      if (knownPaths.contains(_normalize(workspaceRoot, path))) continue;
      final name = path.split(Platform.pathSeparator).last;
      if (byName.containsKey(name)) continue;
      byName[name] = DbConnection.sqlite(
        name,
        path,
        origin: DbConnectionOrigin.detected,
      );
    }
    return byName.values.toList();
  }

  @override
  Future<void> save(
    String workspaceRoot,
    List<DbConnection> connections,
  ) async {
    final registered = connections
        .where((c) => c.origin == DbConnectionOrigin.registered)
        .toList();
    final file = File('$workspaceRoot/$_dirName/$_fileName');
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert({
        'databases': [for (final c in registered) c.toJson()],
      })}\n',
    );
  }

  Future<List<DbConnection>> _readFile(
    File file,
    DbConnectionOrigin origin,
  ) async {
    try {
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      final list = decoded is Map ? decoded['databases'] : decoded;
      if (list is! List) return const [];
      final out = <DbConnection>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          out.add(
            DbConnection.fromJson(Map<String, Object?>.from(e), origin: origin),
          );
        } on FormatException {
          // Entrada inválida (URL de engine desconhecido, edição manual) não
          // pode derrubar as demais conexões do arquivo — pula só ela.
          continue;
        }
      }
      return out;
    } on FormatException {
      // JSON quebrado (edição manual) não pode derrubar o painel — lista
      // vazia; o usuário corrige o arquivo no próprio editor.
      return const [];
    }
  }

  /// Varre o workspace atrás de arquivos sqlite: extensão candidata + magic
  /// header confirmado (evita falso positivo de `.db` genérico).
  Future<List<String>> _detectSqlites(String root) async {
    final found = <String>[];
    Future<void> walk(Directory dir, int depth) async {
      if (depth > _scanDepth) return;
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        return;
      }
      for (final e in entries) {
        final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (e is Directory) {
          if (name.startsWith('.') || _skipDirs.contains(name)) continue;
          await walk(e, depth + 1);
        } else if (e is File) {
          final dot = name.lastIndexOf('.');
          final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
          if (!_sqliteExts.contains(ext)) continue;
          if (await _hasSqliteMagic(e)) {
            // Path relativo à raiz — portável entre máquinas do time.
            final rel = e.path.startsWith('$root/')
                ? e.path.substring(root.length + 1)
                : e.path;
            found.add(rel);
          }
        }
      }
    }

    await walk(Directory(root), 0);
    found.sort();
    return found;
  }

  static Future<bool> _hasSqliteMagic(File f) async {
    try {
      final raf = await f.open();
      try {
        final head = await raf.read(_sqliteMagic.length);
        return String.fromCharCodes(head) == _sqliteMagic;
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return false;
    }
  }

  static String _normalize(String root, String path) =>
      _isAbsolute(path) ? path : '$root/$path';

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}
