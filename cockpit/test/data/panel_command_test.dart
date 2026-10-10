import 'package:cockpit/app/cockpit/data/panel/panel_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exec ganha --cwd da pasta do host', () {
    expect(
      injectExecCwd('exec docker ps', '/root/app'),
      'exec --cwd /root/app docker ps',
    );
    expect(
      injectExecCwd('exec --json -- hostname', '/root/app'),
      'exec --cwd /root/app --json -- hostname',
    );
  });

  test('caminho com espaço vai entre aspas', () {
    expect(
      injectExecCwd('exec ls', '/home/u/my app'),
      'exec --cwd "/home/u/my app" ls',
    );
  });

  test('--cwd explícito e outros verbos passam intactos', () {
    expect(
      injectExecCwd('exec --cwd /tmp ls', '/root/app'),
      'exec --cwd /tmp ls',
    );
    expect(
      injectExecCwd('db query main "select 1"', '/root/app'),
      'db query main "select 1"',
    );
    expect(injectExecCwd('execute x', '/root/app'), 'execute x');
  });
}
