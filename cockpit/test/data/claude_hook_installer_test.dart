import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes repeated Windows CLI hooks and preserves user hooks', () async {
    final home = await Directory.systemTemp.createTemp('cockpit-hook-test-');
    addTearDown(() async {
      if (await home.exists()) await home.delete(recursive: true);
    });
    final config = File('${home.path}/.claude/settings.json');
    await config.parent.create(recursive: true);
    final legacy = <String>[
      ...List.filled(5, r'C:/Users/test/.cockpit/bin/cockpit.exe hook'),
      r'"C:/Program Files/Cockpit/cockpit.exe" hook --harness claude',
      r'C:\Users\test\.cockpit\bin\cockpit.exe hook',
    ];
    await config.writeAsString(
      jsonEncode({
        'hooks': {
          'Stop': [
            for (final command in legacy)
              {
                'matcher': '',
                'hooks': [
                  {'type': 'command', 'command': command},
                ],
              },
            {
              'matcher': '',
              'hooks': [
                {'type': 'command', 'command': 'echo user-hook'},
              ],
            },
          ],
        },
      }),
    );

    const installer = ClaudeHookInstallerImpl();
    Future<List<dynamic>> stopGroups() async {
      final root = jsonDecode(await config.readAsString()) as Map;
      final hooks = root['hooks'] as Map;
      return hooks['Stop'] as List;
    }

    await installer.writeConfig(
      home: home.path,
      command: r'C:/Users/test/.cockpit/bin/cockpit.exe hook',
    );
    var groups = await stopGroups();
    expect(groups, hasLength(2));
    expect(jsonEncode(groups), contains('echo user-hook'));
    expect(jsonEncode(groups), contains('"_cockpit":"v1"'));

    await installer.writeConfig(
      home: home.path,
      command: r'C:/Users/test/.cockpit/bin/cockpit.exe hook',
    );
    groups = await stopGroups();
    expect(groups, hasLength(2));
  });
}
