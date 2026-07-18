import 'dart:math';

final Random _rng = Random.secure();

/// UUID v4 (RFC 4122) sem dependência externa. Usado como id de workspaces e
/// realms — o id é opaco e estável; o vínculo com o filesystem mora em
/// `Project.path`, nunca no id.
String newUid() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
