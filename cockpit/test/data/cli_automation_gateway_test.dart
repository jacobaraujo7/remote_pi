import 'package:cockpit/app/core/data/automation/cli_automation_gateway.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/services/commit_message_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'builds read-only ephemeral Codex command and sends prompt over stdin',
    () {
      const selection = AutomationSelection(
        harnessId: HarnessKind.codex,
        modelId: 'gpt-5.4-mini',
      );

      final command = CliAutomationGateway.buildCommand(
        selection,
        'prompt',
        codexSystemPromptPath: '/tmp/cockpit-system.md',
      );

      expect(
        command.args,
        containsAll(['--ephemeral', '--sandbox', 'read-only']),
      );
      expect(command.args, containsAll(['--model', 'gpt-5.4-mini']));
      expect(
        command.args,
        contains('model_instructions_file="/tmp/cockpit-system.md"'),
      );
      expect(command.stdin, 'prompt');
    },
  );

  test('replaces supported harness system prompts', () {
    final pi = CliAutomationGateway.buildCommand(
      const AutomationSelection(harnessId: HarnessKind.pi),
      'repository context',
    );
    final claude = CliAutomationGateway.buildCommand(
      const AutomationSelection(harnessId: HarnessKind.claudeCode),
      'repository context',
    );

    for (final command in [pi, claude]) {
      final flag = command.args.indexOf('--system-prompt');
      expect(flag, isNonNegative);
      expect(command.args[flag + 1], CommitMessagePrompt.systemPrompt);
    }
    expect(pi.args.last, 'repository context');
    expect(claude.stdin, 'repository context');
  });

  test('keeps instructions in prompts for harnesses without an override', () {
    for (final id in const [
      HarnessKind.openCode,
      HarnessKind.cursor,
      HarnessKind.antigravity,
      HarnessKind.gitHubCopilot,
    ]) {
      final command = CliAutomationGateway.buildCommand(
        AutomationSelection(harnessId: id),
        'repository context',
      );
      final instructed = CommitMessagePrompt.withSystemPrompt(
        'repository context',
      );
      expect(
        command.stdin ?? command.args.join('\n'),
        contains(instructed),
        reason: '$id must carry the system prompt in the user prompt',
      );
    }
  });

  test('Pi discovery and generation share the same isolation flags', () {
    // O bug: a descoberta listava os modelos do provider `antigravity` (que é
    // registrado por uma extensão) e a geração rodava com `--no-extensions`,
    // derrubando o provider — o CLI respondia "Model not found" para um id que
    // o próprio Cockpit tinha oferecido.
    final generation = CliAutomationGateway.buildCommand(
      const AutomationSelection(
        harnessId: HarnessKind.pi,
        modelId: 'antigravity/gemini-3.7-flash',
      ),
      'prompt',
    );

    expect(
      CliAutomationGateway.piIsolationFlags,
      isNot(contains('--no-extensions')),
    );
    expect(generation.args, isNot(contains('--no-extensions')));
    for (final flag in CliAutomationGateway.piIsolationFlags) {
      expect(generation.args, contains(flag));
    }
    expect(generation.args, containsAll(['--no-tools', '--no-session']));
  });

  test('OpenCode takes the prompt over stdin and stays read-only', () {
    // `opencode run` re-envolve cada posicional em aspas literais e escapa as
    // internas — o diff chegava corrompido. Por stdin passa intacto.
    final command = CliAutomationGateway.buildCommand(
      const AutomationSelection(
        harnessId: HarnessKind.openCode,
        modelId: 'opencode/big-pickle',
      ),
      'diff with "quotes" and spaces',
    );

    expect(command.stdin, contains('diff with "quotes" and spaces'));
    expect(command.args, containsAll(['run', '--format', 'json']));
    expect(command.args, containsAll(['--agent', 'plan']));
    expect(command.args, containsAll(['--model', 'opencode/big-pickle']));
    expect(command.args.last, isNot(contains('diff with')));
  });

  test('Copilot is pinned to auto and runs without tools', () {
    // Plano restrito (Student) só libera o roteador automático: um id fixo
    // escolhido pelo usuário quebraria na chamada.
    final command = CliAutomationGateway.buildCommand(
      const AutomationSelection(
        harnessId: HarnessKind.gitHubCopilot,
        modelId: 'claude-opus-5',
      ),
      'prompt',
    );

    final model = command.args.indexOf('--model');
    expect(model, isNonNegative);
    expect(command.args[model + 1], kAutomationAutoModelId);
    expect(command.args, contains('--available-tools'));
    expect(
      command.args,
      containsAll(['--no-custom-instructions', '--disable-builtin-mcps']),
    );
    expect(command.args, containsAll(['--output-format', 'json']));
  });

  test('cursor-agent and agy run in read-only modes', () {
    final cursor = CliAutomationGateway.buildCommand(
      const AutomationSelection(harnessId: HarnessKind.cursor, modelId: 'auto'),
      'prompt',
    );
    final agy = CliAutomationGateway.buildCommand(
      const AutomationSelection(
        harnessId: HarnessKind.antigravity,
        modelId: 'gemini-3.7-flash-low',
      ),
      'prompt',
      timeout: const Duration(seconds: 90),
    );

    expect(cursor.args, containsAll(['--mode', 'ask']));
    expect(cursor.args, containsAll(['--output-format', 'json']));
    // Sem `--trust` o cursor-agent aborta em pasta não confiada, e em modo
    // não-interativo não há como responder ao prompt de confiança.
    expect(cursor.args, contains('--trust'));
    expect(agy.args, containsAll(['--mode', 'plan']));
    // A CLI avisa que `--mode plan` não vale junto com esta flag.
    expect(agy.args, isNot(contains('--disable-slash-commands')));
    expect(agy.args, containsAll(['--print-timeout', '90s']));
    expect(agy.args, containsAll(['--model', 'gemini-3.7-flash-low']));
  });

  test('parses provider-specific structured outputs', () {
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.claudeCode,
        '{"result":"fix: claude output"}',
      ),
      'fix: claude output',
    );
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.claudeCode,
        '{"result":"```gitcommit\\nrefactor: unwrap Claude output\\n```"}',
      ),
      'refactor: unwrap Claude output',
    );
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.cursor,
        '{"type":"result","subtype":"success","is_error":false,'
        '"result":"fix: cursor output"}',
      ),
      'fix: cursor output',
    );
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.antigravity,
        '{"type":"system","subtype":"init"}\n'
        '{"type":"result","result":"fix: agy output"}\n',
      ),
      'fix: agy output',
    );
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.codex,
        '{"type":"item.completed","item":{"type":"agent_message","text":"fix: codex output"}}',
      ),
      'fix: codex output',
    );
    expect(
      CliAutomationGateway.parseOutput(
        HarnessKind.pi,
        '{"type":"message_end","message":{"content":[{"type":"text","text":"fix: pi output"}]}}',
      ),
      'fix: pi output',
    );
  });

  test('Copilot output takes the assistant message, not session noise', () {
    // Envelope real da CLI: um evento JSONL por linha, resposta em
    // `assistant.message` → `data.content`.
    const stdout =
        '{"type":"session.skills_loaded","data":{"skills":[]}}\n'
        '{"type":"user.message","data":{"content":"the prompt"}}\n'
        '{"type":"assistant.reasoning","data":{"content":"thinking out loud"}}\n'
        '{"type":"assistant.message","data":{"model":"gpt-5-mini",'
        '"content":"docs: add troubleshooting section","toolRequests":[]}}\n'
        '{"type":"result","exitCode":0,"usage":{"premiumRequests":0}}\n';

    expect(
      CliAutomationGateway.parseOutput(HarnessKind.gitHubCopilot, stdout),
      'docs: add troubleshooting section',
    );
  });

  test('OpenCode output keeps only assistant text events', () {
    const stdout =
        '{"type":"step_start","sessionID":"s","part":{"text":"thinking"}}\n'
        '{"type":"tool_use","sessionID":"s","part":{"text":"ran a tool"}}\n'
        '{"type":"text","sessionID":"s","part":{"text":"fix: opencode "}}\n'
        '{"type":"text","sessionID":"s","part":{"text":"output"}}\n'
        '{"type":"step_finish","sessionID":"s","part":{}}\n';

    expect(
      CliAutomationGateway.parseOutput(HarnessKind.openCode, stdout),
      'fix: opencode output',
    );
  });

  test('surfaces OpenCode errors reported on stdout', () {
    // O OpenCode escreve a falha em stdout e deixa stderr vazio: lendo só
    // stderr, o usuário recebia "mensagem vazia" sem motivo nenhum.
    const stdout =
        '{"type":"error","sessionID":"s",'
        '"error":{"name":"ProviderAuthError","message":"missing credentials"}}\n';

    expect(CliAutomationGateway.errorFromStdout(stdout), 'missing credentials');
    final error = CliAutomationGateway.processError(
      HarnessKind.openCode,
      '',
      stdout,
    );
    expect(error.detail, 'missing credentials');
    expect(error.harness, 'OpenCode');
  });

  test('parses model discovery output', () {
    final pi = CliAutomationGateway.parsePiModels(
      'provider  model  context  max-out\nopenai  gpt-5  200000  32000\n',
    );
    final openCode = CliAutomationGateway.parseOpenCodeModels(
      'anthropic/claude-sonnet-4\ninvalid line\n',
    );
    final cursor = CliAutomationGateway.parseCursorModels(
      'Available models\n\nauto - Auto (default)\n'
      'claude-opus-5-low - Claude Opus 5 1M Low\n',
    );
    final agy = CliAutomationGateway.parseAgyModels(
      'Fetching available models...\n'
      'gemini-3.7-flash-low\tGemini 3.7 Flash (Low)\n'
      'claude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)\n',
    );

    expect(pi.single.id, 'openai/gpt-5');
    expect(openCode.single.id, 'anthropic/claude-sonnet-4');
    expect(cursor.first.id, 'auto');
    expect(cursor.first.label, 'Auto');
    expect(cursor.last.id, 'claude-opus-5-low');
    expect(agy.map((model) => model.id), [
      'gemini-3.7-flash-low',
      'claude-sonnet-4-6',
    ]);
    expect(agy.first.label, 'Gemini 3.7 Flash (Low)');
  });

  test('harnesses without an account catalog do not offer a model choice', () {
    // Nenhuma das duas CLIs sabe dizer o que o plano do usuário libera fora do
    // modo interativo, então o Cockpit não inventa uma lista.
    expect(HarnessKind.claudeCode.hasAccountScopedModels, isFalse);
    expect(HarnessKind.gitHubCopilot.hasAccountScopedModels, isFalse);
    expect(HarnessKind.gitHubCopilot.pinnedModelId, kAutomationAutoModelId);
    expect(HarnessKind.claudeCode.pinnedModelId, isNull);

    const copilot = AutomationHarness(
      id: HarnessKind.gitHubCopilot,
      executablePath: '/usr/bin/copilot',
      models: [AutomationModel(id: kAutomationAutoModelId, label: 'Auto')],
    );
    expect(copilot.allowsModelChoice, isFalse);
    expect(copilot.defaultModelId, kAutomationAutoModelId);

    const claude = AutomationHarness(
      id: HarnessKind.claudeCode,
      executablePath: '/usr/bin/claude',
    );
    expect(claude.allowsModelChoice, isFalse);
    expect(claude.defaultModelId, isNull);
  });

  test('redacts credentials and validates generated messages', () {
    final prompt = CommitMessagePrompt.build(
      'diff --git a/app.dart b/app.dart\n+api_key=secret-value',
      const ['feat: recent'],
    );

    expect(prompt, isNot(contains('secret-value')));
    expect(prompt, contains('[sensitive line redacted by Cockpit]'));
    expect(prompt, isNot(contains('intent and meaningful outcome')));
    expect(
      CommitMessagePrompt.systemPrompt,
      contains('intent and meaningful outcome'),
    );
    expect(CommitMessagePrompt.systemPrompt, contains('1–3 lines'));
    expect(CommitMessagePrompt.validate('fix: safe subject'), isNull);
    expect(CommitMessagePrompt.validate('fix: invalid.'), isNotNull);
    expect(CommitMessagePrompt.validate('fix: invalid.'), contains('period'));
  });
}
