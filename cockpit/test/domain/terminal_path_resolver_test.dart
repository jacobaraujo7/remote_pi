import 'package:cockpit/app/cockpit/domain/services/terminal_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/repo';
  bool Function(String) disk(Set<String> files) => files.contains;

  test('absoluto: abre como está, normalizado', () {
    expect(
      TerminalPathResolver.resolve('/repo/a/../b.md', cwd: '/x'),
      '/repo/b.md',
    );
  });

  test('~ expande pro home', () {
    expect(
      TerminalPathResolver.resolve('~/notes.md', cwd: null, home: '/home/j'),
      '/home/j/notes.md',
    );
    expect(TerminalPathResolver.resolve('~/x', cwd: '/a'), isNull);
  });

  test('relativo que existe no cwd vence', () {
    expect(
      TerminalPathResolver.resolve(
        'lib/main.dart',
        cwd: '/repo/cockpit',
        roots: [root],
        exists: disk({'/repo/cockpit/lib/main.dart', '/repo/lib/main.dart'}),
      ),
      '/repo/cockpit/lib/main.dart',
    );
  });

  test('agente em cockpit/ cita plan/ da raiz do monorepo: sobe e acha', () {
    expect(
      TerminalPathResolver.resolve(
        'plan/66-janela-dbq.md',
        cwd: '/repo/cockpit',
        roots: [root],
        exists: disk({'/repo/plan/66-janela-dbq.md'}),
      ),
      '/repo/plan/66-janela-dbq.md',
    );
  });

  test('não sobe além da raiz do workspace', () {
    expect(
      TerminalPathResolver.resolve(
        'secret.md',
        cwd: '/repo/cockpit',
        roots: [root],
        exists: disk({'/secret.md'}),
      ),
      '/repo/cockpit/secret.md',
    );
  });

  test('cwd fora do workspace: tenta o cwd e as raízes, sem subir', () {
    expect(
      TerminalPathResolver.resolve(
        'plan/a.md',
        cwd: '/tmp/work',
        roots: [root],
        exists: disk({'/tmp/plan/a.md', '/repo/plan/a.md'}),
      ),
      '/repo/plan/a.md',
    );
  });

  test('nada existe (ou remoto, sem disco): cwd + caminho', () {
    expect(
      TerminalPathResolver.resolve(
        'plan/novo.md',
        cwd: '/repo/cockpit',
        roots: [root],
        exists: disk({}),
      ),
      '/repo/cockpit/plan/novo.md',
    );
    expect(
      TerminalPathResolver.resolve('./x/../y.md', cwd: '/srv/app'),
      '/srv/app/y.md',
    );
  });

  test('sem cwd, relativo ainda acha pela raiz', () {
    expect(
      TerminalPathResolver.resolve(
        'README.md',
        cwd: null,
        roots: [root],
        exists: disk({'/repo/README.md'}),
      ),
      '/repo/README.md',
    );
    expect(TerminalPathResolver.resolve('README.md', cwd: null), isNull);
  });
}
