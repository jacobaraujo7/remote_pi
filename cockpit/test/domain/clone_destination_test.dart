import 'package:cockpit/app/cockpit/domain/validators/clone_destination.dart';
import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Os três alvos de release: macOS Apple Silicon, macOS Intel e Windows.
/// Silicon e Intel têm o mesmo layout de home/caminhos (POSIX); a diferença
/// entre eles é onde o Homebrew põe o git (coberto em git_binary_test).
void main() {
  group('userHome por plataforma (env injetado)', () {
    test('macOS (Silicon e Intel): HOME', () {
      expect(
        userHome(environment: {'HOME': '/Users/ana'}, isWindows: false),
        '/Users/ana',
      );
    });

    test('macOS ignora USERPROFILE e devolve null sem HOME', () {
      expect(
        userHome(environment: {'USERPROFILE': r'C:\x'}, isWindows: false),
        isNull,
      );
    });

    test('Windows: USERPROFILE, mesmo com HOME setado (Git Bash)', () {
      expect(
        userHome(
          environment: {'USERPROFILE': r'C:\Users\ana', 'HOME': '/c/Users/ana'},
          isWindows: true,
        ),
        r'C:\Users\ana',
      );
    });

    test('Windows sem USERPROFILE: HOMEDRIVE + HOMEPATH', () {
      expect(
        userHome(
          environment: {'HOMEDRIVE': 'D:', 'HOMEPATH': r'\Users\ana'},
          isWindows: true,
        ),
        r'D:\Users\ana',
      );
    });

    test('Windows sem nenhuma variável: null', () {
      expect(userHome(environment: const {}, isWindows: true), isNull);
    });
  });

  group('cloneInitialParent', () {
    test('macOS: pasta-mãe do workspace selecionado', () {
      expect(
        cloneInitialParent(
          selectedProjectPath: '/Users/ana/Projetos/remote_pi',
          home: '/Users/ana',
          fallback: '/',
          context: p.posix,
        ),
        '/Users/ana/Projetos',
      );
    });

    test('Windows: pasta-mãe com barra invertida e drive', () {
      expect(
        cloneInitialParent(
          selectedProjectPath: r'C:\Users\ana\Projetos\remote_pi',
          home: r'C:\Users\ana',
          fallback: r'C:\',
          context: p.windows,
        ),
        r'C:\Users\ana\Projetos',
      );
    });

    test('Windows: workspace na raiz do drive fica na raiz', () {
      expect(
        cloneInitialParent(
          selectedProjectPath: r'D:\repo',
          home: r'C:\Users\ana',
          fallback: r'C:\',
          context: p.windows,
        ),
        r'D:\',
      );
    });

    test('sem workspace: home (macOS e Windows)', () {
      expect(
        cloneInitialParent(home: '/Users/ana', fallback: '/', context: p.posix),
        '/Users/ana',
      );
      expect(
        cloneInitialParent(
          selectedProjectPath: '  ',
          home: r'C:\Users\ana',
          fallback: r'C:\',
          context: p.windows,
        ),
        r'C:\Users\ana',
      );
    });

    test('sem workspace nem home: fallback', () {
      expect(cloneInitialParent(fallback: '/tmp', context: p.posix), '/tmp');
    });
  });

  group('cloneTargetPath e folderDisplayName', () {
    test('macOS junta com /', () {
      expect(
        cloneTargetPath('/Users/ana/Projetos', ' remote_pi ', context: p.posix),
        '/Users/ana/Projetos/remote_pi',
      );
      expect(cloneTargetPath('/', 'repo', context: p.posix), '/repo');
    });

    test(r'Windows junta com \ e respeita a raiz do drive', () {
      expect(
        cloneTargetPath(
          r'C:\Users\ana\Projetos',
          'remote_pi',
          context: p.windows,
        ),
        r'C:\Users\ana\Projetos\remote_pi',
      );
      expect(cloneTargetPath(r'D:\', 'repo', context: p.windows), r'D:\repo');
    });

    test('nome exibido = último segmento, nas duas convenções', () {
      expect(
        folderDisplayName('/Users/ana/Projetos/app/', context: p.posix),
        'app',
      );
      expect(
        folderDisplayName(r'C:\Users\ana\Projetos\app', context: p.windows),
        'app',
      );
      // Antes era split('/'), que devolvia o caminho inteiro no Windows.
      expect(
        folderDisplayName(r'C:\Projetos\billing-api', context: p.windows),
        'billing-api',
      );
    });
  });

  group('validateCloneFolderName', () {
    test('nome de repo comum serve nas duas plataformas', () {
      for (final w in [false, true]) {
        expect(validateCloneFolderName('remote_pi', windows: w), isNull);
        expect(validateCloneFolderName('my-app.v2', windows: w), isNull);
      }
    });

    test('vazio, ponto e separadores são recusados em qualquer plataforma', () {
      for (final w in [false, true]) {
        expect(
          validateCloneFolderName('  ', windows: w),
          CloneFolderError.empty,
        );
        expect(
          validateCloneFolderName('..', windows: w),
          CloneFolderError.dotName,
        );
        expect(
          validateCloneFolderName('a/b', windows: w),
          CloneFolderError.separator,
        );
        expect(
          validateCloneFolderName(r'a\b', windows: w),
          CloneFolderError.separator,
        );
      }
    });

    test('regras do Windows não valem no macOS', () {
      expect(validateCloneFolderName('a:b', windows: false), isNull);
      expect(validateCloneFolderName('CON', windows: false), isNull);
      expect(validateCloneFolderName('repo.', windows: false), isNull);
    });

    test('Windows: caracteres, nomes reservados e ponto/espaço final', () {
      expect(
        validateCloneFolderName('a:b', windows: true),
        CloneFolderError.invalidChar,
      );
      expect(
        validateCloneFolderName('what?', windows: true),
        CloneFolderError.invalidChar,
      );
      expect(
        validateCloneFolderName('con', windows: true),
        CloneFolderError.reserved,
      );
      expect(
        validateCloneFolderName('NUL.txt', windows: true),
        CloneFolderError.reserved,
      );
      expect(validateCloneFolderName('console', windows: true), isNull);
      expect(
        validateCloneFolderName('repo.', windows: true),
        CloneFolderError.trailingDotOrSpace,
      );
    });
  });

  group('classifyCloneFailure', () {
    test('reconhece as falhas com dica', () {
      expect(
        classifyCloneFailure([
          r'$ git clone x',
          'Failed to run git: ProcessException: The system cannot find the file specified.',
        ]),
        CloneFailure.gitMissing,
      );
      expect(
        classifyCloneFailure([
          'xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), missing xcrun',
        ]),
        CloneFailure.xcodeToolsMissing,
      );
      expect(
        classifyCloneFailure([
          "error: cannot run ssh: No such file or directory",
          'fatal: unable to fork',
        ]),
        CloneFailure.sshMissing,
      );
      expect(
        classifyCloneFailure(['Host key verification failed.']),
        CloneFailure.hostKey,
      );
      expect(
        classifyCloneFailure([
          'git@github.com: Permission denied (publickey).',
          'fatal: Could not read from remote repository.',
        ]),
        CloneFailure.auth,
      );
      expect(
        classifyCloneFailure([
          "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
        ]),
        CloneFailure.auth,
      );
    });

    test('falha sem dica conhecida: null', () {
      expect(
        classifyCloneFailure([
          "fatal: destination path 'x' already exists and is not an empty directory.",
        ]),
        isNull,
      );
    });
  });
}
