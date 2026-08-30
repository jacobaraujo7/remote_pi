import 'dart:convert';
import 'dart:io';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cockpit-secrets-test');
    path = '${dir.path}/db-secrets.json';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('grava, lê e apaga', () {
    final store = DbSecretStore(path: path);
    expect(store.read('/srv/proj', 'dev'), isNull);

    store.write('/srv/proj', 'dev', 's3cr3t');
    expect(store.read('/srv/proj', 'dev'), 's3cr3t');

    store.delete('/srv/proj', 'dev');
    expect(store.read('/srv/proj', 'dev'), isNull);
  });

  test('outro processo lê o que este gravou', () {
    DbSecretStore(path: path).write('/srv/proj', 'dev', 's3cr3t');
    // Instância nova = cache vazio, ou seja: leu do disco de verdade.
    expect(DbSecretStore(path: path).read('/srv/proj', 'dev'), 's3cr3t');
  });

  test('a raiz do workspace faz parte da chave', () {
    final store = DbSecretStore(path: path);
    // `dev-local` é o nome de conexão mais provável do mundo; dois workspaces
    // do mesmo host não podem compartilhar o segredo por coincidência de nome.
    store.write('/srv/a', 'dev-local', 'senha-a');
    store.write('/srv/b', 'dev-local', 'senha-b');
    expect(store.read('/srv/a', 'dev-local'), 'senha-a');
    expect(store.read('/srv/b', 'dev-local'), 'senha-b');
  });

  test('apagar um não derruba os outros', () {
    final store = DbSecretStore(path: path);
    store.write('/srv/proj', 'a', '1');
    store.write('/srv/proj', 'b', '2');
    store.delete('/srv/proj', 'a');
    expect(store.read('/srv/proj', 'a'), isNull);
    expect(store.read('/srv/proj', 'b'), '2');
  });

  test('arquivo corrompido não derruba o servidor nem impede regravar', () {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('{isto não é json');
    final store = DbSecretStore(path: path);
    expect(store.read('/srv/proj', 'dev'), isNull);
    store.write('/srv/proj', 'dev', 'nova');
    expect(DbSecretStore(path: path).read('/srv/proj', 'dev'), 'nova');
  });

  test('o segredo NÃO fica em texto claro no disco', () {
    DbSecretStore(path: path).write('/srv/proj', 'dev', 's3cr3t-em-claro');
    final raw = File(path).readAsStringSync();
    // O motivo da cifragem: vazamento acidental (backup, grep, print de tela).
    expect(raw, isNot(contains('s3cr3t-em-claro')));
    expect(raw, isNot(contains('/srv/proj')));
    expect(raw, isNot(contains('dev')));
    // E continua sendo um JSON legível como envelope.
    final env = jsonDecode(raw) as Map<String, Object?>;
    expect(env['v'], 1);
    expect(env['n'], isA<String>());
    expect(env['d'], isA<String>());
  });

  test('cofre legado em CLARO ainda é lido (sem passo de migração)', () {
    // Formato anterior à cifragem: mapa direto, chave separada por NUL.
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'/srv/proj\u0000dev': 'senha-antiga'}),
      );

    final store = DbSecretStore(path: path);
    expect(store.read('/srv/proj', 'dev'), 'senha-antiga');

    // A próxima escrita regrava cifrado, sem ninguém pedir migração.
    store.write('/srv/proj', 'outra', 'nova');
    expect(File(path).readAsStringSync(), isNot(contains('senha-antiga')));
    final reaberto = DbSecretStore(path: path);
    expect(reaberto.read('/srv/proj', 'dev'), 'senha-antiga');
    expect(reaberto.read('/srv/proj', 'outra'), 'nova');
  });

  test('envelope adulterado não derruba o servidor: cofre vazio', () {
    DbSecretStore(path: path).write('/srv/proj', 'dev', 's3cr3t');
    final env = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    // Vira um byte do ciphertext: o GCM é autenticado, então tem que recusar.
    final d = base64.decode(env['d']! as String);
    d[0] = d[0] ^ 0xff;
    env['d'] = base64.encode(d);
    File(path).writeAsStringSync(jsonEncode(env));

    expect(DbSecretStore(path: path).read('/srv/proj', 'dev'), isNull);
  });

  test('outra instância enxerga escrita de fora (dois escritores)', () {
    // O app (workspace local) e o sidecar (cliente remoto) escrevem o MESMO
    // arquivo. Sem revalidar por mtime, um serviria eternamente o valor que o
    // outro acabou de substituir.
    final leitor = DbSecretStore(path: path);
    final escritor = DbSecretStore(path: path);

    escritor.write('/srv/proj', 'dev', 'primeira');
    expect(leitor.read('/srv/proj', 'dev'), 'primeira');

    escritor.write('/srv/proj', 'dev', 'segunda');
    expect(
      leitor.read('/srv/proj', 'dev'),
      'segunda',
      reason: 'o leitor precisa revalidar o cache',
    );

    escritor.delete('/srv/proj', 'dev');
    expect(leitor.read('/srv/proj', 'dev'), isNull);
  });

  test('rename move o segredo sem o valor sair do cofre', () {
    final store = DbSecretStore(path: path);
    store.write('/srv/proj', 'antiga', 's3cr3t');

    store.rename('/srv/proj', 'antiga', 'nova');

    expect(store.read('/srv/proj', 'antiga'), isNull);
    expect(store.read('/srv/proj', 'nova'), 's3cr3t');
    // Persistiu: quem renomeia não pode depender de o processo continuar vivo.
    expect(DbSecretStore(path: path).read('/srv/proj', 'nova'), 's3cr3t');
  });

  test('rename de chave inexistente é no-op (não cria entrada vazia)', () {
    final store = DbSecretStore(path: path);
    store.write('/srv/proj', 'outra', 'x');
    store.rename('/srv/proj', 'nao-existe', 'nova');
    expect(store.read('/srv/proj', 'nova'), isNull);
    expect(store.read('/srv/proj', 'outra'), 'x');
  });

  test('o arquivo nasce 0600', () {
    // Permissão POSIX; no Windows o equivalente é ACL e o teste não se aplica.
    if (Platform.isWindows) return;
    DbSecretStore(path: path).write('/srv/proj', 'dev', 's3cr3t');
    final mode = Process.runSync('stat', [
      '-c',
      '%a',
      path,
    ]).stdout.toString().trim();
    expect(mode, '600');
  });
}
