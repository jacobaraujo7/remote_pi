import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/contracts/automation_gateway.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/exceptions/automation_error.dart';
import 'package:cockpit/app/core/domain/services/automation_model_catalog.dart';
import 'package:cockpit/app/core/domain/services/commit_message_prompt.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';

class CliAutomationGateway implements AutomationGateway {
  CliAutomationGateway({this.timeout = const Duration(seconds: 60)});

  /// Isolamento do Pi. **A mesma lista vale para descoberta e geração** — foi
  /// justamente o descompasso que quebrou o harness: a descoberta listava os
  /// modelos do provider `antigravity` (registrado por uma extensão npm) e a
  /// geração rodava com `--no-extensions`, derrubando o provider e devolvendo
  /// `Model "antigravity/…" not found`. Sem `--no-extensions` aqui: as tools
  /// continuam desligadas por `--no-tools`, então extensão carregada não
  /// reintroduz risco de escrita.
  static const List<String> piIsolationFlags = <String>[
    '--no-session',
    '--no-tools',
    '--no-skills',
    '--no-context-files',
    '--no-approve',
  ];

  final Duration timeout;
  Process? _activeProcess;
  bool _cancelRequested = false;

  @override
  Future<List<AutomationHarness>> discover() async {
    final discovered = await Future.wait(
      HarnessKind.values.map(_discoverHarness),
    );
    return discovered.whereType<AutomationHarness>().toList();
  }

  Future<AutomationHarness?> _discoverHarness(HarnessKind id) async {
    try {
      final executable = await _resolve(id);
      if (!await isExecutableAvailable(executable)) return null;
      return AutomationHarness(
        id: id,
        executablePath: executable,
        models: await _discoverModels(id, executable),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _resolve(HarnessKind id) => resolveExecutable(
    id.executableName,
    unixHomeRelative: id.unixHomeRelativeCandidates,
  );

  Future<List<AutomationModel>> _discoverModels(
    HarnessKind id,
    String executable,
  ) async {
    // Harness sem catálogo vinculado à conta não oferece escolha: o Copilot
    // fica no roteador `auto` (obrigatório em planos restritos) e o Claude Code
    // no modelo que o próprio CLI já tem configurado.
    if (!id.hasAccountScopedModels) {
      final pinned = id.pinnedModelId;
      return pinned == null
          ? const <AutomationModel>[]
          : <AutomationModel>[AutomationModel(id: pinned, label: 'Auto')];
    }
    try {
      final discovered = switch (id) {
        HarnessKind.pi => parsePiModels(
          await _runForDiscovery(executable, const [
            ...piIsolationFlags,
            '--list-models',
          ]),
        ),
        HarnessKind.codex => await _discoverCodexModels(executable),
        HarnessKind.openCode => parseOpenCodeModels(
          await _runForDiscovery(executable, const ['models']),
        ),
        HarnessKind.cursor => parseCursorModels(
          await _runForDiscovery(executable, const ['models']),
        ),
        HarnessKind.antigravity => parseAgyModels(
          await _runForDiscovery(executable, const ['models']),
        ),
        HarnessKind.claudeCode ||
        HarnessKind.gitHubCopilot => const <AutomationModel>[],
      };
      return AutomationModelCatalog.curate(discovered);
    } catch (_) {
      // Descoberta é best-effort. Sem catálogo confiável o harness fica no
      // default do próprio CLI, que é sempre compatível com o plano — melhor
      // do que oferecer uma lista curada à mão que envelhece.
      return const <AutomationModel>[];
    }
  }

  Future<String> _runForDiscovery(String executable, List<String> args) async {
    final result = await Process.run(
      executable,
      args,
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) return '';
    return result.stdout?.toString() ?? '';
  }

  Future<List<AutomationModel>> _discoverCodexModels(String executable) async {
    final process = await Process.start(
      executable,
      const ['app-server'],
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    );
    unawaited(process.stderr.drain<void>());
    final result = Completer<List<AutomationModel>>();
    late final StreamSubscription<String> subscription;
    subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final value = jsonDecode(line);
            if (value is! Map) return;
            if (value['id'] == 1) {
              process.stdin.writeln(jsonEncode({'method': 'initialized'}));
              process.stdin.writeln(
                jsonEncode({
                  'method': 'model/list',
                  'id': 2,
                  'params': {'limit': 100, 'includeHidden': false},
                }),
              );
            } else if (value['id'] == 2 && !result.isCompleted) {
              final data = (value['result'] as Map?)?['data'];
              final models = <AutomationModel>[];
              if (data is List) {
                for (final raw in data.whereType<Map>()) {
                  final id = raw['id']?.toString().trim() ?? '';
                  if (id.isEmpty) continue;
                  models.add(
                    AutomationModel(
                      id: id,
                      label:
                          raw['displayName']?.toString().trim().isNotEmpty ==
                              true
                          ? raw['displayName'].toString().trim()
                          : id,
                    ),
                  );
                }
              }
              result.complete(models);
            }
          } catch (_) {
            // Linhas que não sejam respostas JSON-RPC são ignoradas.
          }
        });
    process.stdin.writeln(
      jsonEncode({
        'method': 'initialize',
        'id': 1,
        'params': {
          'clientInfo': {'name': 'Cockpit', 'version': '1'},
        },
      }),
    );
    try {
      return await result.future.timeout(const Duration(seconds: 20));
    } finally {
      await subscription.cancel();
      process.kill();
    }
  }

