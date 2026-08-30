import 'dart:io';

/// Log de diagnóstico do motor SSH.
///
/// O motor é compartilhado pelo app (Flutter) e pelo `cockpit-server` (Dart
/// puro), então não pode usar `debugPrint`. Vai pro stderr: no servidor é o
/// log de arranque, no app é o console do `flutter run`.
void sshLog(String message) {
  try {
    stderr.writeln('[ssh] $message');
  } on Object {
    // Log nunca derruba quem chamou.
  }
}
