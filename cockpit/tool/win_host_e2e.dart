// Verificação fim-a-fim de HOST WINDOWS (plano 61, passos B.1–C.2b).
//
// Exercita o caminho REAL do cliente — as mesmas classes que o
// `RemoteHostConnector` usa — contra um host Windows, e vai até abrir um PTY de
// verdade. É o que fecha o risco que o spike de 2026-08-26 deixou aberto: o
// servidor iniciado por WMI nasce na **sessão 0**, e ConPTY nessa sessão não
// tinha sido exercitado.
//
// Uso (a partir de `cockpit/`):
//   dart run tool/win_host_e2e.dart <user@host> [--identity <chave>] [--port 22]
//
// O host precisa ter o Cockpit instalado (decisão D2) — ver
// docs/windows-host-setup.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/windows_host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_channel_duplex.dart';
import 'package:cockpit/app/cockpit/data/remote/ssh_tunnel.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_remote/cockpit_remote.dart';

var _failures = 0;
List<String> _mobileArgs = const [];

void _check(String label, bool ok, [String detail = '']) {
  stdout.writeln(
    '${ok ? '  ok  ' : ' FAIL '} $label${detail.isEmpty ? '' : ' — $detail'}',
  );
  if (!ok) _failures++;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'uso: dart run tool/win_host_e2e.dart <user@host> '
      '[--identity <chave>] [--port 22]',
    );
    exit(64);
  }
  final target = args.first;
  final identity = _optionOf(args, '--identity');
  final port = int.tryParse(_optionOf(args, '--port') ?? '22') ?? 22;

  Future<(int, String, String)> exec(String command, {List<int>? stdinBytes}) =>
      SshTunnel.capture(
        target,
        command,
        stdinBytes: stdinBytes,
        port: port,
        identityFile: identity,
      );

  stdout.writeln('== host $target ==');

  // B1 — detecção de OS/arch.
  final probe = await probeHost(exec);
  _check('probe respondeu', probe != null);
  if (probe == null) exit(1);
  _check('família = windows', probe.family == HostOsFamily.windows, probe.os);
  _check('home resolvida', probe.home.isNotEmpty, probe.home);
  stdout.writeln('       arch=${probe.arch}');

  final shell = WindowsHostShell(probe: probe, exec: exec);

  // C1 — instalação por cópia local do bundle do host (D2).
  final installed = await shell.installFromHost();
  _check('bundle do host copiado (sem tráfego SSH)', installed);
  if (!installed) {
    stdout.writeln(
      '       host sem Cockpit instalado; ver docs/windows-host-setup.md',
    );
    exit(1);
  }

  // C2 — start fora do Job Object, via WMI.
  await shell.startServer(idleSeconds: 120);

  // B2/B3 — rendezvous com porta + token.
  final endpoint = await shell.awaitEndpoint();
  _check('rendezvous lido e porta viva', endpoint is TcpEndpoint);
  if (endpoint is! TcpEndpoint) {
    stdout.writeln('       boot log:\n${await shell.tailBootLog()}');
    exit(1);
  }
  _check('token presente', endpoint.token != null);
  stdout.writeln('       port=${endpoint.port}');

  // Transporte MOBILE (`--mobile`): dartssh2 + SshChannelDuplex, a pilha do
  // iPad. É a única diferença estrutural entre os dois clientes — o desktop
  // usa o `ssh` do sistema com `-L`. Existe porque o terminal funciona no
  // macOS contra este mesmo host e não no iPad: se o input morrer aqui, o
  // culpado é o transporte, não o servidor.
  if (args.contains('--mobile')) {
    _mobileArgs = args;
    await _runMobile(target, port, identity, endpoint);
    return;
  }

  // B2 — túnel TCP↔TCP.
  final tunnel = await SshTunnel.open(
    target: target,
    remote: endpoint,
    port: port,
    identityFile: identity,
  );
  _check('túnel aberto', tunnel.isOpen);

  // B4 — handshake com token.
  final duplex = tunnel.localPort != null
      ? SocketRemoteDuplex(
          await Socket.connect(InternetAddress.loopbackIPv4, tunnel.localPort!),
        )
      : await SocketRemoteDuplex.connectUnix(tunnel.localSocketPath);
  final connection = await RemoteConnection.connectOn(
    duplex,
    clientName: 'win-host-e2e',
    token: endpoint.token,
  );
  _check('handshake aceito', connection.isOpen);

  if (args.contains('--bench')) {
    await _bench('desktop (ssh -L)', connection, r'C:\\Users\\jacob');
  }

  // C2b — o que o spike deixou em aberto: PTY REAL, com o servidor na sessão 0.
  final service = RemoteTerminalService(connection);
  final session = await service.open(
    const PtySpawnSpec(
      // PowerShell, e não `cmd.exe`, para a prova de UTF-8: o `cmd` converte a
      // própria linha de comando para a codepage OEM ao arrancar (CP-850 em
      // pt-BR), então um acento vindo no argumento já chega deformado lá dentro
      // — e `chcp 65001` depois não desfaz isso. Com o `OutputEncoding` fixado
      // em UTF-8, o que sai do shell é UTF-8 de verdade, e é o CAMINHO (ConPTY
      // → servidor → protocolo → túnel → cliente) que fica sob teste, que é o
      // que este script existe para verificar.
      // `executable` VAZIO: é exatamente o que o cliente remoto manda para
      // "login shell do host" (`TerminalProfile.hostLoginShell`), e o caso que
      // deixava a aba do iPad vazia — num host Windows o servidor caía no
      // fallback POSIX `/bin/sh -l`, que não existe lá.
      executable: '',
      // Mesmos parâmetros do cliente remoto real
      // (`remote_host_terminal_gateway`): sem eles o teste exercitava um
      // modo que nenhum cliente usa.
      environment: {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      flowControlled: true,
      rows: 24,
      columns: 80,
    ),
  );
  _check('PTY aberto na sessão 0', session.pid > 0, 'pid=${session.pid}');

  final output = StringBuffer();
  final done = Completer<void>();
  final sub = service.attach(session.id).listen((event) {
    if (event is PtyOutputEvent) {
      output.write(utf8.decode(event.chunk.bytes, allowMalformed: true));
      // Flow control: sem devolver crédito por chunk consumido, a leitura
      // no servidor trava depois da primeira janela e a saída seca.
      unawaited(service.ack(session.id, event.chunk.bytes.length));
      if (output.length > 0 && !done.isCompleted) done.complete();
    }
  });
  await done.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => stdout.writeln('       (timeout esperando saída do PTY)'),
  );
  _check('login shell do host abriu e produziu saída', output.isNotEmpty);
  // O que o shell do host cuspiu — evidência de QUAL shell abriu.
  for (final line in const LineSplitter().convert(output.toString())) {
    if (line.trim().isNotEmpty) stdout.writeln('       | ${line.trim()}');
  }

  // Round-trip de INPUT: digita um comando e exige ver o resultado dele.
  //
  // O check anterior aqui era `output.length > 0`, que só reafirmava que
  // ALGO tinha saído antes — passava mesmo com a digitação sendo ignorada,
  // que é exatamente o bug que ele deveria pegar. Um teste que não pode
  // falhar não é teste.
  final before = output.length;
  final echoed = Completer<void>();
  final watcher = Timer.periodic(const Duration(milliseconds: 200), (t) {
    if (output.toString().contains('INPUT_ROUNDTRIP_OK') &&
        !echoed.isCompleted) {
      echoed.complete();
      t.cancel();
    }
  });
  await service.write(
    session.id,
    Uint8List.fromList(utf8.encode('echo INPUT_ROUNDTRIP_OK\r')),
  );
  await echoed.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () => stdout.writeln('       (timeout esperando eco do input)'),
  );
  watcher.cancel();
  _check(
    'input digitado chega no shell e ecoa',
    output.toString().contains('INPUT_ROUNDTRIP_OK'),
    'bytes novos: ${output.length - before}',
  );

  await sub.cancel();
  await service.kill(session.id);
  await connection.close();
  await tunnel.close();
  await shell.killServer();

  stdout.writeln(
    _failures == 0 ? '\nTUDO VERDE' : '\n$_failures verificação(ões) falharam',
  );
  exit(_failures == 0 ? 0 : 1);
}

