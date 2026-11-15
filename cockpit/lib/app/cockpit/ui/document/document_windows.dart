import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Abre arquivos em **janelas de documento** próprias (plano 2.0): uma
/// janela leve, sem rail nem panes, que renderiza o viewer certo pro caminho
/// (markdown, `.kanban`, `.notebook`, código…). É o que substitui o "destacar
/// aba": a aba fica onde está, abre uma cópia solta — sem confundir com o
/// drag de abas entre panes.
///
/// Cada janela tem um engine Flutter próprio. No Windows, o Canvas Board
/// abre em outro processo para sobreviver ao fechamento do Cockpit de origem.
/// O `main` detecta os argumentos e inicia apenas o editor do documento.
/// O estado compartilhado é só o caminho; edição concorrente é resolvida pelo
/// próprio arquivo (o viewer relê quando ele muda no disco).
class DocumentWindows {
  DocumentWindows._();

  // The Windows runner already reserves the multi_window prefix from CLI
  // forwarding. Pass the path as its own argv entry, including spaces.
  static const _boardProcess = 'standalone-board';

  static bool isStandaloneBoard(List<String> args) =>
      args.length == 3 && args[0] == 'multi_window' && args[1] == _boardProcess;

  /// Argumento que o engine da janela recebe (`main(args)` →
  /// `['multi_window', <id>, <este JSON>]`).
  static String argumentsFor(String path) =>
      jsonEncode({'type': 'document', 'path': path});

  /// `path` do JSON de argumentos, ou `null` se não é uma janela de documento.
  static String? pathFromArguments(List<String> args) {
    if (args.length < 3 || args[0] != 'multi_window') return null;
    if (isStandaloneBoard(args)) {
      return args[2].toLowerCase().endsWith('.board') ? args[2] : null;
    }
    try {
      final json = jsonDecode(args[2]);
      if (json is Map && json['type'] == 'document') {
        final path = json['path'];
        if (path is String && path.isNotEmpty) return path;
      }
    } on FormatException {
      // argumento de outro tipo de janela (ou vazio) → não é documento
    }
    return null;
  }

  /// Abre (e mostra) uma janela de documento para [path].
  static Future<void> open(String path) async {
    if (Platform.isWindows && path.toLowerCase().endsWith('.board')) {
      // Give the canvas its own engine and Win32 message loop. Shutting down
      // a sibling engine must not destroy the canvas window or its renderer.
      await Process.start(Platform.resolvedExecutable, [
        'multi_window',
        _boardProcess,
        File(path).absolute.path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    final controller = await WindowController.create(
      WindowConfiguration(arguments: argumentsFor(path)),
    );
    await controller.show();
  }
}

/// Canal com o lado nativo da **própria** janela de documento (registrado no
/// `setOnWindowCreatedCallback` do macOS): título e tamanho. Best-effort —
/// plataforma sem o canal só fica sem título.
class DocumentWindowChannel {
  DocumentWindowChannel._();

  static const _channel = MethodChannel('cockpit/document_window');

  /// Título + tamanho inicial + traz pra frente (ver DocumentWindows.swift).
  static Future<void> present(
    String title, {
    bool standaloneBoard = false,
    double width = 960,
    double height = 720,
  }) async {
    if (standaloneBoard) {
      await windowManager.ensureInitialized();
      await windowManager.setTitle(title);
      await windowManager.setSize(Size(width, height));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    try {
      await _channel.invokeMethod<void>('present', {
        'title': title,
        'width': width,
        'height': height,
      });
    } on MissingPluginException {
      // Windows/Linux ainda sem o handler nativo: sem título, sem erro.
    } on PlatformException {
      // idem
    }
  }
}
