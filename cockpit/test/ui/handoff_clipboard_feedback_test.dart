import 'dart:async';

import 'package:cockpit/app/cockpit/ui/widgets/handoff_clipboard_feedback.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  for (final confirmCopied in [false, true]) {
    final entryPoint = confirmCopied ? 'graph' : 'owned-terminal menu';
    for (final result in TextClipboardResult.values) {
      testWidgets(
        '$entryPoint: $result preserves handoff completion and summary',
        (tester) async {
          const summary =
              'Keep the prepared API changes and run the next check.';
          final waiting = Completer<void>();
          final reachedRetry = Completer<void>();
          final writes = <String>[];
          final service = TextClipboardService(
            writer: (text) async {
              writes.add(text);
              if (text != summary) return;
              if (result == TextClipboardResult.failed) {
                throw PlatformException(code: 'denied');
              }
              if (result == TextClipboardResult.superseded) {
                throw PlatformException(
                  code: 'Clipboard error',
                  message: 'Unable to open clipboard',
                );
              }
            },
            delay: (_) {
              reachedRetry.complete();
              return waiting.future;
            },
          );
          var completed = false;
          await tester.pumpWidget(
            TranslationProvider(
              child: ShadcnApp(
                theme: buildTheme(brightness: Brightness.dark),
                home: Builder(
                  builder: (context) => PrimaryButton(
                    onPressed: () async {
                      await showHandoffClipboardFeedback(
                        context,
                        sessionId: 'created-session',
                        summary: summary,
                        operation: 'test',
                        confirmCopied: confirmCopied,
                        clipboard: service,
                      );
                      completed = true;
                    },
                    child: const Text('Complete handoff'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Complete handoff'));
          await tester.pump();
          TextClipboardResult? newerResult;
          if (result == TextClipboardResult.superseded) {
            expect(reachedRetry.isCompleted, isTrue);
            unawaited(
              service.write('newer copy', operation: 'test').then((value) {
                newerResult = value;
              }),
            );
            waiting.complete();
          }
          await tester.pumpAndSettle();
          final needsDialog =
              confirmCopied || result != TextClipboardResult.copied;
          if (needsDialog) {
            expect(find.text('New session ready'), findsOneWidget);
            expect(completed, isFalse);
            if (result == TextClipboardResult.copied) {
              expect(
                find.textContaining('Paste the copied summary'),
                findsOneWidget,
              );
              expect(find.byType(SelectableText), findsNothing);
            } else {
              expect(
                find.textContaining('summary was not copied'),
                findsOneWidget,
              );
              expect(
                find.textContaining('Paste the copied summary'),
                findsNothing,
              );
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is SelectableText && widget.data == summary,
                ),
                findsOneWidget,
              );
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is SelectableText &&
                      widget.data == 'created-session',
                ),
                findsOneWidget,
              );
            }
            await tester.tap(
              find.text(LocaleSettings.currentLocale.translations.common.gotIt),
            );
            await tester.pumpAndSettle();
          } else {
            expect(find.byType(AlertDialog), findsNothing);
          }
          expect(completed, isTrue);
          if (result == TextClipboardResult.superseded) {
            expect(newerResult, TextClipboardResult.copied);
            expect(writes, [summary, 'newer copy']);
          } else {
            expect(writes, [summary]);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'long failed summary stays selectable in a bounded scrolling dialog',
    (tester) async {
      final summary = List.generate(
        200,
        (index) => 'Line $index: retain this handoff detail.',
      ).join('\n');
      final service = TextClipboardService(
        writer: (_) async => throw PlatformException(code: 'denied'),
      );
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Builder(
              builder: (context) => PrimaryButton(
                onPressed: () => showHandoffClipboardFeedback(
                  context,
                  sessionId: 'created-session',
                  summary: summary,
                  operation: 'test',
                  clipboard: service,
                ),
                child: const Text('Complete handoff'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Complete handoff'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == summary,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(LocaleSettings.currentLocale.translations.common.gotIt),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