String? _optionOf(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

/// Mesmo roteiro do caminho desktop, mas sobre o transporte do MOBILE.
Future<void> _runMobile(
  String target,
  int port,
  String? identity,
  TcpEndpoint endpoint,
) async {
  // --cwd: reproduz o workingDirectory que o picker remoto produz. Ele é
  // POSIX hardcoded, então num host Windows sai com separador MISTO
  // (`C:\\Users\\jacob/pasta`) e, ao subir um nível, vira `/`.
  final cwdIndex = _mobileArgs.indexOf('--cwd');
  final cwd = cwdIndex >= 0 ? _mobileArgs[cwdIndex + 1] : null;
  final user = target.split('@').first;
  final host = target.split('@').last;
  final socket = await SSHSocket.connect(host, port);
  final client = SSHClient(
    socket,
    username: user,
    identities: SSHKeyPair.fromPem(await File(identity!).readAsString()),
  );
  await client.authenticated;
  _check('mobile: autenticou', true);

  final channel = await client.forwardLocal('127.0.0.1', endpoint.port);
  _check('mobile: forwardLocal abriu', true);

  final connection = await RemoteConnection.connectOn(
    SshChannelDuplex(channel),
    clientName: 'cockpit-ipad',
    token: endpoint.token,
  );
  _check('mobile: handshake aceito', connection.isOpen);

  if (_mobileArgs.contains('--bench')) {
    await _bench('mobile (dartssh2)', connection, r'C:\\Users\\jacob');
  }

  final service = RemoteTerminalService(connection);
  final session = await service.open(
    PtySpawnSpec(
      executable: '',
      workingDirectory: cwd,
      environment: const {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      flowControlled: true,
      rows: 24,
      columns: 80,
    ),
  );
  _check('mobile: PTY aberto', session.pid > 0, 'pid=${session.pid}');

  final output = StringBuffer();
  final echoed = Completer<void>();
  final sub = service.attach(session.id).listen((event) {
    if (event is PtyOutputEvent) {
      output.write(utf8.decode(event.chunk.bytes, allowMalformed: true));
      unawaited(service.ack(session.id, event.chunk.bytes.length));
      if (output.toString().contains('INPUT_ROUNDTRIP_OK') &&
          !echoed.isCompleted) {
        echoed.complete();
      }
    }
  });

  await Future<void>.delayed(const Duration(seconds: 2));
  _check('mobile: shell produziu saida', output.isNotEmpty);

  await service.write(
    session.id,
    Uint8List.fromList(utf8.encode('echo INPUT_ROUNDTRIP_OK\r')),
  );
  await echoed.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () => stdout.writeln('       (timeout esperando eco do input)'),
  );
  _check(
    'mobile: input digitado ecoa',
    output.toString().contains('INPUT_ROUNDTRIP_OK'),
  );
  for (final line in const LineSplitter().convert(output.toString())) {
    if (line.trim().isNotEmpty) stdout.writeln('       | ${line.trim()}');
  }

  await sub.cancel();
  await connection.close();
  client.close();
  stdout.writeln(_failures == 0 ? 'MOBILE VERDE' : 'FALHOU');
  exit(_failures == 0 ? 0 : 1);
}

/// Mede N operações SEQUENCIAIS de arquivo sobre uma conexão já aberta.
///
/// Files/tasks/terminal travam JUNTOS no iPad, então o suspeito é o transporte
/// compartilhado — e não o terminal. Aqui a comparação é justa: mesma máquina,
/// mesmo host, mesmo servidor; muda só o caminho até ele.
Future<void> _bench(
  String label,
  RemoteConnection connection,
  String dir,
) async {
  final files = RemoteFileService(connection);
  // Descarta a primeira: paga abertura de recursos do lado do servidor.
  await files.list(dir);
  final sw = Stopwatch()..start();
  const rounds = 30;
  var entries = 0;
  for (var i = 0; i < rounds; i++) {
    entries += (await files.list(dir)).length;
  }
  sw.stop();
  final perOp = sw.elapsedMilliseconds / rounds;
  stdout.writeln(
    '       $label: ${sw.elapsedMilliseconds}ms / $rounds ops '
    '= ${perOp.toStringAsFixed(1)}ms por op ($entries entradas)',
  );
}
