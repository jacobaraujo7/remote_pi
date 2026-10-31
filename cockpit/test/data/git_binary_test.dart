import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plataforma e disco injetados: nada aqui depende do host que roda o teste.
void main() {
  GitBinary binary({
    required bool windows,
    required Set<String> onDisk,
    Map<String, String> env = const {},
  }) => GitBinary(
    environment: env,
    isWindows: windows,
    exists: (path) async => onDisk.contains(path),
  );

  test('macOS com Command Line Tools: /usr/bin/git primeiro', () async {
    final g = binary(
      windows: false,
      onDisk: {'/usr/bin/git', '/opt/homebrew/bin/git'},
    );
    expect(await g.resolve(), '/usr/bin/git');
  });

  test('macOS Apple Silicon só com Homebrew: /opt/homebrew/bin/git', () async {
    final g = binary(windows: false, onDisk: {'/opt/homebrew/bin/git'});
    expect(await g.resolve(), '/opt/homebrew/bin/git');
  });

  test('macOS Intel só com Homebrew: /usr/local/bin/git', () async {
    final g = binary(windows: false, onDisk: {'/usr/local/bin/git'});
    expect(await g.resolve(), '/usr/local/bin/git');
  });

  test('Windows: Git for Windows em Program Files', () async {
    final g = binary(
      windows: true,
      env: {'ProgramFiles': r'C:\Program Files'},
      onDisk: {r'C:\Program Files\Git\cmd\git.exe'},
    );
    expect(await g.resolve(), r'C:\Program Files\Git\cmd\git.exe');
  });

  test('Windows: instalação por usuário em LOCALAPPDATA', () async {
    final g = binary(
      windows: true,
      env: {
        'ProgramFiles': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\ana\AppData\Local',
      },
      onDisk: {r'C:\Users\ana\AppData\Local\Programs\Git\cmd\git.exe'},
    );
    expect(
      await g.resolve(),
      r'C:\Users\ana\AppData\Local\Programs\Git\cmd\git.exe',
    );
  });

  test('Windows não procura caminhos POSIX', () async {
    final g = binary(windows: true, onDisk: {'/usr/bin/git'});
    expect(g.candidates.any((c) => c.startsWith('/')), isFalse);
    expect(await g.resolve(), 'git');
  });

  test('nenhum candidato: cai no git do PATH', () async {
    expect(await binary(windows: false, onDisk: {}).resolve(), 'git');
  });
}
