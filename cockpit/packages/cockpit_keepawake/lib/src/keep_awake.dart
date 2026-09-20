import 'dart:io';

import 'package:win32/win32.dart' as win32;

/// Segura o sleep por inatividade do sistema enquanto [acquire] estiver de pé.
///
/// Contrato comum às plataformas:
/// - efêmero: nada persiste; morrer o processo = soltar (nos POSIX o filho
///   vigia o pid do pai e sai sozinho; no Windows o estado é da thread);
/// - idempotente: `acquire` duas vezes = uma; `release` sem `acquire` = no-op;
/// - nunca lança por falta de ferramenta: [isSupported] diz se a plataforma
///   tem implementação, e um `acquire` que falhe deixa [isActive] em `false`.
abstract class KeepAwake {
  /// Implementação da plataforma atual; [UnsupportedKeepAwake] fora do desktop
  /// (iPad/Android nunca são host, então nem mostram o botão).
  factory KeepAwake.platform() {
    if (Platform.isMacOS) return MacKeepAwake();
    if (Platform.isWindows) return WindowsKeepAwake();
    if (Platform.isLinux) return LinuxKeepAwake();
    return const UnsupportedKeepAwake();
  }

  bool get isSupported;
  bool get isActive;

  /// Passa a segurar. Devolve `true` se está segurando ao final (inclusive se
  /// já estava).
  Future<bool> acquire();

  Future<void> release();
}

class UnsupportedKeepAwake implements KeepAwake {
  const UnsupportedKeepAwake();
  @override
  bool get isSupported => false;
  @override
  bool get isActive => false;
  @override
  Future<bool> acquire() async => false;
  @override
  Future<void> release() async {}
}

/// Base dos POSIX: a assertion é um **processo filho** que vive enquanto o
/// Cockpit vive. Soltar = matar o filho. Se o Cockpit morrer sem soltar, o
/// filho percebe (`-w pid` no macOS, loop `kill -0` no Linux) e sai.
abstract class _ChildProcessKeepAwake implements KeepAwake {
  Process? _child;

  @override
  bool get isSupported => true;

  @override
  bool get isActive => _child != null;

  /// Comando + args que seguram o sleep até serem mortos ou até [pid] sumir.
  List<String> command(int pid);

  @override
  Future<bool> acquire() async {
    if (_child != null) return true;
    final cmd = command(pid);
    try {
      final p = await Process.start(cmd.first, cmd.sublist(1));
      // Ninguém lê a saída; drenar evita pipe cheio bloqueando o filho.
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      _child = p;
      // Filho que morre por conta própria (ferramenta ausente no PATH, por
      // exemplo) solta o estado sem ninguém chamar release.
      p.exitCode.then((_) {
        if (identical(_child, p)) _child = null;
      });
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<void> release() async {
    final p = _child;
    if (p == null) return;
    _child = null;
    p.kill(ProcessSignal.sigterm);
  }
}

/// macOS: `caffeinate -i` cria `PreventUserIdleSystemSleep` (a tela pode
/// apagar). `-w <pid>` faz o caffeinate sair sozinho quando o Cockpit morre.
/// Aparece em `pmset -g assertions` como o processo `caffeinate`.
class MacKeepAwake extends _ChildProcessKeepAwake {
  @override
  List<String> command(int pid) => ['caffeinate', '-i', '-w', '$pid'];
}

/// Linux: `systemd-inhibit --what=sleep:idle --mode=block` segura enquanto o
/// comando filho viver; o filho é um loop que vigia o pid do Cockpit. Em
/// distro sem systemd o binário falta e o `acquire` devolve `false`.
class LinuxKeepAwake extends _ChildProcessKeepAwake {
  @override
  List<String> command(int pid) => [
    'systemd-inhibit',
    '--what=sleep:idle',
    '--who=Cockpit',
    '--why=Remote access (keep awake)',
    '--mode=block',
    'sh',
    '-c',
    'while kill -0 $pid 2>/dev/null; do sleep 5; done',
  ];
}

/// Windows: `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`.
/// É estado da **thread** que chamou, então as duas chamadas precisam sair da
/// mesma isolate (a main). Sem filho: o processo morrer já limpa.
class WindowsKeepAwake implements KeepAwake {
  bool _active = false;

  @override
  bool get isSupported => true;

  @override
  bool get isActive => _active;

  @override
  Future<bool> acquire() async {
    if (_active) return true;
    final prev = win32.SetThreadExecutionState(
      win32.ES_CONTINUOUS | win32.ES_SYSTEM_REQUIRED,
    );
    _active = prev != 0;
    return _active;
  }

  @override
  Future<void> release() async {
    if (!_active) return;
    _active = false;
    win32.SetThreadExecutionState(win32.ES_CONTINUOUS);
  }
}
