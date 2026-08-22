import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/automation_gateway.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/exceptions/automation_error.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements AutomationGateway {
  List<AutomationHarness> discovered = const <AutomationHarness>[];
  Completer<GeneratedCommitMessage>? generation;
  int discoverCalls = 0;
  bool cancelled = false;

  @override
  Future<List<AutomationHarness>> discover() async {
    discoverCalls++;
    return discovered;
  }

  @override
  Future<GeneratedCommitMessage> generate({
    required AutomationSelection selection,
    required AutomationRequest request,
  }) =>
      generation?.future ??
      Future.value(
        const GeneratedCommitMessage(message: 'fix: generated message'),
      );

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  const harness = AutomationHarness(
    id: HarnessKind.codex,
    executablePath: '/usr/bin/codex',
    models: [
      AutomationModel(id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra'),
      AutomationModel(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
    ],
  );
  const selection = AutomationSelection(harnessId: HarnessKind.codex);
  const request = AutomationRequest(prompt: 'prompt', repositoryPath: '/repo');

  test('discovers installed harnesses and exposes them by id', () async {
    final gateway = _Gateway()..discovered = const [harness];
    final controller = AutomationController(gateway);

    await controller.refresh();

    expect(controller.initialized, isTrue);
    expect(controller.harnessFor(HarnessKind.codex), harness);
    expect(controller.discovering, isFalse);
    controller.dispose();
  });

  test('ensureInitialized discovers once and generate awaits it', () async {
    final gateway = _Gateway()..discovered = const [harness];
    final controller = AutomationController(gateway);

    await controller.ensureInitialized();
    await controller.ensureInitialized();
    expect(gateway.discoverCalls, 1);

    final result = await controller.generate(
      selection: selection,
      request: request,
    );
    expect(result.isSuccess, isTrue);
    expect(gateway.discoverCalls, 1);
    controller.dispose();
  });

  test('rejects generation when configured harness is unavailable', () async {
    final controller = AutomationController(_Gateway());

    final result = await controller.generate(
      selection: selection,
      request: request,
    );

    expect(result.isFailure, isTrue);
    result.fold<void>((_) => fail('expected failure'), (error) {
      expect(error.kind, AutomationErrorKind.unavailable);
    });
    controller.dispose();
  });

  test('rejects stale model ids before spawning the CLI', () async {
    final gateway = _Gateway()..discovered = const [harness];
    final controller = AutomationController(gateway);
    await controller.refresh();

    final result = await controller.generate(
      selection: const AutomationSelection(
        harnessId: HarnessKind.codex,
        modelId: 'retired-model',
      ),
      request: request,
    );

    expect(result.isFailure, isTrue);
    result.fold<void>((_) => fail('expected failure'), (error) {
      expect(error.kind, AutomationErrorKind.unavailable);
      // O erro carrega os dados, não a frase: quem traduz é a UI.
      expect(error.model, 'retired-model');
      expect(error.harness, 'Codex');
    });
    controller.dispose();
  });

  test('reconcileStaleModel clears unavailable selections', () async {
    final gateway = _Gateway()..discovered = const [harness];
    final controller = AutomationController(gateway);
    await controller.refresh();
    var cleared = false;

    final warning = controller.reconcileStaleModel(
      harnessId: HarnessKind.codex,
      modelId: 'retired-model',
      clearToCliDefault: () => cleared = true,
    );

    expect(cleared, isTrue);
    expect(warning?.model, 'retired-model');
    expect(controller.error?.kind, AutomationErrorKind.unavailable);
    expect(controller.error?.model, 'retired-model');
    controller.dispose();
  });

  test('prevents concurrent generations and forwards cancellation', () async {
    final gateway = _Gateway()
      ..discovered = const [harness]
      ..generation = Completer<GeneratedCommitMessage>();
    final controller = AutomationController(gateway);
    await controller.refresh();

    final first = controller.generate(selection: selection, request: request);
    await Future<void>.delayed(Duration.zero);
    final second = await controller.generate(
      selection: selection,
      request: request,
    );
    expect(second.isFailure, isTrue);

    await controller.cancelGeneration();
    expect(gateway.cancelled, isTrue);
    gateway.generation!.complete(
      const GeneratedCommitMessage(message: 'fix: generated message'),
    );
    expect((await first).isSuccess, isTrue);
    controller.dispose();
  });
}
