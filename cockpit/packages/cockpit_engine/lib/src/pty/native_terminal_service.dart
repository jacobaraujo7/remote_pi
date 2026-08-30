import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:ffi/ffi.dart';

import 'pty_bindings.dart';
import 'pty_dylib.dart';
import 'scrollback_buffer.dart';

class _Session {
  _Session({
    required this.info,
    required this.handle,
    required this.stdoutPort,
    required this.exitPort,
    required this.scrollback,
  });

  PtySessionInfo info;
  final Pointer<Void> handle;
  final ReceivePort stdoutPort;
  final ReceivePort exitPort;
  final ScrollbackBuffer scrollback;

  /// Broadcast dos eventos live; attach = replay do scrollback + este stream.
  final StreamController<PtyEvent> live = StreamController.broadcast();

  // --- flow control (sessões abertas com flowControlled) ---
  bool flowControlled = false;

  /// Bytes emitidos e ainda não confirmados via [TerminalService.ack].
  int outstanding = 0;

  /// A leitura nativa está travada esperando crédito.
  bool nativeAckPending = false;

  /// Consumidores anexados. Zero = leitura corre livre (só scrollback).
  int consumers = 0;
}

/// Implementação nativa do [TerminalService] sobre a dylib do cockpit_pty.
///
/// Sessões pertencem ao serviço: sobrevivem a detach de qualquer cliente e
/// só morrem via [kill] (ou exit do processo, retendo scrollback).
class NativeTerminalService implements TerminalService {
  NativeTerminalService({
    DynamicLibrary? dylib,
    this.scrollbackCapacity = 4 * 1024 * 1024,
    this.flowWindow = 256 * 1024,
  }) : _bindings = PtyBindings(dylib ?? openPtyDylib()) {
    final rc = _bindings.initializeApiDL(NativeApi.initializeApiDLData);
    if (rc != 0) {
      throw const TerminalException(
        TerminalErrorKind.spawnFailed,
        'Dart_InitializeApiDL failed',
      );
    }
  }

  final PtyBindings _bindings;
  final int scrollbackCapacity;

  /// Janela de créditos por sessão flow-controlled: quanto pode estar "no ar"
  /// (emitido sem ack do consumidor) antes de pausar a leitura nativa. Grande
  /// o bastante pra amortizar o RTT do loopback; pequena o bastante pra
  /// backpressure real sob TUI busy (plano 57).
  final int flowWindow;
  final Map<String, _Session> _sessions = {};
  int _nextId = 0;

