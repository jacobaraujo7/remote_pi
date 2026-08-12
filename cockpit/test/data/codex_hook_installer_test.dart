import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/codex_hook_installer_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Instalador com o passo de materialização da CLI curto-circuitado: os testes
/// exercitam a escrita da config (que é o que tem regra), não a cópia de
/// binário — que depende do bundle do app.
class _FakeInstaller extends CodexHookInstallerImpl {
  const _FakeInstaller(this.command);

  final String command;

  @override
  Future<String?> ensureCli() async => '/fake/cockpit';

  @override
  Future<String?> resolveHookCommand(String? cliPath) async => command;
}

void main() {
  late Directory home;
  late Directory codex;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('codex-hook-test');
    codex = await Directory('${home.path}/.codex').create();
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  Map<String, dynamic> readHooks() =>
      jsonDecode(File('${codex.path}/hooks.json').readAsStringSync())
          as Map<String, dynamic>;

  String readConfig() {
    final f = File('${codex.path}/config.toml');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  group('trustHash', () {
    // Goldens capturados de uma sessão real: com estes valores no config.toml,
    // o `codex exec` executou os hooks SEM `--dangerously-bypass-hook-trust`.
    // Se o Codex mudar o algoritmo, é aqui que a gente descobre.
    const command =
        '/private/tmp/claude-501/-Users-jacob-Projects-remote-pi-cockpit'
        '/5221e354-8d12-4aa7-9ca6-66fb9a82d33c/scratchpad/capture/hook.sh';
    const installer = CodexHookInstallerImpl();

    test('bate com o hash que o Codex aceitou (evento comum)', () {
      expect(
        installer.trustHash(
          eventLabel: 'session_start',
          command: command,
          timeoutSec: 600,
        ),
        'sha256:11036127f25c0aa2c919cb29255297b0e1538b56a5fad8d7430384d0bcbed64b',
      );
      expect(
        installer.trustHash(
          eventLabel: 'user_prompt_submit',
          command: command,
          timeoutSec: 600,
        ),
        'sha256:465349ad203a361f4adaa351793b72f15625e8e8c3926ccf1be8e0196d53efc2',
      );
    });

    test('SessionEnd usa o timeout próprio (1s), não o default', () {
      // O Codex normaliza o timeout do SessionEnd antes de hashear; usar 600
      // aqui geraria um hash que ele nunca reconheceria.
      expect(
        installer.trustHash(
          eventLabel: 'session_end',
          command: command,
          timeoutSec: 1,
        ),
        'sha256:5fad7d95feb545474ffd528129743203608a8b9f993a4f97f392e20e8438c8a1',
      );
      expect(
        installer.trustHash(
          eventLabel: 'session_end',
          command: command,
          timeoutSec: 600,
        ),
        isNot(
          'sha256:5fad7d95feb545474ffd528129743203608a8b9f993a4f97f392e20e8438c8a1',
        ),
      );
    });
  });

  group('writeConfig', () {
    test('instala os sete eventos com trust correspondente', () async {
      const installer = _FakeInstaller('/bin/cockpit hook');
      await installer.writeConfig(
        home: home.path,
        command: '/bin/cockpit hook',
      );

      final hooks = readHooks()['hooks'] as Map<String, dynamic>;
      expect(hooks.keys, hasLength(7));
      expect(hooks.keys, contains('PermissionRequest'));
      // Subagente e compactação ficam de fora de propósito.
      expect(hooks.keys, isNot(contains('SubagentStart')));
      expect(hooks.keys, isNot(contains('PreCompact')));

      final config = readConfig();
      for (final label in const [
        'user_prompt_submit',
        'pre_tool_use',
        'post_tool_use',
        'permission_request',
        'stop',
        'session_start',
        'session_end',
      ]) {
        expect(
          config,
          contains('[hooks.state."${codex.path}/hooks.json:$label:0:0"]'),
        );
      }
      expect('trusted_hash'.allMatches(config).length, 7);
    });

    test('marca o comando com --harness codex', () async {
      // É o que permite ao app retomar a aba com `codex resume <id>`: o
      // session-id sozinho não diz de que harness veio.
      const installer = _FakeInstaller('/bin/cockpit hook');
      await installer.writeConfig(
        home: home.path,
        command: '/bin/cockpit hook',
      );

      final stop = ((readHooks()['hooks'] as Map)['Stop'] as List).first as Map;
      final handler = (stop['hooks'] as List).first as Map;
      expect(handler['command'], '/bin/cockpit hook --harness codex');
    });

    test('re-rodar não duplica entries nem blocos de trust', () async {
      const installer = _FakeInstaller('/bin/cockpit hook');
      for (var i = 0; i < 3; i++) {
        await installer.writeConfig(
          home: home.path,
          command: '/bin/cockpit hook',
        );
      }

      final hooks = readHooks()['hooks'] as Map<String, dynamic>;
      expect((hooks['Stop'] as List).length, 1);

      final config = readConfig();
      expect('# >>> cockpit hooks'.allMatches(config).length, 1);
      expect('trusted_hash'.allMatches(config).length, 7);
    });

    test('preserva hooks de terceiros e reindexa o trust', () async {
      // Usuário já tem um hook próprio em Stop: o nosso entra DEPOIS, então a
      // chave de trust precisa apontar pro índice 1, não pro 0.
      File('${codex.path}/hooks.json').writeAsStringSync(
        jsonEncode({
          'hooks': {
            'Stop': [
              {
                'hooks': [
                  {'type': 'command', 'command': '/usr/local/bin/meu-hook'},
                ],
              },
            ],
          },
        }),
      );

      const installer = _FakeInstaller('/bin/cockpit hook');
      await installer.writeConfig(
        home: home.path,
        command: '/bin/cockpit hook',
      );

      final stop =
          (readHooks()['hooks'] as Map<String, dynamic>)['Stop'] as List;
      expect(stop, hasLength(2));
      expect(jsonEncode(stop.first), contains('meu-hook'));
      expect(
        readConfig(),
        contains('[hooks.state."${codex.path}/hooks.json:stop:1:0"]'),
      );
    });

    test(
      'preserva o resto do config.toml e substitui só o nosso bloco',
      () async {
        final config = File('${codex.path}/config.toml')
          ..writeAsStringSync(
            'model = "gpt-5.6"\n\n[projects."/tmp"]\n'
            'trust_level = "trusted"\n',
          );

        const installer = _FakeInstaller('/bin/cockpit hook');
        await installer.writeConfig(
          home: home.path,
          command: '/bin/cockpit hook',
        );
        await installer.writeConfig(
          home: home.path,
          command: '/bin/cockpit hook',
        );

        final content = config.readAsStringSync();
        expect(content, contains('model = "gpt-5.6"'));
        expect(content, contains('trust_level = "trusted"'));
        expect('# >>> cockpit hooks'.allMatches(content).length, 1);
        // O que é nosso vem no fim, depois do conteúdo do usuário.
        expect(
          content.indexOf('# >>> cockpit hooks'),
          greaterThan(content.indexOf('trust_level')),
        );
      },
    );

    test('sem ~/.codex não cria nada (Codex não instalado)', () async {
      await codex.delete(recursive: true);
      const installer = _FakeInstaller('/bin/cockpit hook');
      await installer.writeConfig(
        home: home.path,
        command: '/bin/cockpit hook',
      );
      expect(Directory('${home.path}/.codex').existsSync(), isFalse);
    });

    test('hooks.json corrompido não impede a instalação', () async {
      File('${codex.path}/hooks.json').writeAsStringSync('{ nao é json');
      const installer = _FakeInstaller('/bin/cockpit hook');
      await installer.writeConfig(
        home: home.path,
        command: '/bin/cockpit hook',
      );
      expect((readHooks()['hooks'] as Map).keys, hasLength(7));
    });
  });
}
