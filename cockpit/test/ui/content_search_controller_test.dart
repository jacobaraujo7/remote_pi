import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/content_search_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

FileMatches result(String name, [String text = 'needle']) => FileMatches(
  relativePath: name,
  matches: [
    LineMatch(lineNumber: 2, text: text, ranges: const [MatchRange(0, 6)]),
  ],
);

void main() {
  testWidgets(
    'workspace/worktree queries and pending streams stay root-bound across navigation',
    (tester) async {
      final streams = <String, StreamController<FileMatches>>{};
      final calls = <String, int>{};
      final states = {
        for (final root in ['/workspace-a', '/workspace-b', '/worktree-a'])
          root: ContentSearchController(
            root: root,
            search:
                (
                  term, {
                  caseSensitive = false,
                  wholeWord = false,
                  regex = false,
                }) {
                  calls.update(root, (n) => n + 1, ifAbsent: () => 1);
                  return (streams[root] = StreamController<FileMatches>())
                      .stream;
                },
          ),
      };
      for (final entry in states.entries) {
        entry.value.attach();
        entry.value.query.text = 'query for ${entry.key}';
        await tester.pump(const Duration(milliseconds: 201));
        entry.value.detach();
      }
      // Deliver AFTER switching contexts, including identical relative paths.
      for (final entry in streams.entries) {
        entry.value.add(result('same.dart', entry.key));
        await entry.value.close();
      }
      await tester.pump();
      for (var round = 0; round < 3; round++) {
        for (final entry in states.entries) {
          final state = entry.value;
          state.attach();
          await tester.pump(const Duration(milliseconds: 300));
          expect(state.query.text, 'query for ${entry.key}');
          expect(state.results.single.matches.single.text, entry.key);
          expect(state.searching, isFalse);
          expect(calls[entry.key], 1);
          state.detach();
        }
      }
      for (final state in states.values) {
        state.dispose();
      }
    },
  );

  testWidgets(
    'options, collapsed groups, caret and scroll survive detach; caret does not search',
    (tester) async {
      var calls = 0;
      final state = ContentSearchController(
        root: '/workspace',
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              calls++;
              return Stream.value(result('file.dart'));
            },
      );
      state.attach();
      state.query.text = 'needle';
      state.setOptions(caseSensitive: true, wholeWord: true, regex: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1, reason: 'option change cancels the text debounce');
      state.toggleCollapsed('file.dart');
      state.scrollOffset = 120;
      state.query.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      state.detach();
      state.attach();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      expect(state.caseSensitive && state.wholeWord && state.regex, isTrue);
      expect(state.isCollapsed('file.dart'), isTrue);
      expect(state.scrollOffset, 120);
      expect(
        state.query.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      state.detach();
      state.dispose();
    },
  );

  testWidgets(
    'editing cancels old results immediately, and clearing cancels the pending scan',
    (tester) async {
      final streams = <StreamController<FileMatches>>[];
      var cancelled = 0;
      final state = ContentSearchController(
        root: '/workspace',
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              final stream = StreamController<FileMatches>(
                onCancel: () => cancelled++,
              );
              streams.add(stream);
              return stream.stream;
            },
      );
      state.query.text = 'first';
      await tester.pump(const Duration(milliseconds: 201));
      streams.first.add(result('old.dart'));
      await tester.pump();
      expect(state.results, hasLength(1));
      state.query.text = 'next';
      expect(state.results, isEmpty);
      streams.first.add(result('late.dart'));
      await tester.pump(const Duration(milliseconds: 201));
      expect(state.results, isEmpty);
      expect(cancelled, 1);
      state.query.clear();
      state.runSearch();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cancelled, 2);
      expect(streams, hasLength(2));
      expect(state.searching, isFalse);
      state.dispose();
      for (final stream in streams) {
        unawaited(stream.close());
      }
    },
  );

  testWidgets(
    'hidden Search cancels observation and validates once on return',
    (tester) async {
      final changes = StreamController<void>.broadcast();
      var revision = 0;
      var observed = 0;
      var validations = 0;
      final resumableChanges = Stream<void>.multi((listener) {
        validations++;
        if (observed != revision) {
          observed = revision;
          listener.add(null);
        }
        final subscription = changes.stream.listen((_) {
          observed = revision;
          listener.add(null);
        });
        listener.onCancel = subscription.cancel;
      });
      var calls = 0;
      final state = ContentSearchController(
        root: '/workspace',
        changes: resumableChanges,
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              calls++;
              return Stream.value(
                result(calls == 1 ? 'deleted.dart' : 'new.dart'),
              );
            },
      );
      state.attach();
      state.query.text = 'needle';
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pump();
      expect(state.results.single.relativePath, 'deleted.dart');
      expect(changes.hasListener, isTrue);
      // Multiple mounts share one observation; only the final detach stops it.
      state.attach();
      state.detach();
      expect(changes.hasListener, isTrue);
      state.detach();
      await tester.pump();
      expect(changes.hasListener, isFalse);
      for (var i = 0; i < 3; i++) {
        state.attach();
        await tester.pump(const Duration(milliseconds: 300));
        expect(calls, 1, reason: 'unchanged signature must reuse the results');
        state.detach();
        await tester.pump();
      }
      final checked = validations;
      revision++;
      changes.add(null);
      await tester.pump(const Duration(minutes: 5));
      expect(state.results.single.relativePath, 'deleted.dart');
      expect(validations, checked, reason: 'no work while hidden');
      expect(calls, 1);
      state.attach();
      await tester.pump();
      expect(state.results, isEmpty);
      expect(validations, checked + 1);
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pump();
      expect(calls, 2);
      expect(state.results.single.relativePath, 'new.dart');
      expect(state.query.text, 'needle');
      changes.add(null);
      changes.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pump();
      expect(calls, 3, reason: 'visible filesystem changes are coalesced');
      state.detach();
      state.dispose();
      unawaited(changes.close());
    },
  );

  testWidgets('hiding during debounce defers the draft until Search returns', (
    tester,
  ) async {
    var calls = 0;
    final state = ContentSearchController(
      root: '/workspace',
      search:
          (term, {caseSensitive = false, wholeWord = false, regex = false}) {
            calls++;
            return Stream.value(result('file.dart'));
          },
    );
    state.attach();
    state.query.text = 'draft';
    state.detach();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 0);
    expect(state.query.text, 'draft');
    state.attach();
    await tester.pump(const Duration(milliseconds: 201));
    await tester.pump();
    expect(calls, 1);
    state.detach();
    state.dispose();
  });

  testWidgets(
    'invalid regex state survives navigation and new sessions are empty',
    (tester) async {
      var calls = 0;
      ContentSearchController create() => ContentSearchController(
        root: '/workspace',
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              calls++;
              return Stream.error(const FormatException('bad regex'));
            },
      );
      final state = create();
      state.query.text = '[';
      state.setOptions(regex: true);
      await tester.pump();
      expect(state.invalidRegex, isTrue);
      state.attach();
      state.detach();
      state.attach();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(state.invalidRegex, isTrue);
      state.detach();
      state.dispose();
      final fresh = create();
      expect(fresh.query.text, isEmpty);
      expect(fresh.results, isEmpty);
      expect(fresh.regex, isFalse);
      fresh.dispose();
    },
  );

  testWidgets(
    'removing a context cancels timers, stream and filesystem watcher',
    (tester) async {
      var scanCancelled = false;
      var watcherCancelled = false;
      var calls = 0;
      final changes = StreamController<void>(
        onCancel: () => watcherCancelled = true,
      );
      final scan = StreamController<FileMatches>(
        onCancel: () => scanCancelled = true,
      );
      final state = ContentSearchController(
        root: '/worktree',
        changes: changes.stream,
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              calls++;
              return scan.stream;
            },
      );
      state.attach();
      state.query.text = 'needle';
      await tester.pump(const Duration(milliseconds: 201));
      state.query.text = 'pending';
      state.dispose();
      changes.add(null);
      scan.add(result('late.dart'));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(scanCancelled, isTrue);
      expect(watcherCancelled, isTrue);
      unawaited(changes.close());
      unawaited(scan.close());
    },
  );
}
