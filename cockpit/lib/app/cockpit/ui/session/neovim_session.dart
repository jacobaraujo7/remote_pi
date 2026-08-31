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
           ],
         ),
         title: 'Neovim',
       ) {
    restoreManualLabel('Neovim');
  }

  final NeovimGateway neovimGateway;
  final String executable;
  final String serverAddress;
  String lastPath;
  int? lastLine;

  Future<bool> isAlive() => neovimGateway.isAlive(executable, serverAddress);

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
