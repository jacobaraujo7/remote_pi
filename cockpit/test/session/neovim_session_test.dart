import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/neovim_session.dart';
import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/exceptions/neovim_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:flutter_test/flutter_test.dart';

class _TerminalGateway implements TerminalGateway {
  TerminalProfile? profile;
  final sizes = <(int, int)>[];

  @override
  int? get rootProcessId => null;

  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  Stream<List<int>> get output => const Stream.empty();

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const {},
  }) {
    this.profile = profile;
  }

  @override
  void resize(int rows, int columns) => sizes.add((rows, columns));

  @override
  void write(List<int> data) {}

  @override
  void acknowledgeOutput() {}

  @override
  Future<void> kill() async {}
}

class _NeovimGateway implements NeovimGateway {
  int redraws = 0;
  ({int? columns, int? rows})? size;

  @override
  Future<String?> executable({bool refresh = false}) async => '/usr/bin/nvim';

  @override
  Future<Result<bool, NeovimError>> hasModifiedBuffers(
    String executable,
    String address,
  ) async => const Success(false);

  @override
  Future<bool> isAlive(String executable, String address) async => true;

  @override
  Future<Result<void, NeovimError>> redraw(
    String executable,
    String address, {
    int? columns,
    int? rows,
  }) async {
    redraws++;
    size = (columns: columns, rows: rows);
    return const Success(null);
  }

  @override
  Future<Result<void, NeovimError>> openRemote(
    String executable,
    String address,
    String path, {
    int? line,
  }) async => const Success(null);

  @override
  Future<void> prepareServer(String address) async {}

  @override
  String serverAddress(String workspaceId) => 'nvim-$workspaceId';
}

void main() {
  late _TerminalGateway terminalGateway;
  late NeovimSession session;

  setUp(() {
    terminalGateway = _TerminalGateway();
    session = NeovimSession(
      id: 'n1',
      projectId: 'p1',
      workingDirectory: '/workspace',
      terminalGateway: terminalGateway,
      neovimGateway: _NeovimGateway(),
      executable: '/usr/bin/nvim',
      serverAddress: '/tmp/nvim.sock',
      lastPath: '/workspace/first.dart',
      engine: TerminalEngine.xterm,
    );
  });

  tearDown(() => session.dispose());

  test('installs the active-buffer autocmd in Neovim', () {
    expect(
      terminalGateway.profile!.args,
      containsAllInOrder(['-c', NeovimSession.activeBufferCommand]),
    );
  });

  test('reports JSON encoded paths from terminal title events', () {
    final paths = <String>[];
    session.onActivePathChanged = paths.add;
    const path = '/workspace/área/a "quoted" file.dart';
    final controller = session.terminal as XtermTerminalController;

    controller.terminal.write(
      '\u001b]2;cockpit-nvim:${jsonEncode(path)}\u0007',
    );

    expect(paths, [path]);
    expect(session.lastPath, path);
    expect(session.lastLine, isNull);
  });

  test('reapplies the measured viewport to the PTY', () async {
    final controller = session.terminal as XtermTerminalController;
    controller.terminal.resize(132, 48);
    terminalGateway.sizes.clear();

    await session.synchronizeViewport();

    expect(terminalGateway.sizes, [(48, 132)]);
  });

  test('redraws Neovim after synchronizing the viewport', () async {
    final controller = session.terminal as XtermTerminalController;
    controller.terminal.resize(132, 48);
    final neovim = session.neovimGateway as _NeovimGateway;

    await session.synchronizeDisplay();

    expect(terminalGateway.sizes.last, (48, 132));
    expect(neovim.redraws, 1);
    expect(neovim.size, (columns: 132, rows: 48));
  });

  test('waits for layout before synchronizing Neovim', () async {
    final neovim = session.neovimGateway as _NeovimGateway;
    final pending = session.synchronizeDisplay();
    expect(neovim.redraws, 0);

    final controller = session.terminal as XtermTerminalController;
    controller.terminal.resize(166, 58);
    await pending;

    expect(neovim.size, (columns: 166, rows: 58));
    expect(terminalGateway.sizes.last, (58, 166));
  });
}
