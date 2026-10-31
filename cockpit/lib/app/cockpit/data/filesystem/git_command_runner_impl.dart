import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';

/// Roda comandos `git` via `Process.start` pra **streaming ao vivo** (stdout e
/// stderr mesclados por linha). O caminho do `git` vem do [GitBinary]
/// compartilhado. Não remove worktrees — em um merge bem-sucedido, o
/// `CockpitViewModel` faz a limpeza (reusa `removeWorktree`).
///
/// Todos os spawns passam [envWithNodeOnPath] no `environment`: o app GUI é
/// lançado pelo Finder/Dock com uma PATH mínima (sem `~/.nvm`, Homebrew, etc.),
/// então um **hook de git** (ex.: `pre-commit` chamando `npx`/`node`) falharia
/// com "command not found". Prefixar o bin do `node` cobre `node`/`npm`/`npx`,
/// que moram no mesmo diretório — mesmo tratamento do terminal/tasks/LSP.
class GitCommandRunnerImpl implements GitCommandRunner {
  GitCommandRunnerImpl(this._gitBinary);

  final GitBinary _gitBinary;

  @override
  GitRun run(String repoPath, List<String> args) {
    final controller = StreamController<String>();
    final exitCompleter = Completer<int>();
    _spawn(repoPath, args, controller, header: null).then((code) {
      exitCompleter.complete(code);
      if (!controller.isClosed) controller.close();
    });
    return GitRun(output: controller.stream, exitCode: exitCompleter.future);
  }

  @override
  GitRun syncPullPush(String repoPath) {
    final controller = StreamController<String>();
    final exitCompleter = Completer<int>();
    () async {
      final pull = await _spawn(
        repoPath,
        const ['pull'],
        controller,
        header: r'$ git pull',
      );
      if (pull != 0) {
        exitCompleter.complete(pull);
        if (!controller.isClosed) controller.close();
        return;
      }
      if (!controller.isClosed) controller.add('');
      final push = await _spawn(
        repoPath,
        const ['push'],
        controller,
        header: r'$ git push',
      );
      exitCompleter.complete(push);
      if (!controller.isClosed) controller.close();
    }();
    return GitRun(output: controller.stream, exitCode: exitCompleter.future);
  }

  @override
  GitRun clone(String url, String targetPath) {
    final controller = StreamController<String>();
    final exitCompleter = Completer<int>();
    final parent = Directory(targetPath).parent.path;
    () async {
      final env = cloneProcessEnvironment(
        await envWithNodeOnPath(),
        configuredSshCommand: await _configuredSshCommand(),
      );
      // `--progress` reescreve a mesma linha com `\r` a cada 1%: o dialog
      // empilharia milhares delas. Passa só a cada 10% (e o 100%) por fase.
      final raw = StreamController<String>();
      final throttle = GitProgressThrottle();
      final forward = raw.stream
          .where(throttle.accept)
          .forEach((l) => controller.isClosed ? null : controller.add(l));
      final code = await _spawn(
        parent,
        ['clone', '--progress', '--', url, targetPath],
        raw,
        header: '\$ git clone $url',
        environment: env,
      );
      await raw.close();
      await forward;
      exitCompleter.complete(code);
      if (!controller.isClosed) await controller.close();
    }();
    return GitRun(output: controller.stream, exitCode: exitCompleter.future);
  }

