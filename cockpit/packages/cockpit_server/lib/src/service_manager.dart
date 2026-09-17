// `cockpit-server service install|uninstall|status` (plano 2.0, k25).
//
// Registra o servidor como serviço de USUÁRIO do systemd, para subir com o
// sistema numa VPS sem depender de um cliente conectar. Vive no binário (e
// não num script solto) pela mesma razão do `remote-pi install`: a lógica
// fica em Dart, testável, ao lado das flags que ela usa.
//
// Sem sudo: a unit vai em `~/.config/systemd/user/` e é gerida com
// `systemctl --user`. O único ponto que pode exigir root é o *linger*
// (`loginctl enable-linger`), necessário para o serviço subir no boot sem
// ninguém logado por SSH. Tentamos; se negar, imprimimos o comando exato.
//
// Só Linux. macOS (launchd) fica para quando houver host macOS dedicado.
import 'dart:io';

/// Nome da unit, também o nome do arquivo `.service`.
const String kServiceName = 'cockpit-server';

/// Gera o conteúdo da unit do systemd. Puro: recebe os caminhos já resolvidos
/// para ser testável sem tocar no sistema.
///
/// - Sem `--exit-on-idle`: modo serviço, nunca sai sozinho.
/// - `COCKPIT_PTY_DYLIB` aponta para a lib ao lado do binário (o mesmo que o
///   cliente injeta ao subir o servidor por SSH).
/// - `%h` é o HOME do usuário da unit, resolvido pelo próprio systemd, então a
///   unit não fixa um caminho absoluto de usuário.
String buildSystemdUnit({
  required String serverBinary,
  required String ptyLibrary,
  required String socketPath,
}) => '''
[Unit]
Description=Remote Pi Cockpit server
Documentation=https://remote-pi.jacobmoura.work/cockpit
After=network.target

[Service]
Type=simple
Environment=COCKPIT_PTY_DYLIB=$ptyLibrary
ExecStart=$serverBinary --socket $socketPath
Restart=on-failure
RestartSec=2
KillMode=mixed
TimeoutStopSec=10

[Install]
WantedBy=default.target
''';

