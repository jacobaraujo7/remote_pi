import 'dart:async';
import 'dart:convert';

enum AgentRoleSuggestionFailure { changed, timeout, invalid }

class AgentRoleSuggestionChannel {
  const AgentRoleSuggestionChannel({
    required this.path,
    required this.send,
    required this.read,
    required this.dispose,
  });
  final String path;
  final Future<void> Function(String prompt) send;
  final Future<String?> Function() read;
  final Future<void> Function() dispose;
}

/// Only a request-correlated JSON reply becomes a draft. Never saves a role.
class AgentRoleSuggestionService {
  final Map<String, Future<String>> _pending = {};
  Future<String> request({
    required String key,
    required String requestId,
    required String language,
    required bool Function() isCurrent,
    required Future<AgentRoleSuggestionChannel> Function() prepare,
    Duration interval = const Duration(seconds: 2),
    int attempts = 90,
  }) => _pending.putIfAbsent(
    key,
    () =>
        _request(
          requestId: requestId,
          language: language,
          isCurrent: isCurrent,
          prepare: prepare,
          interval: interval,
          attempts: attempts,
        ).whenComplete(() {
          _pending.remove(key);
        }),
  );

  Future<String> _request({
    required String requestId,
    required String language,
    required bool Function() isCurrent,
    required Future<AgentRoleSuggestionChannel> Function() prepare,
    required Duration interval,
    required int attempts,
  }) async {
    if (!isCurrent()) throw AgentRoleSuggestionFailure.changed;
    final channel = await prepare();
    try {
      if (!isCurrent()) throw AgentRoleSuggestionFailure.changed;
      await channel.send(
        'Cockpit role suggestion request. Describe your current function in this terminal in one short sentence, in $language. '
        'Use your current session context; if the task is unclear, suggest a general role. '
        'Write a JSON object with requestId ${jsonEncode(requestId)} and role (your suggested sentence) to ${jsonEncode(channel.path)}. '
        'This is a metadata question only. Do not change project files, the orchestration document, or start other tasks. '
        'The user will review your suggestion before saving.',
      );
      for (var i = 0; i < attempts; i++) {
        if (!isCurrent()) throw AgentRoleSuggestionFailure.changed;
        final text = await channel.read().timeout(const Duration(seconds: 15));
        if (!isCurrent()) throw AgentRoleSuggestionFailure.changed;
        final role = parseReply(text, requestId);
        if (role != null) return role;
        await Future<void>.delayed(interval);
      }
      throw AgentRoleSuggestionFailure.timeout;
    } finally {
      try {
        await channel.dispose().timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Temporary-file cleanup is best effort. */
      }
    }
  }

  static String? parseReply(String? text, String requestId) {
    if (text == null || text.isEmpty) return null;
    if (text.length > 4096) throw AgentRoleSuggestionFailure.invalid;
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (value is! Map || value['requestId'] != requestId) return null;
    final role = value['role'];
    if (role is! String ||
        role.trim().isEmpty ||
        role.length > 1000 ||
        role.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
      throw AgentRoleSuggestionFailure.invalid;
    }
    return role.trim();
  }
}
