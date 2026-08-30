import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// O alias curto `ck` é o MESMO binário da CLI, criado ao lado dela: symlink
/// no POSIX, cópia no Windows (onde symlink exige privilégio).
void main() {
  late Directory dir;
  const installer = ClaudeHookInstallerImpl();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cli-alias');
    await File('${dir.path}/cockpit').writeAsString('#!/bin/sh\necho oi\n');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String aliasPath() => '${dir.path}/${Platform.isWindows ? 'ck.exe' : 'ck'}';

  test('cria o alias apontando para a CLI', () async {
    await installer.ensureShortAlias(dir.path, 'cockpit');

    expect(File(aliasPath()).existsSync(), isTrue);
    if (!Platform.isWindows) {
      // Alvo RELATIVO: mover o $HOME (backup, usuário renomeado) não pode
      // transformar o alias num ponteiro morto.
      expect(Link(aliasPath()).targetSync(), 'cockpit');
    }
    expect(File(aliasPath()).readAsStringSync(), contains('echo oi'));
  });

  test('é idempotente — rodar de novo não quebra o alias', () async {
    await installer.ensureShortAlias(dir.path, 'cockpit');
    await installer.ensureShortAlias(dir.path, 'cockpit');

    expect(File(aliasPath()).existsSync(), isTrue);
    expect(File(aliasPath()).readAsStringSync(), contains('echo oi'));
  });

  test('substitui um alias que aponta para o lugar errado', () async {
    await File('${dir.path}/outro').writeAsString('#!/bin/sh\necho velho\n');
    if (Platform.isWindows) {
      await File('${dir.path}/outro').copy(aliasPath());
    } else {
      Link(aliasPath()).createSync('outro');
    }

    await installer.ensureShortAlias(dir.path, 'cockpit');
    expect(File(aliasPath()).readAsStringSync(), contains('echo oi'));
  });

  test('sem CLI materializada, não inventa alias', () async {
    final vazio = await Directory.systemTemp.createTemp('cli-alias-vazio');
    addTearDown(() => vazio.delete(recursive: true));

    await installer.ensureShortAlias(vazio.path, 'cockpit');
    expect(
      File(
        '${vazio.path}/${Platform.isWindows ? 'ck.exe' : 'ck'}',
      ).existsSync(),
      isFalse,
    );
  });
}
