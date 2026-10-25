import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Configuração global dos testes (`flutter test` carrega este arquivo antes
/// de cada arquivo de teste).
///
/// Ignora a mensagem de sistema `fontsChange` durante os testes. Ela é
/// emitida pelo engine quando uma fonte termina de carregar (`google_fonts`
/// carrega Space Grotesk/Hanken/JetBrains Mono de forma assíncrona ao primeiro
/// uso) e faz o framework agendar um frame callback de relayout em todo
/// RenderObject vivo. No Flutter 3.50 essa mensagem pousa DEPOIS de o primeiro
/// teste do arquivo descartar a árvore, e o harness falha com "An animation is
/// still running even after the widget tree was disposed" (1 falha por
/// arquivo, 27 arquivos). No 3.47 a mesma mensagem chegava e era tolerada.
/// Relayout por troca de fonte não tem valor em widget test: o texto é medido
/// com a fonte de teste de qualquer jeito.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SystemChannels.system.setMessageHandler((Object? message) async {
    if (message is Map && message['type'] == 'fontsChange') return null;
    return PaintingBinding.instance.handleSystemMessage(message!);
  });
  await testMain();
}
