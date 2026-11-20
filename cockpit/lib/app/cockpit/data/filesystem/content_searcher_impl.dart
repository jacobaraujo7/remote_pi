import 'package:cockpit/app/cockpit/domain/services/content_search_paths.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/app/cockpit/domain/contracts/content_searcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';

/// Find-in-files em **Dart puro**, rodando o walk + grep num [Isolate] pra não
/// travar a UI. Emite [FileMatches] incrementalmente (um por arquivo) e aborta o
/// Isolate se a assinatura do stream for cancelada (Cmd+Shift+F → nova query).
class ContentSearcherImpl implements ContentSearcher {
  const ContentSearcherImpl();

  @override
  Stream<FileMatches> search(ContentQuery query) {
    if (query.term.trim().isEmpty) return const Stream<FileMatches>.empty();

    final controller = StreamController<FileMatches>();
    final receive = ReceivePort();
    Isolate? isolate;
    var done = false;

    Future<void> spawn() async {
      try {
        isolate = await Isolate.spawn(
          _searchEntry,
          _SearchArgs(receive.sendPort, query),
          onError: receive.sendPort,
          onExit: receive.sendPort,
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }

    receive.listen((dynamic message) {
      if (controller.isClosed) return;
      if (message is FileMatches) {
        controller.add(message);
      } else if (message is _SearchError) {
        controller.addError(FormatException(message.message));
      } else {
        // `null` (done sentinel) / onExit / onError → encerra.
        done = true;
        receive.close();
        controller.close();
      }
    });

    controller.onCancel = () {
      if (!done) {
        isolate?.kill(priority: Isolate.immediate);
        receive.close();
      }
    };

    unawaited(spawn());
    return controller.stream;
  }
}

/// Argumentos enviados ao Isolate (SendPort + a query, ambos sendable).
class _SearchArgs {
  const _SearchArgs(this.send, this.query);
  final SendPort send;
  final ContentQuery query;
}

/// Sentinela de erro (ex.: regex inválida) enviada de volta pela porta.
class _SearchError {
  const _SearchError(this.message);
  final String message;
}

// ---- corpo que roda no Isolate ---------------------------------------------

/// Limites de segurança (evitam payloads/varreduras gigantes na UI).
const int _maxFilesWithMatches = 2000;
const int _maxTotalMatches = 10000;
const int _maxMatchesPerFile = 200;
const int _maxFileBytes = 2 * 1024 * 1024; // 2 MB — igual ao FileReader
const int _maxLineLength = 1000; // trunca a linha enviada à UI

void _searchEntry(_SearchArgs args) {
  final send = args.send;
  final q = args.query;

  final RegExp pattern;
  try {
    pattern = _buildPattern(q);
  } on FormatException catch (e) {
    send.send(_SearchError(e.message));
    send.send(null);
    return;
  }

  final root = Directory(q.root);
  if (!root.existsSync()) {
    send.send(null);
    return;
  }

  final rootPath = root.path;
  var filesWithMatches = 0;
  var totalMatches = 0;
  final stack = <Directory>[root];

  outer:
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // sem permissão etc.
    }
    for (final entity in entries) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        if (!contentSearchIncludesDirectory(name)) continue;
        stack.add(entity);
      } else if (entity is File) {
        if (name == '.DS_Store') continue; // lixo do Finder (macOS)
        final matches = _scanFile(entity, pattern);
        if (matches == null || matches.isEmpty) continue;
        final rel = entity.path.startsWith('$rootPath${Platform.pathSeparator}')
            ? entity.path.substring(rootPath.length + 1)
            : entity.path;
        send.send(
          FileMatches(
            relativePath: rel.replaceAll(Platform.pathSeparator, '/'),
            matches: matches,
          ),
        );
        filesWithMatches++;
        totalMatches += matches.fold(0, (s, m) => s + m.ranges.length);
        if (filesWithMatches >= _maxFilesWithMatches ||
            totalMatches >= _maxTotalMatches) {
          break outer;
        }
      }
    }
  }

  send.send(null); // done
}

/// Monta a [RegExp] da query. Não-regex é escapado; `wholeWord` envolve em `\b`.
RegExp _buildPattern(ContentQuery q) {
  var source = q.regex ? q.term : RegExp.escape(q.term);
  if (q.wholeWord) source = '\\b(?:$source)\\b';
  return RegExp(source, caseSensitive: q.caseSensitive, multiLine: false);
}

/// Varre um arquivo e devolve as linhas com match, ou `null` se deve pular
/// (binário, grande demais, ilegível).
List<LineMatch>? _scanFile(File file, RegExp pattern) {
  final List<int> bytes;
  try {
    final len = file.lengthSync();
    if (len > _maxFileBytes) return null;
    bytes = file.readAsBytesSync();
  } catch (_) {
    return null;
  }
  // Binário: byte nulo nos primeiros 8 KB.
  final probe = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < probe; i++) {
    if (bytes[i] == 0) return null;
  }

  final String content;
  try {
    content = utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }

  final out = <LineMatch>[];
  final lines = const LineSplitter().convert(content);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final ranges = <MatchRange>[];
    for (final m in pattern.allMatches(line)) {
      // Ignora matches vazios (ex.: regex `a*`) pra não loopar/ poluir.
      if (m.end > m.start) ranges.add(MatchRange(m.start, m.end));
    }
    if (ranges.isEmpty) continue;
    final text = line.length > _maxLineLength
        ? line.substring(0, _maxLineLength)
        : line;
    out.add(LineMatch(lineNumber: i + 1, text: text, ranges: ranges));
    if (out.length >= _maxMatchesPerFile) break;
  }
  return out;
}