  @override
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  ) {
    final controller = StreamController<String>();
    final statusCompleter = Completer<GitMergeStatus>();

    Future<void> add(String line) async {
      if (!controller.isClosed) controller.add(line);
    }

    () async {
      try {
        // 1. Pré-check: worktree sujo → não faz nada (evita perda de dados).
        if (await _isDirty(worktreePath)) {
          await add(
            'Worktree has uncommitted changes. '
            'Commit or discard changes in this worktree first.',
          );
          statusCompleter.complete(GitMergeStatus.dirtyWorktree);
          return;
        }

        // 2. Merge no checkout do pai (que já está na branch dele).
        final merge = await _spawn(
          parentPath,
          ['merge', worktreeBranch],
          controller,
          header: '\$ git merge $worktreeBranch',
        );
        if (merge != 0) {
          // Conflito → aborta pra deixar o pai intocado.
          await add('');
          await _spawn(
            parentPath,
            const ['merge', '--abort'],
            controller,
            header: r'$ git merge --abort',
          );
          await add('');
          await add('Merge aborted — parent branch untouched.');
          statusCompleter.complete(GitMergeStatus.conflict);
          return;
        }

        // 3. Sucesso — a limpeza do worktree fica a cargo do ViewModel.
        await add('');
        await add('Merge complete.');
        statusCompleter.complete(GitMergeStatus.merged);
      } catch (e) {
        await add('Unexpected error: $e');
        if (!statusCompleter.isCompleted) {
          statusCompleter.complete(GitMergeStatus.error);
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    return GitMergeOutcome(
      status: statusCompleter.future,
      output: controller.stream,
    );
  }

  /// `core.sshCommand` do git config global/sistema do usuário, ou `null`.
  Future<String?> _configuredSshCommand() async {
    try {
      final git = await _gitBinary.resolve();
      final res = await Process.run(git, [
        'config',
        '--get',
        'core.sshCommand',
      ], environment: await envWithNodeOnPath());
      final value = (res.stdout as String).trim();
      return res.exitCode == 0 && value.isNotEmpty ? value : null;
    } catch (_) {
      return null; // git ausente: o clone em si reporta o erro
    }
  }

  /// `true` se o working tree em [path] tem mudanças (staged ou não).
  Future<bool> _isDirty(String path) async {
    final git = await _gitBinary.resolve();
    final res = await Process.run(git, [
      '-C',
      path,
      'status',
      '--porcelain',
    ], environment: await envWithNodeOnPath());
    if (res.exitCode != 0) return false; // não-git → nada a bloquear
    return (res.stdout as String).trim().isNotEmpty;
  }

  /// Spawna `git -C <repoPath> <args>`, encaminha stdout+stderr (por linha) para
  /// [controller] e devolve o exit code. [header] (opcional) é emitido antes da
  /// saída pra marcar a fronteira entre comandos numa sequência.
  /// [environment] substitui o padrão ([envWithNodeOnPath]).
  Future<int> _spawn(
    String repoPath,
    List<String> args,
    StreamController<String> controller, {
    required String? header,
    Map<String, String>? environment,
  }) async {
    if (header != null && !controller.isClosed) controller.add(header);
    try {
      final git = await _gitBinary.resolve();
      final proc = await Process.start(git, [
        '-C',
        repoPath,
        ...args,
      ], environment: environment ?? await envWithNodeOnPath());
      final done = <Future<void>>[];
      for (final stream in [proc.stdout, proc.stderr]) {
        done.add(
          stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .forEach((line) {
                if (!controller.isClosed) controller.add(line);
              }),
        );
      }
      await Future.wait(done);
      return await proc.exitCode;
    } catch (e) {
      if (!controller.isClosed) controller.add('Failed to run git: $e');
      return -1;
    }
  }
}

/// Filtra a saída de `--progress` do git: de cada fase (`Receiving objects`,
/// `remote: Counting objects`...) deixa passar só quando o percentual cruza um
/// novo múltiplo de 10, mais a linha final (`, done.`). Linha que não é
/// progresso passa sempre.
class GitProgressThrottle {
  static final _progress = RegExp(r'^(.*?):\s+(\d{1,3})%');
  final Map<String, int> _lastBucket = {};

  bool accept(String line) {
    final m = _progress.firstMatch(line);
    if (m == null || line.trimRight().endsWith('done.')) return true;
    final phase = m.group(1)!;
    final pct = int.parse(m.group(2)!);
    final bucket = pct >= 100 ? 10 : pct ~/ 10;
    if (_lastBucket[phase] == bucket) return false;
    _lastBucket[phase] = bucket;
    return true;
  }
}

/// SSH sem prompt usado no clone quando o usuário não configurou o dele.
/// `BatchMode` falha em vez de perguntar passphrase/senha; `accept-new` aceita
/// a host key só na PRIMEIRA conexão (github.com numa máquina nova) e continua
/// recusando chave trocada. OpenSSH ≥ 7.6: o do macOS, o embutido no Git for
/// Windows e o OpenSSH do Windows 10/11 atendem.
const kCloneSshCommand =
    'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new';

/// Ambiente do `git clone` a partir de [base] (o env do processo).
///
/// O app GUI não tem TTY: um prompt de usuário/senha (HTTPS) ou de passphrase
/// e host key (SSH) deixaria o clone pendurado. `GIT_TERMINAL_PROMPT=0` corta o
/// do HTTPS (credential helpers como osxkeychain/manager seguem funcionando).
///
/// O SSH sem prompt ([kCloneSshCommand]) só entra quando o usuário não escolheu
/// o próprio: `GIT_SSH_COMMAND`/`GIT_SSH` no ambiente (ex.: plink/PuTTY no
/// Windows) ou `core.sshCommand` no git config ([configuredSshCommand], ex.:
/// OpenSSH do Windows pro ssh-agent do sistema, agente do 1Password). Setar
/// `GIT_SSH_COMMAND` por cima disso ganharia do config e quebraria o acesso.
Map<String, String> cloneProcessEnvironment(
  Map<String, String> base, {
  String? configuredSshCommand,
}) {
  final env = Map<String, String>.of(base);
  env['GIT_TERMINAL_PROMPT'] = '0';
  bool has(String key) => (env[key] ?? '').isNotEmpty;
  final userChoseSsh =
      has('GIT_SSH_COMMAND') ||
      has('GIT_SSH') ||
      (configuredSshCommand?.isNotEmpty ?? false);
  if (!userChoseSsh) env['GIT_SSH_COMMAND'] = kCloneSshCommand;
  return env;
}
