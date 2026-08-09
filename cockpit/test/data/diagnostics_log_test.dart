import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final log = DiagnosticsLog.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cockpit_diag_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File sessionFile() => File('${dir.path}/session.json');

  group('DiagnosticsLog', () {
    test('primeira execução não acusa crash', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(log.previousCrash, isNull);
    });

    test('grava boot e erro no arquivo do dia', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      log.logError('flutter', StateError('explodiu'), StackTrace.current);
      final content = await log.currentFile!.readAsString();
      expect(content, contains('[boot] Cockpit 1.0.0'));
      expect(content, contains('[flutter]'));
      expect(content, contains('explodiu'));
    });

    test('saída limpa remove o marcador de sessão', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(sessionFile().existsSync(), isTrue);
      log.markCleanExit();
      expect(sessionFile().existsSync(), isFalse);
    });

    test(
      'marcador remanescente é detectado como crash na sessão seguinte',
      () async {
        // Sessão 1 morre sem markCleanExit (SIGPIPE, segfault, kill -9).
        await log.init(appVersion: '1.0.0', baseDir: dir.path);
        expect(sessionFile().existsSync(), isTrue);

        // Sessão 2 encontra o marcador órfão.
        await log.init(appVersion: '1.0.1', baseDir: dir.path);
        expect(log.previousCrash, isNotNull);
        expect(log.previousCrash!.appVersion, '1.0.0');
        expect(log.previousCrash!.pid, pid);
      },
    );

    test('após saída limpa a sessão seguinte não acusa crash', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      log.markCleanExit();
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(log.previousCrash, isNull);
    });

    test(
      'sem saída limpa, TODA sessão seguinte acusa crash — o loop relatado',
      () async {
        // Era o que acontecia no Windows: o X da barra de título chamava
        // `windowManager.close()`, a janela era destruída sem passar pelo Dart,
        // e `markCleanExit` nunca rodava. Dispensar o aviso não ajudava, porque
        // o aviso não é o que limpa o marcador — quem limpa é a saída.
        // Primeira execução: nada anterior para acusar.
        await log.init(appVersion: '1.22.0', baseDir: dir.path);
        expect(log.previousCrash, isNull);

        // Daí em diante, cada boot encontra o marcador do anterior — e como
        // nenhum deles sai limpo, o aviso nunca para de aparecer.
        for (var i = 1; i <= 3; i++) {
          await log.init(appVersion: '1.22.0', baseDir: dir.path);
          expect(
            log.previousCrash,
            isNotNull,
            reason: 'boot $i devia acusar a sessão anterior',
          );
        }

        // Uma única saída limpa quebra o ciclo, e ele não volta sozinho.
        log.markCleanExit();
        await log.init(appVersion: '1.22.0', baseDir: dir.path);
        expect(log.previousCrash, isNull);
      },
    );

    test('sessão de debug é marcada como tal', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      final marcador =
          jsonDecode(await sessionFile().readAsString())
              as Map<String, Object?>;
      // O teste roda em debug; o campo existe para o boot seguinte distinguir
      // "morreu" de "foi parado pela IDE".
      expect(marcador['debug'], isTrue);

      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(log.previousCrash!.debug, isTrue);
    });

    test('marcador antigo sem o campo debug conta como release', () async {
      // Compatibilidade: quem atualizar com um marcador sujo gravado pela
      // versão anterior não pode ter o aviso silenciado por engano.
      await sessionFile().writeAsString(jsonEncode({'pid': 1}));
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(log.previousCrash!.debug, isFalse);
    });

    test('marcador corrompido é tratado como saída limpa', () async {
      await sessionFile().writeAsString('{ não é json');
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(log.previousCrash, isNull);
    });

    test(
      'marcador sem campos ainda produz um DirtySession utilizável',
      () async {
        await sessionFile().writeAsString(jsonEncode({}));
        await log.init(appVersion: '1.0.0', baseDir: dir.path);
        expect(log.previousCrash, isNotNull);
        expect(log.previousCrash!.appVersion, 'desconhecida');
      },
    );

    test('rotate apaga log além da retenção e preserva o recente', () async {
      final velho = File('${dir.path}/cockpit-2020-01-01.log');
      await velho.writeAsString('antigo');
      await velho.setLastModified(
        DateTime.now().subtract(
          Duration(days: DiagnosticsLog.retentionDays + 1),
        ),
      );
      final novo = File('${dir.path}/cockpit-recente.log');
      await novo.writeAsString('recente');

      await log.init(appVersion: '1.0.0', baseDir: dir.path);

      expect(velho.existsSync(), isFalse);
      expect(novo.existsSync(), isTrue);
    });

    test('rotate ignora arquivos que não são log do cockpit', () async {
      final outro = File('${dir.path}/outra-coisa.txt');
      await outro.writeAsString('x');
      await outro.setLastModified(DateTime(2020));
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      expect(outro.existsSync(), isTrue);
    });

    test('tail devolve as últimas linhas', () async {
      await log.init(appVersion: '1.0.0', baseDir: dir.path);
      for (var i = 0; i < 20; i++) {
        log.log('t', 'linha $i');
      }
      final tail = await log.tail(maxLines: 5);
      expect(tail.split('\n').length, 5);
      expect(tail, contains('linha 19'));
      expect(tail, isNot(contains('linha 0 ')));
    });
  });
}
