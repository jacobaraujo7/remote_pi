import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_history_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_history_commit.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_history_file_change.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/git_history_error.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Leitor estruturado do `git log`; os separadores de controle evitam depender
/// de alinhamento, locale ou do desenho textual de `--graph`.
class GitHistoryReaderImpl implements GitHistoryReader {
  GitHistoryReaderImpl(this._gitBinary);

  final GitBinary _gitBinary;

  @override
  Future<Result<List<GitHistoryCommit>, GitHistoryError>> read(
    String repoPath, {
    int limit = 100,
  }) async {
    try {
      final git = await _gitBinary.resolve();
      final result = await Process.run(git, [
        '-C',
        repoPath,
        'log',
        '-n',
        '$limit',
        '--decorate=short',
        '--date=iso-strict',
        '--format=%H%x1f%P%x1f%D%x1f%an%x1f%aI%x1f%s%x1e',
      ], environment: await envWithNodeOnPath());
      if (result.exitCode != 0) {
        return Failure(
          GitHistoryError(
            GitHistoryErrorKind.commandFailed,
            detail: result.stderr.toString().trim(),
          ),
        );
      }
      return Success(GitHistoryParser.parse(result.stdout.toString()));
    } on ProcessException catch (error) {
      return Failure(
        GitHistoryError(
          GitHistoryErrorKind.commandFailed,
          detail: error.message,
        ),
      );
    }
  }

  @override
  Future<Result<List<GitHistoryFileChange>, GitHistoryError>> readFiles(
    String repoPath,
    String commitHash,
  ) async {
    try {
      final git = await _gitBinary.resolve();
      final result = await Process.run(git, [
        '-C',
        repoPath,
        'show',
        '--format=',
        '--name-status',
        '-z',
        '--find-renames',
        '--first-parent',
        commitHash,
        '--',
      ], environment: await envWithNodeOnPath());
      if (result.exitCode != 0) {
        return Failure(
          GitHistoryError(
            GitHistoryErrorKind.commandFailed,
            detail: result.stderr.toString().trim(),
          ),
        );
      }
      return Success(
        GitHistoryFileChangeParser.parse(result.stdout.toString()),
      );
    } on ProcessException catch (error) {
      return Failure(
        GitHistoryError(
          GitHistoryErrorKind.commandFailed,
          detail: error.message,
        ),
      );
    }
  }
}

/// Parser publico para manter o formato do processo testavel sem um repo real.
class GitHistoryParser {
  static List<GitHistoryCommit> parse(String output) {
    final commits = <GitHistoryCommit>[];
    for (final record in output.split('\u001e')) {
      if (record.trim().isEmpty) continue;
      // `git log` acrescenta uma quebra de linha apos cada record separator.
      // Sem remove-la do inicio, todo hash apos o primeiro vira uma revisao
      // invalida quando usado em `git show`.
      final fields = record.trim().split('\u001f');
      if (fields.length < 6 || fields.first.isEmpty) continue;
      final decorations = fields[2].trim();
      commits.add(
        GitHistoryCommit(
          hash: fields[0],
          parents: fields[1].trim().isEmpty
              ? const []
              : fields[1].trim().split(RegExp(r'\s+')),
          refs: decorations.isEmpty
              ? const []
              : decorations.split(',').map((ref) => ref.trim()).toList(),
          author: fields[3],
          authoredAt: DateTime.tryParse(fields[4]),
          subject: fields.sublist(5).join('\u001f'),
        ),
      );
    }
    return commits;
  }
}

/// Parser do formato NUL-delimitado de `git show --name-status -z`.
class GitHistoryFileChangeParser {
  static List<GitHistoryFileChange> parse(String output) {
    final fields = output.split('\u0000');
    final changes = <GitHistoryFileChange>[];
    for (var index = 0; index < fields.length - 1;) {
      final status = fields[index++];
      if (status.isEmpty || index >= fields.length) continue;
      if (status.startsWith('R') || status.startsWith('C')) {
        if (index + 1 >= fields.length) break;
        final previousPath = fields[index++];
        final path = fields[index++];
        changes.add(
          GitHistoryFileChange(
            status: status,
            path: path,
            previousPath: previousPath,
          ),
        );
      } else {
        changes.add(
          GitHistoryFileChange(status: status, path: fields[index++]),
        );
      }
    }
    return changes;
  }
}