  @override
  Future<GeneratedCommitMessage> generate({
    required AutomationSelection selection,
    required AutomationRequest request,
  }) async {
    if (_activeProcess != null) {
      throw const AutomationError(AutomationErrorKind.busy);
    }
    // Zerado **antes** do primeiro await: resolver o executável e escrever o
    // system prompt do codex leva tempo suficiente para o usuário cancelar, e
    // reciclar a flag depois desses awaits descartava esse cancel — o CLI
    // acabava spawnado mesmo com a UI já de volta ao estado ocioso.
    _cancelRequested = false;
    final harnessId = selection.harnessId;
    final executable = await _resolve(harnessId);
    if (!await isExecutableAvailable(executable)) {
      throw AutomationError(
        AutomationErrorKind.unavailable,
        harness: harnessId.label,
      );
    }

    // Diretório descartável: system prompt do Codex e, no Copilot, o
    // `COPILOT_HOME` inteiro (a CLI não tem flag de "não persistir sessão").
    Directory? scratch;
    String? codexSystemPromptPath;
    final environment = Map<String, String>.of(await envWithNodeOnPath());
    if (harnessId == HarnessKind.codex ||
        harnessId == HarnessKind.gitHubCopilot) {
      scratch = await Directory.systemTemp.createTemp('cockpit_commit_');
      if (harnessId == HarnessKind.codex) {
        final systemPromptFile = File(
          '${scratch.path}${Platform.pathSeparator}SYSTEM.md',
        );
        await systemPromptFile.writeAsString(CommitMessagePrompt.systemPrompt);
        codexSystemPromptPath = systemPromptFile.path;
      } else {
        environment['COPILOT_HOME'] = scratch.path;
      }
    }

    final command = buildCommand(
      selection,
      request.prompt,
      codexSystemPromptPath: codexSystemPromptPath,
      timeout: timeout,
    );
    if (_cancelRequested) {
      await _deleteTemporaryDirectory(scratch);
      throw const AutomationError(AutomationErrorKind.cancelled);
    }
    Process process;
    try {
      process = await Process.start(
        executable,
        command.args,
        workingDirectory: request.repositoryPath,
        environment: environment,
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (error) {
      await _deleteTemporaryDirectory(scratch);
      throw AutomationError(
        AutomationErrorKind.unavailable,
        harness: harnessId.label,
        cause: error,
      );
    }
    _activeProcess = process;

    try {
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      if (command.stdin != null) process.stdin.write(command.stdin);
      await process.stdin.close();

      final exitCode = await process.exitCode.timeout(timeout);
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      if (_cancelRequested) {
        throw const AutomationError(AutomationErrorKind.cancelled);
      }
      if (exitCode != 0) throw processError(harnessId, stderr, stdout);
      final message = parseOutput(harnessId, stdout);
      if (message.isEmpty) {
        // O OpenCode reporta falha em stdout e ainda sai com 0: sem olhar ali,
        // o usuário só via "mensagem vazia" sem motivo.
        if (errorFromStdout(stdout) != null) {
          throw processError(harnessId, '', stdout);
        }
        throw const AutomationError(AutomationErrorKind.invalidResponse);
      }
      // Convenções (72 chars, ponto final, …) viram aviso — o rascunho fica
      // editável. Só mensagem vazia é hard-fail acima.
      return GeneratedCommitMessage(
        message: message,
        warning: CommitMessagePrompt.validate(message),
      );
    } on TimeoutException catch (error) {
      process.kill();
      throw AutomationError(
        AutomationErrorKind.timeout,
        harness: harnessId.label,
        timeoutSeconds: timeout.inSeconds,
        cause: error,
      );
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
      await _deleteTemporaryDirectory(scratch);
    }
  }

  static ({List<String> args, String? stdin}) buildCommand(
    AutomationSelection selection,
    String prompt, {
    String? codexSystemPromptPath,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final harnessId = selection.harnessId;
    final model = (harnessId.pinnedModelId ?? selection.modelId)?.trim();
    final modelArgs = model == null || model.isEmpty
        ? const <String>[]
        : <String>['--model', model];
    final promptWithInstructions = CommitMessagePrompt.withSystemPrompt(prompt);
    return switch (harnessId) {
      HarnessKind.pi => (
        args: <String>[
          '-p',
          '--mode',
          'json',
          ...piIsolationFlags,
          '--system-prompt',
          CommitMessagePrompt.systemPrompt,
          ...modelArgs,
          prompt,
        ],
        stdin: null,
      ),
      HarnessKind.claudeCode => (
        args: <String>[
          '-p',
          '--output-format',
          'json',
          '--tools',
          '',
          '--no-session-persistence',
          '--disable-slash-commands',
          '--system-prompt',
          CommitMessagePrompt.systemPrompt,
          ...modelArgs,
        ],
        stdin: prompt,
      ),
      HarnessKind.codex => (
        args: <String>[
          'exec',
          '--ephemeral',
          '--sandbox',
          'read-only',
          '--skip-git-repo-check',
          '--json',
          '-c',
          'model_instructions_file=${jsonEncode(_requiredCodexSystemPromptPath(codexSystemPromptPath))}',
          ...modelArgs,
          '-',
        ],
        stdin: prompt,
      ),
      // O `run` re-envolve cada argumento posicional em aspas literais e escapa
      // as internas — o diff chegava corrompido no modelo. Por stdin o texto
      // passa intacto.
      HarnessKind.openCode => (
        args: <String>[
          'run',
          '--format',
          'json',
          '--agent',
          'plan',
          ...modelArgs,
        ],
        stdin: promptWithInstructions,
      ),
      // `--trust` só pula o prompt "confia nesta pasta?", que em modo
      // não-interativo aborta o run; quem impede escrita é `--mode ask`
      // (Q&A read-only).
      HarnessKind.cursor => (
        args: <String>[
          '-p',
          '--output-format',
          'json',
          '--mode',
          'ask',
          '--trust',
          ...modelArgs,
          promptWithInstructions,
        ],
        stdin: null,
      ),
      // Diferente do pi e do cursor-agent, aqui `-p` **recebe** o prompt
      // (`flag needs an argument: -p`) em vez de ligar o modo print e ler um
      // posicional.
      HarnessKind.antigravity => (
        args: <String>[
          '-p',
          promptWithInstructions,
          '--output-format',
          'json',
          '--mode',
          'plan',
          // Sem `--disable-slash-commands`: a própria CLI avisa que
          // "--mode plan has no effect while slash command expansion is
          // disabled", e o modo read-only vale mais aqui do que bloquear a
          // expansão.
          '--print-timeout',
          '${timeout.inSeconds}s',
          ...modelArgs,
        ],
        stdin: null,
      ),
      // `-s` só esconde o rodapé de estatísticas; o isolamento real vem de
      // `--available-tools` sem valores (o modelo não enxerga tool nenhuma).
      // `--allow-all-tools` é exigido pelo modo não-interativo e, sem tools
      // visíveis, não concede nada na prática.
      HarnessKind.gitHubCopilot => (
        args: <String>[
          '-p',
          promptWithInstructions,
          '--output-format',
          'json',
          '--stream',
          'off',
          '--allow-all-tools',
          '--available-tools',
          '--disable-builtin-mcps',
          '--no-custom-instructions',
          '--no-ask-user',
          '--no-remote-export',
          '--no-auto-update',
          '--no-color',
          '--log-level',
          'none',
          ...modelArgs,
        ],
        stdin: null,
      ),
    };
  }

  static String _requiredCodexSystemPromptPath(String? path) {
    if (path == null || path.isEmpty) {
      throw ArgumentError(
        'codexSystemPromptPath is required for the Codex harness.',
      );
    }
    return path;
  }

  static Future<void> _deleteTemporaryDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup must not hide the automation result.
    }
  }

  static String parseOutput(HarnessKind id, String stdout) {
    String message;
    switch (id) {
      case HarnessKind.claudeCode:
      case HarnessKind.cursor:
      case HarnessKind.antigravity:
        message = _resultField(stdout);
      case HarnessKind.pi:
        message = _lastJsonText(stdout, pi: true);
      case HarnessKind.codex:
        message = _lastJsonText(stdout, codex: true);
      case HarnessKind.openCode:
        message = _lastJsonText(stdout, openCode: true);
      case HarnessKind.gitHubCopilot:
        message = _lastJsonText(stdout, copilot: true);
    }
    return normalizeCommitMessage(message);
  }

  /// Alguns CLIs obedecem ao conteúdo mas ainda envolvem a resposta inteira
  /// em um fence. Desembrulhamos apenas esse caso inequívoco; Markdown misturado
  /// à mensagem continua sendo rejeitado pelo validador.
  static String normalizeCommitMessage(String raw) {
    var value = raw
        .replaceAll('\r\n', '\n')
        .replaceFirst(RegExp(r'^commit message:\s*', caseSensitive: false), '')
        .trim();
    final fenced = RegExp(
      r'^```[^\n]*\n([\s\S]*?)\n```[ \t]*$',
    ).firstMatch(value);
    if (fenced != null) value = fenced.group(1)!.trim();
    return value;
  }

  static Object? _decodeSingleJson(String value) {
    try {
      return jsonDecode(value.trim());
    } catch (_) {
      return null;
    }
  }

  /// Claude Code, cursor-agent e agy convergiram no mesmo envelope: um objeto
  /// `{"type":"result", "result": "<texto>"}`. Alguns emitem o objeto sozinho,
  /// outros no fim de um NDJSON — cobrimos os dois.
  static String _resultField(String stdout) {
    final single = _decodeSingleJson(stdout);
    if (single is Map) {
      final value = single['result'] ?? single['response'];
      if (value is String) return value;
    }
    var result = '';
    for (final line in stdout.split('\n')) {
      final raw = _decodeSingleJson(line);
      if (raw is! Map) continue;
      final value = raw['result'] ?? raw['response'];
      if (value is String && value.isNotEmpty) result = value;
    }
    return result;
  }

  static String _lastJsonText(
    String stdout, {
    bool pi = false,
    bool codex = false,
    bool openCode = false,
    bool copilot = false,
  }) {
    var result = '';
    for (final line in stdout.split('\n')) {
      final raw = _decodeSingleJson(line);
      if (raw is! Map) continue;
      if (pi && raw['type'] == 'message_end') {
        // O Pi fecha a mensagem do **usuário** com um `message_end` também —
        // sem filtrar o papel, o prompt inteiro viraria a mensagem de commit
        // se o turno terminasse sem resposta.
        final message = raw['message'] as Map?;
        if (message?['role'] == 'user') continue;
        result = _contentText(message?['content']);
      } else if (codex && raw['type'] == 'item.completed') {
        final item = raw['item'];
        if (item is Map && item['type'] == 'agent_message') {
          result = item['text']?.toString() ?? '';
        }
      } else if (openCode && raw['type'] == 'text') {
        // Só o evento `text`: `tool_use`/`step_*` também carregam um `part`, e
        // concatenar todos misturava passos intermediários na mensagem.
        final part = raw['part'];
        final candidate = part is Map ? part['text']?.toString() : null;
        if (candidate != null && candidate.isNotEmpty) result += candidate;
      } else if (copilot) {
        final candidate = _copilotText(raw);
        if (candidate != null && candidate.isNotEmpty) result = candidate;
      }
    }
    return result;
  }

  /// JSONL do Copilot: um envelope `{type, data, id, timestamp}` por linha. A
  /// resposta vem em `assistant.message` → `data.content`; os demais eventos
  /// (`user.message`, `assistant.reasoning`, `session.*`, `result`) são ruído
  /// de sessão. O `result` final só traz `exitCode`/`usage`, sem texto.
  static String? _copilotText(Map<dynamic, dynamic> raw) {
    if (raw['type'] != 'assistant.message') return null;
    final data = raw['data'];
    if (data is! Map) return null;
    final content = data['content'];
    if (content is String) return content;
    return _contentText(content);
  }

  static String _contentText(Object? content) {
    if (content is String) return content;
    if (content is! List) return '';
    return content
        .whereType<Map>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text']?.toString() ?? '')
        .join();
  }

  static List<AutomationModel> parsePiModels(String output) {
    final models = <AutomationModel>[];
    for (final line in output.split('\n').skip(1)) {
      final columns = line.trim().split(RegExp(r'\s{2,}'));
      if (columns.length < 2 || columns[0].isEmpty || columns[1].isEmpty) {
        continue;
      }
      final id = '${columns[0]}/${columns[1]}';
      models.add(AutomationModel(id: id, label: id));
    }
    return _uniqueModels(models);
  }

  static List<AutomationModel> parseOpenCodeModels(String output) {
    return _uniqueModels([
      for (final line in output.split('\n'))
        if (RegExp(r'^[^\s/]+/[^\s]+$').hasMatch(line.trim()))
          AutomationModel(id: line.trim(), label: line.trim()),
    ]);
  }

  /// `cursor-agent models` → `slug - Nome legível` (uma linha por modelo, com
  /// um cabeçalho "Available models" que não casa com o padrão).
  static List<AutomationModel> parseCursorModels(String output) {
    final pattern = RegExp(r'^(\S+) - (.+)$');
    return _uniqueModels([
      for (final line in output.split('\n'))
        if (pattern.firstMatch(line.trim()) case final match?)
          AutomationModel(
            id: match.group(1)!,
            // "auto - Auto (default)" → o sufixo é ruído no menu.
            label: match
                .group(2)!
                .replaceFirst(RegExp(r'\s*\(default\)$'), '')
                .trim(),
          ),
    ]);
  }

  /// `agy models` → `slug\tNome legível`, precedido de "Fetching available
  /// models...". Sempre usar a **primeira** coluna: o settings.json do agy
  /// guarda o display name, mas o `--model` só aceita o slug.
  static List<AutomationModel> parseAgyModels(String output) {
    final models = <AutomationModel>[];
    for (final line in output.split('\n')) {
      final columns = line.trimRight().split(RegExp(r'\t+|\s{2,}'));
      if (columns.length < 2) continue;
      final id = columns[0].trim();
      final label = columns[1].trim();
      if (id.isEmpty || label.isEmpty || id.contains(' ')) continue;
      models.add(AutomationModel(id: id, label: label));
    }
    return _uniqueModels(models);
  }

  static List<AutomationModel> _uniqueModels(List<AutomationModel> values) {
    final byId = <String, AutomationModel>{};
    for (final value in values) {
      byId[value.id] = value;
    }
    return byId.values.toList();
  }

  /// Erro reportado em **stdout**. O OpenCode escreve
  /// `{"type":"error","error":{…}}` na saída padrão e deixa stderr vazio —
  /// lendo só stderr o usuário recebia "mensagem vazia" sem motivo nenhum.
  static String? errorFromStdout(String stdout) {
    for (final line in stdout.split('\n')) {
      final raw = _decodeSingleJson(line);
      if (raw is! Map) continue;
      if (raw['type']?.toString().contains('error') != true) continue;
      final error = raw['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
      if (error is Map) {
        for (final key in const ['message', 'name', 'data']) {
          final value = error[key];
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
        return jsonEncode(error);
      }
    }
    return null;
  }

  static AutomationError processError(
    HarnessKind id,
    String stderr,
    String stdout,
  ) {
    final raw = stderr.trim().isEmpty
        ? (errorFromStdout(stdout) ?? '')
        : stderr;
    final clean = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final detail = clean.length > 300 ? '${clean.substring(0, 300)}…' : clean;
    final lower = clean.toLowerCase();
    final authentication = const [
      'auth',
      'login',
      'credential',
      'subscription',
      'api key',
    ].any(lower.contains);
    return AutomationError(
      authentication
          ? AutomationErrorKind.authentication
          : AutomationErrorKind.process,
      harness: id.label,
      detail: detail,
    );
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeProcess?.kill();
  }

  @override
  Future<void> close() async => cancel();
}
