import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/domain/exceptions/neovim_error.dart';

/// TUI do Neovim hospedada no terminal do Cockpit, com servidor RPC próprio.
class NeovimSession extends TerminalSession {
  NeovimSession({
    required super.id,
    required super.projectId,
    required super.workingDirectory,
    required TerminalGateway terminalGateway,
    required this.neovimGateway,
    required this.executable,
    required this.serverAddress,
    required this.lastPath,
    this.lastLine,
    required super.engine,
  }) : super(
         gateway: terminalGateway,
         profile: TerminalProfile(
           id: 'cockpit-neovim',
           label: 'Neovim',
           executable: executable,
           args: [
             '--listen',
             serverAddress,
             if (lastLine != null) '+$lastLine',
             lastPath,
             '-c',
             activeBufferCommand,
           ],
         ),
         title: 'Neovim',
       ) {
    restoreManualLabel('Neovim');
    terminal.onTitleChanged = _handleTerminalTitle;
  }

  static const _pathTitlePrefix = 'cockpit-nvim:';

  /// Instalado depois do vimrc. O payload JSON evita ambiguidades em paths com
  /// espaços, Unicode, aspas ou barras e a OSC 2 funciona nos dois motores de
  /// terminal usados pelo Cockpit.
  static const activeBufferCommand =
      "lua local function cockpit_path() local p=vim.api.nvim_buf_get_name(0); "
      "io.stdout:write(string.char(27)..']2;cockpit-nvim:'..vim.fn.json_encode(p)..string.char(7)); "
      "io.stdout:flush() end; vim.api.nvim_create_autocmd('BufEnter',{callback=cockpit_path}); cockpit_path()";

  final NeovimGateway neovimGateway;
  final String executable;
  final String serverAddress;
  String lastPath;
  int? lastLine;
  void Function(String path)? onActivePathChanged;

  void _handleTerminalTitle(String title) {
    if (!title.startsWith(_pathTitlePrefix)) return;
    final payload = title.substring(_pathTitlePrefix.length);
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! String || decoded.isEmpty) return;
      lastPath = decoded;
      lastLine = null;
      notifyListeners();
      onActivePathChanged?.call(decoded);
    } on FormatException {
      // Títulos normais ou payloads truncados não pertencem ao protocolo.
    }
  }

  Future<bool> isAlive() => neovimGateway.isAlive(executable, serverAddress);

  /// Sincroniza a PTY e a grade interna do editor. Só redesenhar pode manter
  /// os 80x25 iniciais quando o sinal de resize chega durante o startup.
  Future<void> synchronizeDisplay() async {
    await synchronizeViewport();
    final size = viewportSize;
    await neovimGateway.redraw(
      executable,
      serverAddress,
      columns: size?.columns,
      rows: size?.rows,
    );
  }

  Future<Result<bool, NeovimError>> hasModifiedBuffers() =>
      neovimGateway.hasModifiedBuffers(executable, serverAddress);

  Future<Result<void, NeovimError>> open(String path, {int? line}) async {
    final result = await neovimGateway.openRemote(
      executable,
      serverAddress,
      path,
      line: line,
    );
    if (result.isSuccess) {
      lastPath = path;
      lastLine = line;
      notifyListeners();
    }
    return result;
  }
}
