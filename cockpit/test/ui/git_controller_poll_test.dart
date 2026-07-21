import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reader nulo — nenhuma pasta é repo git; o poll roda mas `refresh` é no-op.
class _NullReader implements GitStatusReader {
  @override
  Future<GitInfo?> read(String path) async => null;
}

/// Runner que nunca é exercido neste teste (o poll só lê estado).
class _UnusedRunner implements GitCommandRunner {
  @override
  GitRun run(String repoPath, List<String> args) =>
      throw UnimplementedError();
  @override
  GitRun syncPullPush(String repoPath) => throw UnimplementedError();
  @override
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  ) => throw UnimplementedError();
}

void main() {
  test('startPoll dispara onPoll a cada tick (reconciliação de worktrees)', () {
    fakeAsync((async) {
      final git = GitController(_NullReader(), _UnusedRunner())
        // Sem alvos de status: isola o teste no gancho onPoll.
        ..pollTargets = (() => const <String>[]);

      var ticks = 0;
      git.onPoll = () => ticks++;

      git.startPoll();
      expect(ticks, 0, reason: 'nada dispara antes do primeiro intervalo');

      // 3 intervalos de 3s = 3 ticks.
      async.elapse(const Duration(seconds: 9));
      expect(ticks, 3);

      git.dispose();
      // Após dispose o timer para → nenhum tick novo.
      async.elapse(const Duration(seconds: 9));
      expect(ticks, 3, reason: 'dispose cancela o poll');
    });
  });
}