  @override
  Future<PtySessionInfo> open(PtySpawnSpec spec) async {
    final id = 's${++_nextId}';
    final stdoutPort = ReceivePort();
    final exitPort = ReceivePort();

    // Executable vazio = "login shell do HOST": o cliente (ex.: iPad) não sabe
    // qual é o shell do host, então quem resolve é o servidor, aqui, onde o
    // ambiente do usuário do host está disponível. Ver
    // remote_host_terminal_gateway.
    //
    // No POSIX, `$SHELL` + `-l` (login) carrega .zprofile/.zshrc → oh-my-zsh e
    // cia. No Windows **não existe `$SHELL`**, e o fallback `/bin/sh -l` não
    // existe naquele sistema: o PTY nascia morto e a aba do cliente remoto
    // ficava eternamente vazia, sem erro visível — o mesmo sintoma que a
    // `TerminalProfile.hostLoginShell` foi criada para evitar no sentido
    // contrário (cliente Windows impondo `powershell.exe` a um host macOS).
    //
    // A escolha aqui espelha o fallback LOCAL do
    // `TerminalProfileResolverImpl._platformFallback()`: PowerShell no Windows
    // comum, `cmd` no Windows ARM (onde o PTY do PowerShell ainda é instável).
    // E nada de `-l`: é flag POSIX.
    final executable = spec.executable.isNotEmpty
        ? spec.executable
        : Platform.isWindows
        ? _windowsDefaultShell()
        : (Platform.environment['SHELL']?.trim().isNotEmpty ?? false)
        ? Platform.environment['SHELL']!.trim()
        : '/bin/sh';
    final arguments = spec.executable.isEmpty && spec.arguments.isEmpty
        ? (Platform.isWindows ? const <String>[] : const <String>['-l'])
        : spec.arguments;

    final arena = Arena();
    final Pointer<Void> handle;
    try {
      final options = arena<PtyOptionsNative>();
      options.ref
        ..rows = spec.rows
        ..cols = spec.columns
        ..executable = executable.toNativeUtf8(allocator: arena).cast()
        ..arguments = _stringArray(arena, [executable, ...arguments])
        ..environment = _stringArray(arena, [
          for (final e in {
            ...Platform.environment,
            ...spec.environment,
          }.entries)
            '${e.key}=${e.value}',
        ])
        // Sem working directory = ponteiro NULO, nunca string vazia. No
        // Windows, `lpCurrentDirectory = L""` faz o CreateProcessW falhar com
        // ERROR_INVALID_NAME (123) e o shell não nasce — o PTY abre, o
        // conhost sobe e a aba fica eternamente vazia. O POSIX tolerava
        // porque o lado nativo já testava `strlen > 0` antes do chdir.
        ..workingDirectory = (spec.workingDirectory?.isNotEmpty ?? false)
            ? spec.workingDirectory!.toNativeUtf8(allocator: arena).cast()
            : nullptr
        ..stdoutPort = stdoutPort.sendPort.nativePort
        ..exitPort = exitPort.sendPort.nativePort
        ..ackRead = spec.flowControlled;

      handle = _bindings.create(options);
    } finally {
      arena.releaseAll();
    }

    if (handle == nullptr) {
      stdoutPort.close();
      exitPort.close();
      final err = _bindings.error();
      throw TerminalException(
        TerminalErrorKind.spawnFailed,
        err == nullptr ? null : err.cast<Utf8>().toDartString(),
      );
    }

    final session = _Session(
      info: PtySessionInfo(
        id: id,
        pid: _bindings.getPid(handle),
        executable: executable,
        rows: spec.rows,
        columns: spec.columns,
        scrollbackLength: 0,
      ),
      handle: handle,
      stdoutPort: stdoutPort,
      exitPort: exitPort,
      scrollback: ScrollbackBuffer(capacity: scrollbackCapacity),
    );
    session.flowControlled = spec.flowControlled;
    _sessions[id] = session;

    stdoutPort.listen((data) {
      final bytes = data as Uint8List;
      final offset = session.scrollback.totalLength;
      session.scrollback.add(bytes);
      session.info = _withLength(session.info, session.scrollback.totalLength);
      session.live.add(
        PtyOutputEvent(PtyOutputChunk(offset: offset, bytes: bytes)),
      );
      if (session.flowControlled) {
        // Janela de créditos: libera a próxima leitura nativa enquanto houver
        // orçamento; sem consumidor anexado a leitura corre livre (o
        // scrollback é o destino, como uma sessão detached de tmux).
        session.outstanding += bytes.length;
        if (session.consumers == 0 || session.outstanding < flowWindow) {
          _bindings.ackRead(session.handle);
        } else {
          session.nativeAckPending = true;
        }
      }
    });

    exitPort.listen((code) {
      session.info = _withExit(session.info, code as int);
      session.live.add(PtyExitEvent(code));
      session.stdoutPort.close();
      session.exitPort.close();
    });

    return session.info;
  }

  @override
  Future<List<PtySessionInfo>> sessions() async => [
    for (final s in _sessions.values) s.info,
  ];

  @override
  Future<void> ack(String sessionId, int bytes) async {
    final session = _sessions[sessionId];
    if (session == null || !session.flowControlled) return;
    session.outstanding = (session.outstanding - bytes).clamp(0, 1 << 62);
    if (session.nativeAckPending && session.outstanding < flowWindow) {
      session.nativeAckPending = false;
      _bindings.ackRead(session.handle);
    }
  }

