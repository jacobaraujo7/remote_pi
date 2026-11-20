import 'dart:async';
import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_fork_builder.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends ChangeNotifier implements TerminalSession {
  @override
  HarnessKind? activeHarness;
  @override
  AgentConversationIdentity? conversationIdentity;
  @override
  int? agentProcessId = 42;
  @override
  bool hasExited = false;
  @override
  String get id => 't1';
  void update() => notifyListeners();
  @override
  Future<void> dispose() async => super.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Vm extends Fake implements CockpitViewModel {
  final probes = <Completer<Result<AgentForkLaunch, AgentForkFailure>>>[];
  final fork = Completer<Result<String, AgentForkFailure>>();
  int invocations = 0;
  @override
  AgentForkProblem? agentForkProblem(TerminalSession source) =>
      source.conversationIdentity == null ? AgentForkProblem.identifying : null;
  @override
  Future<Result<AgentForkLaunch, AgentForkFailure>> prepareAgentFork(
    TerminalSession source,
  ) {
    final result = Completer<Result<AgentForkLaunch, AgentForkFailure>>();
    probes.add(result);
    return result.future;
  }

  @override
  Future<Result<String, AgentForkFailure>> forkAgentInNewTab(String tabId) {
    invocations++;
    return fork.future;
  }
}

void main() {
  testWidgets(
    'visibility follows active agent; pending identity and probe gate clicks',
    (tester) async {
      final session = _Session();
      final vm = _Vm();
      AgentForkAction? action;
      await tester.pumpWidget(
        TranslationProvider(
          child: AgentForkBuilder(
            vm: vm,
            source: session,
            builder: (_, value) {
              action = value;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(action!.visible, isFalse);
      session.activeHarness = HarnessKind.claudeCode;
      session.update();
      await tester.pump();
      expect(action!.visible, isTrue);
      expect(action!.problem, AgentForkProblem.identifying);
      expect(action!.onInvoke, isNull);

      session.conversationIdentity = const AgentConversationIdentity(
        harness: HarnessKind.claudeCode,
        sessionId: 'parent',
        processIds: [42],
      );
      session.update();
      await tester.pump();
      expect(action!.problem, AgentForkProblem.checking);
      vm.probes.single.complete(
        const Success(AgentForkLaunch('claude --resume parent --fork-session')),
      );
      await tester.pumpAndSettle();
      expect(action!.problem, isNull);
      final invoke = action!.onInvoke!;
      invoke();
      invoke();
      await tester.pump();
      expect(vm.invocations, 1);
      expect(action!.busy, isTrue);
      vm.fork.complete(const Success('t2'));
      await tester.pumpAndSettle();
      expect(action!.busy, isFalse);

      session.activeHarness = null;
      session.update();
      await tester.pump();
      expect(action!.visible, isFalse);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'late capability result cannot enable an ended or replaced session',
    (tester) async {
      final session = _Session()
        ..activeHarness = HarnessKind.pi
        ..conversationIdentity = const AgentConversationIdentity(
          harness: HarnessKind.pi,
          sessionId: 'pi-session',
          processIds: [42],
        );
      final vm = _Vm();
      AgentForkAction? action;
      await tester.pumpWidget(
        TranslationProvider(
          child: AgentForkBuilder(
            vm: vm,
            source: session,
            builder: (_, value) {
              action = value;
              return const SizedBox();
            },
          ),
        ),
      );
      session.hasExited = true;
      session.conversationIdentity = null;
      session.update();
      await tester.pump();
      vm.probes.single.complete(
        const Success(AgentForkLaunch('pi --fork pi-session')),
      );
      await tester.pump();
      expect(action!.visible, isFalse);
      expect(action!.onInvoke, isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
