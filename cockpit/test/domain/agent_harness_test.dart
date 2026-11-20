import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentHarness.resumeCommand', () {
    test('cada harness tem a própria sintaxe de resume', () {
      // Regressão: o restore mandava `claude --resume <id>` para qualquer id.
      // Com um id do Codex isso morre em "No conversation found with session ID".
      const id = '019ff255-62c9-7ba1-8481-63c8803ef51e';
      expect(AgentHarness.claude.resumeCommand(id), 'claude --resume $id');
      expect(
        AgentHarness.codex.resumeCommand(id),
        'codex resume $id --no-daemon',
      );
    });
  });

  test('Codex launches and restores use the terminal-specific server', () {
    expect(AgentHarness.codex.launchCommand, 'codex --no-daemon');
    expect(
      AgentHarness.codex.resumeCommand('latest'),
      'codex resume --last --no-daemon',
    );
    expect(AgentHarness.claude.launchCommand, 'claude');
    expect(AgentHarness.pi.launchCommand, 'pi');
  });

  group('AgentHarness.fromWire', () {
    test('reconhece os nomes do wire', () {
      expect(AgentHarness.fromWire('claude'), AgentHarness.claude);
      expect(AgentHarness.fromWire('codex'), AgentHarness.codex);
    });

    test('ausente ou desconhecido cai em claude (compat)', () {
      // Layout salvo antes desta distinção, ou helper antigo sem `--harness`:
      // nos dois casos só o Claude tinha hooks instalados.
      expect(AgentHarness.fromWire(null), AgentHarness.claude);
      expect(AgentHarness.fromWire(''), AgentHarness.claude);
      expect(AgentHarness.fromWire('gemini'), AgentHarness.claude);
    });
  });
}