/// Resultado de um passo do gerenciador: `ok` + o que dizer ao usuário.
class ServiceStep {
  const ServiceStep(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Executa comandos externos. Abstraído para os testes não chamarem o
/// systemctl de verdade.
typedef CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _defaultRunner(String exe, List<String> args) =>
    Process.run(exe, args);

class ServiceManager {
  ServiceManager({
    required this.home,
    required this.serverBinary,
    CommandRunner? run,
    StringSink? out,
  }) : _run = run ?? _defaultRunner,
       _out = out ?? stdout;

  final String home;
  final String serverBinary;
  final CommandRunner _run;
  final StringSink _out;

  String get unitDir => '$home/.config/systemd/user';
  String get unitPath => '$unitDir/$kServiceName.service';
  String get socketPath => '$home/.cockpit/cockpit-server.sock';

  /// `bin/cockpit-server` → `lib/libcockpit_pty.so` (layout do bundle).
  String get ptyLibrary {
    final bin = File(serverBinary).parent;
    return '${bin.parent.path}/lib/libcockpit_pty.so';
  }

  String get _user =>
      Platform.environment['USER'] ??
      Platform.environment['LOGNAME'] ??
      'USER';

  /// Escreve a unit, recarrega o systemd, habilita e inicia. Depois tenta o
  /// linger. Devolve 0 em sucesso (mesmo se o linger foi negado: o serviço
  /// está de pé, só não sobe sozinho no boot até o usuário rodar o sudo).
  Future<int> install() async {
    if (!Platform.isLinux) {
      _out.writeln('cockpit-server service: only Linux (systemd) is supported');
      return 2;
    }
    if (!File(serverBinary).existsSync()) {
      _out.writeln('cockpit-server service: binary not found: $serverBinary');
      return 2;
    }
    final unit = buildSystemdUnit(
      serverBinary: serverBinary,
      ptyLibrary: ptyLibrary,
      socketPath: socketPath,
    );
    Directory(unitDir).createSync(recursive: true);
    File(unitPath).writeAsStringSync(unit, flush: true);
    _out.writeln('wrote $unitPath');

    for (final args in [
      ['--user', 'daemon-reload'],
      ['--user', 'enable', '--now', '$kServiceName.service'],
    ]) {
      final r = await _run('systemctl', args);
      if (r.exitCode != 0) {
        _out.writeln('systemctl ${args.join(' ')} failed:');
        _out.writeln(_trim(r));
        return 1;
      }
    }
    _out.writeln('service enabled and started (systemctl --user)');

    final linger = await _run('loginctl', ['enable-linger', _user]);
    if (linger.exitCode == 0) {
      _out.writeln('linger enabled: the service starts at boot');
    } else {
      _out.writeln(
        'could not enable linger (needed to start at boot without a login).\n'
        'Run once:\n'
        '  sudo loginctl enable-linger $_user',
      );
    }
    return 0;
  }

  /// Para, desabilita, apaga a unit e recarrega. Não mexe no linger: ele é
  /// do usuário, não do serviço, e outros serviços podem depender dele.
  Future<int> uninstall() async {
    if (!Platform.isLinux) {
      _out.writeln('cockpit-server service: only Linux (systemd) is supported');
      return 2;
    }
    // Best-effort: unit ausente não é erro de desinstalação.
    await _run('systemctl', ['--user', 'disable', '--now', kServiceName]);
    final file = File(unitPath);
    if (file.existsSync()) {
      file.deleteSync();
      _out.writeln('removed $unitPath');
    } else {
      _out.writeln('no unit at $unitPath');
    }
    await _run('systemctl', ['--user', 'daemon-reload']);
    _out.writeln('service uninstalled');
    return 0;
  }

  /// Unit presente, estado do systemd, linger e socket. Sempre sai 0: é
  /// consulta, o texto é a resposta.
  Future<int> status() async {
    if (!Platform.isLinux) {
      _out.writeln('cockpit-server service: only Linux (systemd) is supported');
      return 2;
    }
    final present = File(unitPath).existsSync();
    _out.writeln('unit:    ${present ? unitPath : 'not installed'}');
    if (present) {
      final active = await _run('systemctl', [
        '--user',
        'is-active',
        kServiceName,
      ]);
      _out.writeln('state:   ${_trim(active)}');
      final enabled = await _run('systemctl', [
        '--user',
        'is-enabled',
        kServiceName,
      ]);
      _out.writeln('enabled: ${_trim(enabled)}');
    }
    final linger = await _run('loginctl', [
      'show-user',
      _user,
      '--property=Linger',
    ]);
    _out.writeln(
      'linger:  ${linger.exitCode == 0 ? _trim(linger).replaceFirst('Linger=', '') : 'unknown'}',
    );
    _out.writeln(
      'socket:  ${FileSystemEntity.typeSync(socketPath) != FileSystemEntityType.notFound ? socketPath : 'absent'}',
    );
    return 0;
  }

  static String _trim(ProcessResult r) =>
      ('${r.stdout}${r.stderr}').trim().isEmpty
      ? 'exit ${r.exitCode}'
      : '${r.stdout}${r.stderr}'.trim();
}

/// Dispatcher do subcomando. `args` já sem o `service` inicial.
Future<int> runServiceCommand(
  List<String> args, {
  ServiceManager? manager,
  StringSink? out,
}) async {
  final o = out ?? stdout;
  final verb = args.isEmpty ? '' : args.first;
  final m =
      manager ??
      ServiceManager(
        home: Platform.environment['HOME'] ?? '',
        serverBinary: Platform.resolvedExecutable,
        out: o,
      );
  switch (verb) {
    case 'install':
      return m.install();
    case 'uninstall':
      return m.uninstall();
    case 'status':
      return m.status();
    default:
      o.writeln('usage: cockpit-server service <install|uninstall|status>');
      return 2;
  }
}
