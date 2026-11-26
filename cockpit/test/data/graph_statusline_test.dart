import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/hooks/terminal_status_server_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Claude status line is installed without replacing user config',
    () async {
      final home = await Directory.systemTemp.createTemp('graph-claude-hook-');
      addTearDown(() => home.delete(recursive: true));
      final installer = ClaudeHookInstallerImpl();
      await installer.writeConfig(home: home.path, command: 'cockpit hook');
      final file = File('${home.path}/.claude/settings.json');
      var settings =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect((settings['statusLine'] as Map)['command'], 'cockpit statusline');
      expect((settings['hooks'] as Map).keys, containsAll(['SubagentStart', 'SubagentStop']));
      settings['statusLine'] = {'type': 'command', 'command': 'my-status'};
      await file.writeAsString(jsonEncode(settings));
      await installer.writeConfig(home: home.path, command: 'cockpit hook');
      settings = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect((settings['statusLine'] as Map)['command'], 'my-status');
    },
  );

  test('metric payload preserves turn state channel', () async {
    final updates = <ClaudeStatusUpdate>[];
    final server = TerminalStatusServerImpl();
    await server.start(updates.add);
    addTearDown(server.stop);
    final env = server.hookEnv;
    expect(env, isNotEmpty);
    final payload = jsonEncode({
      'type': 'metric',
      'paneId': 'tab-1',
      'ct': 900,
      'cw': 200000,
      'tok': env['COCKPIT_STATUS_TOKEN'],
    });
    final socket = env['COCKPIT_STATUS_PORT'] == null
        ? await Socket.connect(
            InternetAddress(
              env['COCKPIT_STATUS_SOCK']!,
              type: InternetAddressType.unix,
            ),
            0,
          )
        : await Socket.connect(
            '127.0.0.1',
            int.parse(env['COCKPIT_STATUS_PORT']!),
          );
    socket.write('$payload\n');
    await socket.flush();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(updates, hasLength(1));
    expect(updates.single.status, 'metric');
    expect(updates.single.contextTokens, 900);
    expect(updates.single.contextWindow, 200000);
  });

  test('subagent lifecycle keeps identity and parent tab', () async {
    final updates = <ClaudeStatusUpdate>[];
    final server = TerminalStatusServerImpl();
    await server.start(updates.add);
    addTearDown(server.stop);
    final env = server.hookEnv;
    final socket = env['COCKPIT_STATUS_PORT'] == null
        ? await Socket.connect(
            InternetAddress(
              env['COCKPIT_STATUS_SOCK']!,
              type: InternetAddressType.unix,
            ),
            0,
          )
        : await Socket.connect(
            '127.0.0.1',
            int.parse(env['COCKPIT_STATUS_PORT']!),
          );
    socket.write(
      '${jsonEncode({'paneId': 'tab-main', 'st': 'subagent_start', 'ev': 'SubagentStart', 'aid': 'child-1', 'at': 'Explore', 'hn': 'claude', 'ts': 1780000000000, 'tok': env['COCKPIT_STATUS_TOKEN']})}\n',
    );
    await socket.flush();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(updates, hasLength(1));
    expect(updates.single.paneId, 'tab-main');
    expect(updates.single.status, 'subagent_start');
    expect(updates.single.subagentId, 'child-1');
    expect(updates.single.subagentType, 'Explore');
    expect(updates.single.eventAt?.millisecondsSinceEpoch, 1780000000000);
  });

  test('Claude message metadata reaches graph without message body', () async {
    final updates = <ClaudeStatusUpdate>[];
    final server = TerminalStatusServerImpl();
    await server.start(updates.add);
    addTearDown(server.stop);
    final env = server.hookEnv;
    final socket = env['COCKPIT_STATUS_PORT'] == null
        ? await Socket.connect(
            InternetAddress(
              env['COCKPIT_STATUS_SOCK']!,
              type: InternetAddressType.unix,
            ),
            0,
          )
        : await Socket.connect(
            '127.0.0.1',
            int.parse(env['COCKPIT_STATUS_PORT']!),
          );
    socket.write(
      '${jsonEncode({'paneId': 'tab-a', 'st': 'working', 'ev': 'PostToolUse', 'hn': 'claude', 'gm': 'backend-17', 'tok': env['COCKPIT_STATUS_TOKEN']})}\n',
    );
    await socket.flush();
    await socket.close();
    final identitySocket = env['COCKPIT_STATUS_PORT'] == null
        ? await Socket.connect(
            InternetAddress(
              env['COCKPIT_STATUS_SOCK']!,
              type: InternetAddressType.unix,
            ),
            0,
          )
        : await Socket.connect(
            '127.0.0.1',
            int.parse(env['COCKPIT_STATUS_PORT']!),
          );
    identitySocket.write(
      '${jsonEncode({'paneId': 'tab-b', 'st': 'working', 'ev': 'PostToolUse', 'hn': 'claude', 'gi': 'backend-17', 'tok': env['COCKPIT_STATUS_TOKEN']})}\n',
    );
    await identitySocket.flush();
    await identitySocket.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(updates, hasLength(2));
    expect(updates.first.graphRecipient, 'backend-17');
    expect(updates.last.graphSelfName, 'backend-17');
  });
}
