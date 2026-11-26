import 'dart:async';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/ui/document/native_document_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;

Project project(
  String id,
  String root, {
  String realm = 'default',
  String? host,
}) => Project(
  id: id,
  name: id,
  path: root,
  realmId: realm,
  remoteHostId: host,
  colorValue: 0,
  createdAt: DateTime(2026),
);

void main() {
  test(
    'cold boot queues owned files without delaying ordinary windows',
    () async {
      final windows = <String>[];
      final apps = <String>[];
      final router = NativeDocumentRouter(
        openDocument: (p) async {
          windows.add(p);
        },
      );
      final first = router.open('/work/a.orc');
      final second = router.open('/work/b.orchestration');
      await router.open('/work/note.txt');
      expect(windows, ['/work/note.txt']);
      expect(apps, isEmpty);
      router.attach((p) async {
        apps.add(p);
      });
      await Future.wait([first, second]);
      expect(apps, ['/work/a.orc', '/work/b.orchestration']);
    },
  );

  test(
    'running opens serialize, including duplicate native delivery',
    () async {
      final gate = Completer<void>();
      final apps = <String>[];
      final router = NativeDocumentRouter(openDocument: (_) async {});
      router.attach((p) async {
        apps.add(p);
        if (apps.length == 1) await gate.future;
      });
      final first = router.open('/work/a.orc');
      final second = router.open('/work/a.orc');
      await Future<void>.delayed(Duration.zero);
      expect(apps, ['/work/a.orc']);
      gate.complete();
      await Future.wait([first, second]);
      expect(apps, ['/work/a.orc', '/work/a.orc']);
    },
  );

  test('one failure does not strand the next native open', () async {
    final apps = <String>[];
    final router = NativeDocumentRouter(openDocument: (_) async {});
    router.attach((p) async {
      if (p.contains('bad')) throw StateError('unavailable');
      apps.add(p);
    });
    await expectLater(router.open('/bad.orc'), throwsStateError);
    await router.open('/good.orc');
    expect(apps, ['/good.orc']);
  });

  test(
    'disposed handler detaches and stale cleanup cannot detach replacement',
    () async {
      final apps = <String>[];
      final router = NativeDocumentRouter(openDocument: (_) async {});
      final detach = router.attach((p) async {
        apps.add('old');
      });
      detach();
      final pending = router.open('/next.orc');
      final detachNew = router.attach((p) async {
        apps.add(p);
      });
      detach();
      await pending;
      await router.open('/again.orc');
      expect(apps, ['/next.orc', '/again.orc']);
      detachNew();
    },
  );

  test(
    'case-insensitive owned extensions do not capture backup files',
    () async {
      final windows = <String>[];
      final apps = <String>[];
      final router = NativeDocumentRouter(
        openDocument: (p) async {
          windows.add(p);
        },
      );
      router.attach((p) async {
        apps.add(p);
      });
      await router.open('/team.ORC');
      await router.open('/team.ORCHESTRATION');
      await router.open('/team.orc.backup');
      expect(apps, ['/team.ORC', '/team.ORCHESTRATION']);
      expect(windows, ['/team.orc.backup']);
    },
  );

  test(
    'nearest local worktree wins over selected unrelated or parent project',
    () {
      final candidates = [
        project('selected', '/other'),
        project('root', '/repo'),
        project('fork', '/repo/worktrees/feature'),
        project('remote', '/repo/worktrees/feature', host: 'ssh'),
      ];
      expect(
        nativeOrchestrationProject(
          '/repo/worktrees/feature/team.orc',
          candidates,
          realmId: 'default',
          selectedProjectId: 'selected',
        )?.id,
        'fork',
      );
      expect(
        nativeOrchestrationProject(
          '/repo-other/team.orc',
          candidates,
          realmId: 'default',
        ),
        isNull,
      );
    },
  );

  test(
    'same-root realm duplicates prefer active realm then its selected project',
    () {
      final candidates = [
        project('a', '/repo', realm: 'old'),
        project('b', '/repo'),
        project('c', '/repo'),
      ];
      expect(
        nativeOrchestrationProject(
          '/repo/team.orc',
          candidates,
          realmId: 'default',
          selectedProjectId: 'a',
        )?.id,
        'b',
      );
      expect(
        nativeOrchestrationProject(
          '/repo/team.orc',
          candidates,
          realmId: 'default',
          selectedProjectId: 'c',
        )?.id,
        'c',
      );
    },
  );

  test('Windows worktree containment respects drive and case boundaries', () {
    final context = paths.Context(style: paths.Style.windows);
    final candidates = [
      project('root', 'C:/repo'),
      project('fork', 'C:/repo/worktrees/feature'),
    ];
    expect(
      nativeOrchestrationProject(
        'c:/REPO/worktrees/FEATURE/team.ORC',
        candidates,
        realmId: 'default',
        context: context,
      )?.id,
      'fork',
    );
    expect(
      nativeOrchestrationProject(
        'D:/repo/team.orc',
        candidates,
        realmId: 'default',
        context: context,
      ),
      isNull,
    );
  });
}