  @override
  Stream<PtyEvent> attach(String sessionId, {int fromOffset = 0}) {
    final session = _session(sessionId);

    late StreamController<PtyEvent> controller;
    StreamSubscription<PtyEvent>? liveSub;
    controller = StreamController<PtyEvent>(
      onListen: () {
        session.consumers++;
        // Replay do scrollback retido; o live já está assinado ANTES da
        // leitura para não perder chunks entre replay e assinatura — o
        // filtro por offset descarta o que o replay já cobriu.
        final replay = session.scrollback.read(fromOffset: fromOffset);
        final replayEnd = replay.offset + replay.bytes.length;
        liveSub = session.live.stream.listen((event) {
          if (event is PtyOutputEvent && event.chunk.offset < replayEnd) {
            return;
          }
          controller.add(event);
        }, onDone: controller.close);
        if (replay.bytes.isNotEmpty) {
          controller.add(
            PtyOutputEvent(
              PtyOutputChunk(offset: replay.offset, bytes: replay.bytes),
            ),
          );
        }
        final exit = session.info.exitCode;
        if (exit != null) controller.add(PtyExitEvent(exit));
      },
      onCancel: () {
        final wasAttached = liveSub != null;
        if (wasAttached) {
          session.consumers--;
          if (session.flowControlled && session.consumers == 0) {
            // Último consumidor saiu: zera a contabilidade e destrava a
            // leitura nativa (modo detached corre livre pro scrollback).
            session.outstanding = 0;
            if (session.nativeAckPending) {
              session.nativeAckPending = false;
              _bindings.ackRead(session.handle);
            }
          }
        }
        return liveSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> write(String sessionId, Uint8List data) async {
    final session = _session(sessionId);
    final arena = Arena();
    try {
      final buffer = arena<Uint8>(data.length);
      buffer.asTypedList(data.length).setAll(0, data);
      _bindings.write(session.handle, buffer.cast(), data.length);
    } finally {
      arena.releaseAll();
    }
  }

  @override
  Future<void> resize(String sessionId, int rows, int columns) async {
    final session = _session(sessionId);
    _bindings.resize(session.handle, rows, columns);
    session.info = _withSize(session.info, rows, columns);
  }

  @override
  Future<void> kill(String sessionId) async {
    final session = _session(sessionId);
    _sessions.remove(sessionId);
    if (session.info.isAlive) {
      // `pty_kill` PRIMEIRO, e não `Process.killPid`: no Windows o kill do Dart
      // vira `TerminateProcess`, que encerra só o shell e deixa os filhos dele
      // (e o conhost do ConPTY) órfãos em "Processos em segundo plano" — issue
      // #163. O nativo alcança a árvore inteira (Job Object no Windows, process
      // group no POSIX).
      //
      // O nativo já existia desde a correção da #163, mas ESTE caminho nunca o
      // chamava: a correção mexeu no `Pty.kill()` do plugin Flutter, e desde
      // que o PTY passou a nascer no sidecar (plano 58) quem encerra sessão é
      // este serviço. Resultado: no Windows o bug seguia vivo com o fix no
      // repositório — verificado em máquina real, com um `ping -t` sobrevivendo
      // ao fechamento da aba.
      final killTree = _bindings.kill;
      if (killTree == null || killTree(session.handle) != 0) {
        // Dylib velha (sem o símbolo) ou falha do nativo: o comportamento
        // antigo ainda é melhor do que não matar nada.
        Process.killPid(session.info.pid, ProcessSignal.sigkill);
      }
    }
    session.stdoutPort.close();
    session.exitPort.close();
    await session.live.close();
  }

  @override
  Future<void> dispose() async {
    for (final id in _sessions.keys.toList()) {
      await kill(id);
    }
  }

  _Session _session(String id) {
    final session = _sessions[id];
    if (session == null) {
      throw TerminalException(TerminalErrorKind.sessionNotFound, id);
    }
    return session;
  }

  static Pointer<Pointer<Char>> _stringArray(Arena arena, List<String> items) {
    final array = arena<Pointer<Char>>(items.length + 1);
    for (var i = 0; i < items.length; i++) {
      array[i] = items[i].toNativeUtf8(allocator: arena).cast();
    }
    array[items.length] = nullptr;
    return array;
  }

  static PtySessionInfo _withLength(PtySessionInfo info, int length) =>
      PtySessionInfo(
        id: info.id,
        pid: info.pid,
        executable: info.executable,
        rows: info.rows,
        columns: info.columns,
        scrollbackLength: length,
        exitCode: info.exitCode,
      );

  static PtySessionInfo _withExit(PtySessionInfo info, int code) =>
      PtySessionInfo(
        id: info.id,
        pid: info.pid,
        executable: info.executable,
        rows: info.rows,
        columns: info.columns,
        scrollbackLength: info.scrollbackLength,
        exitCode: code,
      );

  static PtySessionInfo _withSize(PtySessionInfo info, int rows, int columns) =>
      PtySessionInfo(
        id: info.id,
        pid: info.pid,
        executable: info.executable,
        rows: rows,
        columns: columns,
        scrollbackLength: info.scrollbackLength,
        exitCode: info.exitCode,
      );
}

/// Shell padrão de um host Windows quando o cliente pede "o login shell do
/// host". Espelha o fallback local do `TerminalProfileResolverImpl`: `cmd` no
/// Windows ARM (o PTY do PowerShell ainda é instável lá), PowerShell no resto.
/// `%COMSPEC%` entra como último recurso, por ser o único caminho que o próprio
/// SO garante.
String _windowsDefaultShell() {
  if (Platform.version.toLowerCase().contains('arm')) {
    final comspec = Platform.environment['COMSPEC']?.trim();
    return (comspec != null && comspec.isNotEmpty) ? comspec : 'cmd.exe';
  }
  return 'powershell.exe';
}
