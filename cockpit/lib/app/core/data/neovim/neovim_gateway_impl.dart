import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/exceptions/neovim_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';

class NeovimGatewayImpl implements NeovimGateway {
  String? _cachedExecutable;
  bool _didProbe = false;

  static const Duration _timeout = Duration(seconds: 3);

  @override
  Future<String?> executable({bool refresh = false}) async {
    if (_didProbe && !refresh) return _cachedExecutable;
    _didProbe = true;
    final resolved = await resolveExecutable(
      'nvim',
      unixCandidates: const [
        '/opt/homebrew/bin/nvim',
        '/usr/local/bin/nvim',
        '/usr/bin/nvim',
      ],
    );
    _cachedExecutable = await isExecutableAvailable(resolved) ? resolved : null;
    return _cachedExecutable;
  }

  @override
  String serverAddress(String workspaceId) {
    final token = _fnv1a(workspaceId).toRadixString(16);
    final name = 'cockpit-nvim-${pid.toRadixString(16)}-$token';
    return Platform.isWindows ? r'\\.\pipe\' + name : '/tmp/$name.sock';
  }

  @override
  Future<void> prepareServer(String address) async {
    if (Platform.isWindows) return;
    final socket = File(address);
    try {
      if (await socket.exists()) await socket.delete();
    } on FileSystemException {
      // O spawn do Neovim produzirá um erro visível se o endereço estiver de
      // fato ocupado. Limpeza aqui é apenas best-effort para sockets mortos.
    }
  }

  @override
  Future<Result<void, NeovimError>> openRemote(
    String executable,
    String address,
    String path, {
    int? line,
  }) async {
    final opened = await _run(executable, [
      '--server',
      address,
      '--remote',
      path,
    ]);
    if (opened case Failure(:final error)) return Failure(error);
    if (line == null) return const Success(null);

    // O `+{cmd}` documentado para Vim ainda não é suportado pelo `--remote`
    // do Neovim: depois de `--remote`, tudo vira nome de arquivo. Posicionamos
    // o cursor numa segunda chamada RPC, já com o buffer trazido por `:drop`.
    final revealed = await _run(executable, [
      '--server',
      address,
      '--remote-expr',
      'cursor($line, 1)',
    ]);
    return switch (revealed) {
      Success() => const Success(null),
      Failure(:final error) => Failure(error),
    };
  }

  @override
  Future<bool> isAlive(String executable, String address) async {
    final result = await _run(executable, [
      '--server',
      address,
      '--remote-expr',
      '1',
    ]);
    return result is Success<ProcessResult, NeovimError>;
  }

  @override
  Future<Result<bool, NeovimError>> hasModifiedBuffers(
    String executable,
    String address,
  ) async {
    final result = await _run(executable, [
      '--server',
      address,
      '--remote-expr',
      "len(filter(getbufinfo(), 'v:val.changed'))",
    ]);
    return switch (result) {
      Success(:final value) => Success(
        (int.tryParse('${value.stdout}'.trim()) ?? 0) > 0,
      ),
      Failure(:final error) => Failure(error),
    };
  }

  Future<Result<ProcessResult, NeovimError>> _run(
    String executable,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(executable, args).timeout(_timeout);
      if (result.exitCode == 0) return Success(result);
      final detail = '${result.stderr}'.trim();
      return Failure(
        NeovimError(
          NeovimErrorKind.connectionFailed,
          detail: detail.isEmpty ? null : detail,
        ),
      );
    } on TimeoutException {
      return const Failure(NeovimError(NeovimErrorKind.timeout));
    } on ProcessException catch (error) {
      return Failure(
        NeovimError(NeovimErrorKind.unavailable, detail: error.message),
      );
    }
  }

  /// FNV-1a 64-bit determinístico: evita caminhos longos/ilegais de worktrees.
  int _fnv1a(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash;
  }
}
