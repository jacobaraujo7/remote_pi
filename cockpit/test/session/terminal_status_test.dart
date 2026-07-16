import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TerminalGateway] inerte — não sobe PTY nenhum; só satisfaz o construtor da
/// [TerminalSession] pra testar a máquina de status de turno isoladamente.
class _NoopGateway implements TerminalGateway {
  final _out = StreamController<List<int>>();

  @override
  Stream<List<int>> get output => _out.stream;
  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {}
  @override
  void write(List<int> data) {}
  @override
  void resize(int rows, int columns) {}
  @override
  Future<void> kill() async {
    await _out.close();
  }
}

TerminalSession _session() => TerminalSession(
  id: 't1',
  projectId: 'p1',
  workingDirectory: '/tmp',
  gateway: _NoopGateway(),
  profile: const TerminalProfile(
    id: 'login-shell',
    label: 'sh (login)',
    executable: '/bin/sh',
    args: ['-l'],
  ),
);

void main() {
  group('TerminalSession — status de turno (spinner)', () {
    test('working → idle: spinner liga e desliga', () async {
      final s = _session();
      expect(s.isWorking, isFalse);

      s.applyClaudeStatus(
        status: TerminalStatus.working,
        isTurnStart: true,
      ); // UserPromptSubmit
      expect(s.isWorking, isTrue);

      s.applyClaudeStatus(status: TerminalStatus.idle); // Stop
      expect(s.isWorking, isFalse);
      await s.dispose();
    });

    test(
      'FIX: working mid-turn reordenado que chega DEPOIS do idle é descartado',
      () async {
        final s = _session();
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        s.applyClaudeStatus(status: TerminalStatus.idle); // Stop → idle
        expect(s.isWorking, isFalse);

        // PostToolUse('working') do MESMO turno, entregue fora de ordem depois do
        // Stop (processos/sockets separados). Sem o guard, o spinner voltaria e
        // ficaria girando pra sempre.
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: false);
        expect(
          s.isWorking,
          isFalse,
          reason: 'working mid-turn órfão pós-idle deve ser ignorado',
        );
        await s.dispose();
      },
    );

    test(
      'follow-up enfileirado (UserPromptSubmit) logo após idle LIGA o spinner',
      () async {
        final s = _session();
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        s.applyClaudeStatus(status: TerminalStatus.idle);
        expect(s.isWorking, isFalse);

        // Turno novo (não é reordenação): isTurnStart pula o guard.
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        expect(s.isWorking, isTrue);
        await s.dispose();
      },
    );

    test('working mid-turn DENTRO de um turno ativo é aceito', () async {
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      // PreToolUse volta a idle? não — segue working. Simula waiting→working:
      s.applyClaudeStatus(status: TerminalStatus.waiting); // Notification
      expect(s.isWorking, isFalse);
      // Aprovou → PreToolUse('working') com turno ainda ativo → volta a working.
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: false);
      expect(s.isWorking, isTrue);
      await s.dispose();
    });
  });
}
