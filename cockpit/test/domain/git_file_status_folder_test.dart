import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a deleted child paints the folder as modified, not deleted', () {
    expect(
      GitFileStatus.strongestForFolder(null, GitFileStatus.deleted),
      GitFileStatus.modified,
    );
  });

  test('new files next to a deletion keep the folder from turning red', () {
    var folder = GitFileStatus.strongestForFolder(null, GitFileStatus.deleted);
    folder = GitFileStatus.strongestForFolder(folder, GitFileStatus.untracked);
    expect(folder, GitFileStatus.modified);
    expect(folder, isNot(GitFileStatus.deleted));
  });

  test('conflict still wins for the folder', () {
    final folder = GitFileStatus.strongestForFolder(
      GitFileStatus.deleted,
      GitFileStatus.conflict,
    );
    expect(folder, GitFileStatus.conflict);
  });

  test('a file itself keeps the plain strongest rule', () {
    expect(
      GitFileStatus.strongest(GitFileStatus.untracked, GitFileStatus.deleted),
      GitFileStatus.deleted,
    );
  });
}
