// Bindings FFI mínimos do cockpit_pty para Dart puro (Wave 0, plano 58).
//
// Escritos à mão (a API são 6 funções + init) para não depender do pacote
// Flutter `cockpit_pty` — o layout do struct segue `src/cockpit_pty.h`.
import 'dart:ffi';

final class PtyOptionsNative extends Struct {
  @Int32()
  external int rows;

  @Int32()
  external int cols;

  external Pointer<Char> executable;

  /// Array NULL-terminated; convenção execvp: argv[0] = executable.
  external Pointer<Pointer<Char>> arguments;

  /// Array NULL-terminated de "CHAVE=valor".
  external Pointer<Pointer<Char>> environment;

  external Pointer<Char> workingDirectory;

  @Int64()
  external int stdoutPort;

  @Int64()
  external int exitPort;

  @Bool()
  external bool ackRead;
}

typedef PtyInitC = IntPtr Function(Pointer<Void>);
typedef PtyInitDart = int Function(Pointer<Void>);
typedef PtyCreateC = Pointer<Void> Function(Pointer<PtyOptionsNative>);
typedef PtyWriteC = Void Function(Pointer<Void>, Pointer<Char>, Int32);
typedef PtyWriteDart = void Function(Pointer<Void>, Pointer<Char>, int);
typedef PtyResizeC = Int32 Function(Pointer<Void>, Int32, Int32);
typedef PtyResizeDart = int Function(Pointer<Void>, int, int);
typedef PtyGetPidC = Int32 Function(Pointer<Void>);
typedef PtyGetPidDart = int Function(Pointer<Void>);
typedef PtyAckReadC = Void Function(Pointer<Void>);
typedef PtyAckReadDart = void Function(Pointer<Void>);
typedef PtyKillC = Int32 Function(Pointer<Void>);
typedef PtyKillDart = int Function(Pointer<Void>);
typedef PtyErrorC = Pointer<Char> Function();

class PtyBindings {
  PtyBindings(DynamicLibrary lib)
    : initializeApiDL = lib.lookupFunction<PtyInitC, PtyInitDart>(
        'Dart_InitializeApiDL',
      ),
      create = lib.lookupFunction<PtyCreateC, PtyCreateC>('pty_create'),
      write = lib.lookupFunction<PtyWriteC, PtyWriteDart>('pty_write'),
      resize = lib.lookupFunction<PtyResizeC, PtyResizeDart>('pty_resize'),
      getPid = lib.lookupFunction<PtyGetPidC, PtyGetPidDart>('pty_getpid'),
      ackRead = lib.lookupFunction<PtyAckReadC, PtyAckReadDart>('pty_ack_read'),
      error = lib.lookupFunction<PtyErrorC, PtyErrorC>('pty_error'),
      kill = _lookupKill(lib);

  /// `pty_kill` é OPCIONAL na resolução: uma dylib anterior à issue #163 não
  /// exporta o símbolo, e um `lookupFunction` direto lançaria no construtor —
  /// derrubando o serviço de terminais inteiro por causa de uma função de
  /// encerramento. Ausente, o chamador cai no `Process.killPid` de antes.
  static PtyKillDart? _lookupKill(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<PtyKillC, PtyKillDart>('pty_kill');
    } on ArgumentError {
      return null;
    }
  }

  final PtyInitDart initializeApiDL;
  final PtyCreateC create;
  final PtyWriteDart write;
  final PtyResizeDart resize;
  final PtyGetPidDart getPid;
  final PtyAckReadDart ackRead;

  /// `null` quando a dylib carregada é anterior à issue #163 (ver [_lookupKill]).
  final PtyKillDart? kill;

  final PtyErrorC error;
}
