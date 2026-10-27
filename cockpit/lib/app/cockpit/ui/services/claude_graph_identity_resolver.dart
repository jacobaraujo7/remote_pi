import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Recovers a Claude session's own address from its ListAgents result.
/// Message text and the other agents in that result are never returned.
class ClaudeGraphIdentityResolver {
  const ClaudeGraphIdentityResolver();

  Future<Set<String>> readAliases(String path) async {
    return Isolate.run(() => _readAliases(path));
  }

  static Future<Set<String>> _readAliases(String path) async {
    final aliases = <String>{};
    final uses = <String>{};
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > 32 * 1024 * 1024) {
        return aliases;
      }
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.contains('ListAgents') && !line.contains('tool_result'))
          continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(line);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        final message = decoded['message'];
        if (message is! Map) continue;
        final content = message['content'];
        if (content is! List) continue;
        for (final part in content) {
          if (part is! Map) continue;
          if (part['type'] == 'tool_use' && part['name'] == 'ListAgents') {
            final id = part['id'];
            if (id is String) uses.add(id);
          } else if (part['type'] == 'tool_result' &&
              uses.contains(part['tool_use_id'])) {
            final value = part['content'];
            final text = value is String ? value : jsonEncode(value);
            final match = RegExp(
              r'This session is ([A-Za-z0-9_-]{1,128})',
            ).firstMatch(text);
            if (match != null) aliases.add(match.group(1)!.toLowerCase());
          }
        }
      }
    } on FileSystemException {
      return aliases;
    }
    return aliases;
  }

  /// Restored tabs persist the Claude session ID, while the transcript path
  /// arrives later via hooks. Locate that exact session file when needed.
  Future<Map<String, String>> findTranscripts(
    String home,
    Set<String> sessionIds,
  ) async {
    final found = <String, String>{};
    if (sessionIds.isEmpty) return found;
    final root = Directory(
      '$home${Platform.pathSeparator}.claude${Platform.pathSeparator}projects',
    );
    if (!await root.exists()) return found;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        final name = entity.uri.pathSegments.last;
        final sid = name.substring(0, name.length - '.jsonl'.length);
        if (sessionIds.contains(sid)) {
          found[sid] = entity.path;
          if (found.length == sessionIds.length) break;
        }
      }
    } on FileSystemException {
      return found;
    }
    return found;
  }
}
