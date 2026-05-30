import 'dart:convert';

const Set<String> _sensitiveKeys = {
  'ct',
  'token',
  't',
  'sig',
  'signature',
  'auth',
  'secret',
  'sk',
  'privateKey',
  'private_key',
  'prompt',
  'reply',
  'response',
  'text',
  'message',
  'body',
  'payload',
  'qr',
  'uri',
};

Object? redactForLog(Object? value, [String? key]) {
  if (key != null && _sensitiveKeys.contains(key)) return '[redacted]';
  if (value is String) return safeLogString(value);
  if (value is List) return value.map((v) => redactForLog(v)).toList();
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: redactForLog(entry.value, entry.key.toString()),
    };
  }
  return value;
}

String safeLogString(String value) {
  if (value.startsWith('remotepi://')) return '[redacted-uri]';
  if (value.length > 48 && RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(value)) {
    return '${value.substring(0, 8)}…(${value.length} chars)';
  }
  return value;
}

String shortId(String value, {int visible = 8}) {
  if (value.length <= visible) return value;
  return '${value.substring(0, visible)}…';
}

String logTextStats(String value) =>
    'text.chars=${value.length} text.bytes=${utf8.encode(value).length}';
