// cockpit-server (plano 58, Wave 0) — binário headless, sem Flutter.
//
// Composição via auto_injector puro (mesmo motor do flutter_modular v7),
// seguindo as convenções do app: registro por tear-off `.new` quando o grafo
// resolve sozinho.
import 'dart:async';
import 'dart:io';

import 'package:auto_injector/auto_injector.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_engine/cockpit_engine.dart';
import 'package:cockpit_server/cockpit_server.dart';

Future<void> main(List<String> args) async {
  // Rede de proteção do daemon: erro assíncrono solto (socket que morre no
  // meio de uma escrita, isolate de driver que estoura) NÃO pode derrubar o
  // processo e levar junto os terminais de todos os workspaces. Um servidor de
  // longa vida registra e segue; quem trata o caso específico é quem o conhece.
  await runZonedGuarded(
    () async {
      await _run(args);
    },
    (error, stack) {
      stderr.writeln('cockpit-server: erro não tratado: $error');
      stderr.writeln(stack.toString());
    },
  );
}

Future<void> _run(List<String> args) async {
  final socketPath =
      _argValue(args, '--socket') ??
      '${Directory.systemTemp.path}/cockpit-server-$pid.sock';

  final injector = AutoInjector()
    ..addLazySingleton<TerminalService>(NativeTerminalService.new)
    ..addInstance<FileService>(const NativeFileService())
    ..addInstance<GitService>(const NativeGitService())
    ..addInstance<DbService>(const NativeDbService())
    ..addLazySingleton<RemoteServer>(RemoteServer.new)
    ..commit();

  final server = injector.get<RemoteServer>();

  // Modo sidecar (GUI): --exit-on-idle <segundos> encerra o servidor quando
  // não resta cliente algum — o seguro contra órfão se a GUI morrer sem
  // conseguir matar o filho. Ausente ou 0 = modo serviço (nunca sai sozinho).
  final idleSeconds = int.tryParse(_argValue(args, '--exit-on-idle') ?? '0');
  if (idleSeconds != null && idleSeconds > 0) {
    server.exitOnIdle = Duration(seconds: idleSeconds);
    // `--idle-keeps-sessions`: sessão viva impede o encerramento por
    // ociosidade. Usado pelo servidor REMOTO, onde desconectar é rotina e
    // retomar de onde parou é a promessa; o sidecar local não passa a flag,
    // porque lá a GUI já morreu e ninguém vai reanexar àqueles PTYs.
    server.idleKeepsSessions = args.contains('--idle-keeps-sessions');
    server.onIdleExit = () async {
      stdout.writeln('cockpit-server idle, exiting');
      await server.close();
      exit(0);
    };
  }

  await server.bind(socketPath);

  // Turn-status (plano 60, Wave G): instala o hook do agente no ~/.claude do
  // HOST, apontando pra CLI `cockpit hook` (resolvida por --cli, ao lado do
  // server, ou no PATH). Assim uma sessão no terminal remoto reporta o turno →
  // socket de status do host → protocolo → cliente. Não-fatal.
  final hookInstaller = HostHookInstaller(
    cliPathOverride: _argValue(args, '--cli'),
  );
  unawaited(hookInstaller.ensureInstalled());
  // Mesma CLI serve a dois papéis: o hook (acima) e os comandos digitados num
  // terminal remoto. Guardar o caminho deixa a pasta dela entrar no PATH das
  // PTYs; sem CLI, o shell remoto simplesmente segue sem o comando.
  unawaited(
    hookInstaller.resolveCli().then((path) => RemoteServer.cliPath = path),
  );

  // Saída em inglês por decisão (CLI interna não se traduz).
  stdout.writeln('cockpit-server listening on $socketPath');

  // Desligamento com TETO: `close()` fecha conexões, sessões e PTYs, e
  // qualquer uma dessas etapas pode ficar presa (PTY que não reporta saída,
  // socket que não responde). Sem o teto, um SIGTERM educado não mata o
  // processo — foi assim que um sidecar órfão sobreviveu a `kill` e só saiu
  // com SIGKILL.
  Future<void> shutdown() async {
    try {
      await server.close().timeout(const Duration(seconds: 3));
    } on Object catch (e) {
      stderr.writeln('cockpit-server: desligamento forçado ($e)');
    }
    exit(0);
  }

  // SIGTERM não existe no Windows: `watch()` lança `SignalException: Failed to
  // listen for SIGTERM` (errno 50, "não há suporte para o pedido"). Isso
  // matava o servidor no ARRANQUE — o sidecar do Windows nunca chegou a
  // funcionar, e o app caía no PTY in-process sem ninguém notar. Quando o
  // runZonedGuarded passou a segurar a exceção, o servidor sobreviveu e o
  // caminho quebrado do PTY dele veio à tona.
  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  // Morte ABRUPTA do app (Force Quit, `kill -9`, crash do engine, relaunch do
  // Sparkle): nenhum handler roda, e fora do Windows não há equivalente do Job
  // Object para amarrar o filho ao pai. O detector que funciona nos três é o
  // PIPE: o app segura a ponta de escrita do nosso stdin e nunca escreve nela;
  // quando ele morre — de qualquer jeito — o kernel fecha o descritor e aqui
  // chega EOF. Não depende de sinal, de handler, nem de o app se comportar.
  //
  // Opt-in por flag de propósito: no bootstrap remoto o servidor sobe com
  // `nohup … &` por SSH, e lá o stdin fecha assim que o comando ssh retorna —
  // sem a flag, o servidor remoto morreria ao nascer.
  if (args.contains('--exit-on-parent-close')) {
    stdin.listen(
      (_) {},
      onDone: () => unawaited(shutdown()),
      onError: (Object _) => unawaited(shutdown()),
      cancelOnError: true,
    );
  }
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
