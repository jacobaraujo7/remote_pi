import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/ui/document/document_windows.dart';
import 'package:flutter/services.dart';

/// Arquivos abertos **pelo sistema** (Finder: duplo clique, "Abrir com").
/// O lado nativo (macOS `AppDelegate.openFiles`) manda `open` com os
/// caminhos; os que chegaram antes de o Dart estar pronto ficam em buffer lá
/// e são puxados com `pull` ao ligar. Cada caminho vira uma janela de
/// documento. Windows/Linux: não há canal nativo; os caminhos chegam pela
/// linha de comando (`pendingFromArguments`) ou pelo `open-document` que o
/// segundo processo manda ao app vivo (ver `RunningInstance`).
class OpenFilesChannel {
  OpenFilesChannel._();

  static const _channel = MethodChannel('cockpit/open_files');
  static bool _bound = false;

  /// Windows/Linux: caminhos que vieram na linha de comando deste processo
  /// (duplo clique com o app fechado). O `main` deposita aqui quando não havia
  /// instância viva pra encaminhar; abrem junto com o `bind`.
  static List<String> pendingFromArguments = const [];

  static Future<void> bind() async {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return null;
      final paths = (call.arguments as List?)?.cast<String>() ?? const [];
      for (final p in paths) {
        unawaited(DocumentWindows.open(p));
      }
      return null;
    });
    for (final p in pendingFromArguments) {
      unawaited(DocumentWindows.open(p));
    }
    pendingFromArguments = const [];
    // Gancho de diagnóstico (debug): COCKPIT_OPEN_DOCUMENT=<path> abre uma
    // janela de documento no boot sem depender do Finder/LaunchServices.
    {
      final probe = Platform.environment['COCKPIT_OPEN_DOCUMENT'];
      if (probe != null && probe.isNotEmpty) {
        unawaited(DocumentWindows.open(probe));
      }
    }
    try {
      final pending =
          (await _channel.invokeMethod<List<Object?>>(
            'pull',
          ))?.cast<String>() ??
          const <String>[];
      for (final p in pending) {
        unawaited(DocumentWindows.open(p));
      }
    } on MissingPluginException {
      // plataforma sem o canal nativo
    } on PlatformException {
      // idem
    }
  }
}
