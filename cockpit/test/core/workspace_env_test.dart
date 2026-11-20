import 'dart:io';

import 'package:cockpit/app/core/utils/workspace_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWorkspaceEnv', () {
    test('KEY=VALUE, comentários, vazios e export', () {
      final env = parseWorkspaceEnv(
        '# comentário\n'
        '\n'
        'API_EMAIL = me@x.com\n'
        'export API_TOKEN=abc123\n'
        '  # outro comentário\n',
      );
      expect(env, {'API_EMAIL': 'me@x.com', 'API_TOKEN': 'abc123'});
    });

    test('remove aspas simples/duplas sem interpretar escapes', () {
      final env = parseWorkspaceEnv(
        'A="com espaço"\n'
        "B='x\\ny'\n"
        'C="desbalanceada\n',
      );
      expect(env['A'], 'com espaço');
      expect(env['B'], r'x\ny');
      expect(env['C'], '"desbalanceada');
    });

    test('valor pode conter = e a última chave repetida vence', () {
      final env = parseWorkspaceEnv('URL=a=b\nX=1\nX=2\n');
      expect(env, {'URL': 'a=b', 'X': '2'});
    });

    test('ignora chave inválida e linha sem =', () {
      final env = parseWorkspaceEnv('1BAD=x\n=y\nlinha solta\nOK-NOT=z\nOK=1');
      expect(env, {'OK': '1'});
    });

    test('chaves perigosas nunca entram, mesmo válidas sintaticamente', () {
      final env = parseWorkspaceEnv(
        'PATH=/evil\nLD_PRELOAD=x.so\nDYLD_INSERT_LIBRARIES=y\n'
        'LD_WHATEVER=z\nSHELL=/bin/evil\nAPI_TOKEN=ok\n'
        'COCKPIT_CODEX_LAUNCHER=/evil\nCOCKPIT_ZSH_PROXY_DIR=/evil\n',
      );
      expect(env, {'API_TOKEN': 'ok'});
      expect(isBlockedWorkspaceEnvKey('PATH'), isTrue);
      expect(isBlockedWorkspaceEnvKey('Path'), isFalse);
      expect(isBlockedWorkspaceEnvKey('API_PATH'), isFalse);
    });

    test('CRLF', () {
      expect(parseWorkspaceEnv('A=1\r\nB=2\r\n'), {'A': '1', 'B': '2'});
    });
  });

  group('loadWorkspaceEnvSync', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ws-env-');
    });
    tearDown(() => tmp.delete(recursive: true));

    test('workspaceEnvRootsWithFile lista só as pastas com arquivo', () async {
      final a = await Directory('${tmp.path}/a').create();
      final b = await Directory('${tmp.path}/b').create();
      await File('${a.path}/$kWorkspaceEnvFileName').writeAsString('X=1');
      expect(workspaceEnvRootsWithFile([a.path, b.path, '']), [a.path]);
    });

    test(
      'funde roots na ordem, última vence; pasta sem arquivo é ignorada',
      () async {
        final a = await Directory('${tmp.path}/a').create();
        final b = await Directory('${tmp.path}/b').create();
        final c = await Directory('${tmp.path}/c').create();
        await File(
          '${a.path}/$kWorkspaceEnvFileName',
        ).writeAsString('X=a\nY=a');
        await File('${b.path}/$kWorkspaceEnvFileName').writeAsString('Y=b');
        expect(loadWorkspaceEnvSync([a.path, b.path, c.path, '']), {
          'X': 'a',
          'Y': 'b',
        });
      },
    );
  });

  group('loadWorkspaceEnvRemote', () {
    test(
      'lê cada root pelo leitor, funde na ordem e ignora ausentes',
      () async {
        final asked = <String>[];
        final env = await loadWorkspaceEnvRemote(['/srv/app', '/srv/lib', ''], (
          path,
        ) async {
          asked.add(path);
          return switch (path) {
            '/srv/app/.env.cockpit' => 'X=app\nY=app\nPATH=/evil',
            '/srv/lib/.env.cockpit' => 'Y=lib',
            _ => null,
          };
        });
        expect(asked, ['/srv/app/.env.cockpit', '/srv/lib/.env.cockpit']);
        expect(env, {'X': 'app', 'Y': 'lib'});
      },
    );

    test('caminho Windows remoto usa o separador do host', () async {
      final asked = <String>[];
      await loadWorkspaceEnvRemote([r'C:\proj'], (path) async {
        asked.add(path);
        return null;
      });
      expect(asked, [r'C:\proj\.env.cockpit']);
    });
  });
}
