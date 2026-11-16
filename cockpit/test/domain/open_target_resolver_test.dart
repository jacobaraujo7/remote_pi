import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/services/open_target_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Project _p(String id, String path, {String? parentId}) => Project(
  id: id,
  name: id,
  path: path,
  colorValue: 0,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  parentId: parentId,
);

void main() {
  final first = _p('first', 'C:/Users/me/apps/first');
  final tenth = _p('tenth', 'C:/Users/me/apps/tenth');
  final worktree = _p(
    'tenth::wt',
    'C:/Users/me/apps/tenth/.tmp/wt',
    parentId: 'tenth',
  );
  final projects = [first, tenth, worktree, Project.systemTerminal()];

  String? resolve(
    String path, {
    String? caller,
    bool caseInsensitive = false,
    Iterable<Project>? list,
  }) => resolveOpenTargetProject(
    path: path,
    callerProjectId: caller,
    projects: list ?? projects,
    caseInsensitive: caseInsensitive,
  );

  test('keeps the caller workspace when it contains the file', () {
    expect(resolve('C:/Users/me/apps/first/a.html', caller: 'first'), 'first');
  });

  test('keeps the caller leaf workspace even if a nested worktree matches', () {
    expect(
      resolve('C:/Users/me/apps/tenth/.tmp/wt/a.html', caller: 'tenth'),
      'tenth',
    );
  });

  test('routes to the workspace that contains the file (shared Codex daemon '
      'inherits the first tab id)', () {
    expect(
      resolve(r'C:\Users\me\apps\tenth\out\a.html', caller: 'first'),
      'tenth',
    );
  });

  test('picks the most specific workspace (worktree beats parent)', () {
    expect(
      resolve('C:/Users/me/apps/tenth/.tmp/wt/a.html', caller: 'first'),
      'tenth::wt',
    );
  });

  test('falls back to the caller when no workspace contains the file', () {
    expect(resolve('C:/Temp/a.html', caller: 'first'), 'first');
  });

  test('without a caller, uses the containing workspace or null', () {
    expect(resolve('C:/Users/me/apps/tenth/a.html'), 'tenth');
    expect(resolve('C:/Temp/a.html'), isNull);
  });

  test('matches case-insensitively when asked (Windows)', () {
    const path = r'C:\Users\Me\Apps\Tenth\a.html';
    expect(resolve(path, caller: 'first'), 'first');
    expect(resolve(path, caller: 'first', caseInsensitive: true), 'tenth');
  });

  test('does not treat a sibling with a shared prefix as containing', () {
    expect(
      resolve('C:/Users/me/apps/tenth-old/a.html', caller: 'first'),
      'first',
    );
  });

  test('a remote caller always keeps its workspace', () {
    final remote = Project.remoteHost(
      pinId: 'pin',
      hostId: 'h',
      name: 'r',
      remotePath: '/home/me',
      colorValue: 0,
    );
    expect(
      resolve(
        'C:/Users/me/apps/tenth/a.html',
        caller: remote.id,
        list: [...projects, remote],
      ),
      remote.id,
    );
  });
}
