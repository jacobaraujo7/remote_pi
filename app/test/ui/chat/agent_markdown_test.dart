// Plan/32b — AgentMarkdown renders fenced code with a copy button.
// Issue #184 — markdown headings must not fall back to Material's TextTheme.

import 'package:app/ui/chat/widgets/agent_markdown.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  Future<void> pump(WidgetTester tester, String md) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AgentMarkdown(md))),
    );
  }

  testWidgets('fenced code block shows a copy button', (tester) async {
    await pump(tester, '```dart\nfinal x = 1;\n```');
    await tester.pump();
    expect(find.byKey(const Key('code-copy')), findsOneWidget);
    expect(find.textContaining('final x = 1;'), findsOneWidget);
  });

  testWidgets('tapping copy puts the code on the clipboard', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, '```\nhello code\n```');
    await tester.pump();
    await tester.tap(find.byKey(const Key('code-copy')));
    await tester.pump();

    expect(calls, isNotEmpty, reason: 'Clipboard.setData was invoked');
    final text = (calls.first.arguments as Map)['text'] as String;
    expect(text, contains('hello code'));
  });

  testWidgets('plain prose renders without a code block', (tester) async {
    await pump(tester, 'just a normal sentence.');
    await tester.pump();
    expect(find.byKey(const Key('code-copy')), findsNothing);
  });

  // Issue #184 — gpt_markdown sizes `#`…`######` from its own
  // GptMarkdownThemeData and falls back to Material's TextTheme when the host
  // provides none (h1 32 / h2 28 / h3 24 / h4 22). Those are absolute rather
  // than derived from the style passed to GptMarkdown, so against this app's
  // 12.5pt mono body a `##` was already 2.24× the prose — and because the #114
  // text-size setting applies one linear TextScaler to the whole tree, the XL
  // preset rendered it at 36.4pt beside 16.25pt body text.
  group('heading typography (#184)', () {
    Iterable<TextStyle?> allHeadings(GptMarkdownThemeData t) =>
        [t.h1, t.h2, t.h3, t.h4, t.h5, t.h6];

    test('headings stay proportionate to the mono body', () {
      final typo = AppTypography.dark;
      final md = buildMarkdownTheme(
        typo: typo,
        brightness: Brightness.dark,
      );
      final body = typo.mono.fontSize!;

      for (final style in allHeadings(md)) {
        // Never smaller than the prose it heads…
        expect(style!.fontSize!, greaterThanOrEqualTo(body));
        // …and never more than 1.4× it. Material's headlineMedium (28) was
        // 2.24×, which is exactly the bug.
        expect(style.fontSize!, lessThanOrEqualTo(body * 1.4));
      }

      // Still a descending scale, so `#` outranks `######`.
      expect(md.h1!.fontSize!, greaterThan(md.h2!.fontSize!));
      expect(md.h2!.fontSize!, greaterThan(md.h3!.fontSize!));
      expect(md.h3!.fontSize!, greaterThan(md.h4!.fontSize!));
    });

    test('headings use the app mono family, not the platform sans', () {
      final md = buildMarkdownTheme(
        typo: AppTypography.dark,
        brightness: Brightness.dark,
      );
      for (final style in allHeadings(md)) {
        expect(style!.fontFamily, kMonoFamily);
      }
    });

    test('both app themes register the markdown heading extension', () {
      for (final theme in [buildDarkTheme(), buildLightTheme()]) {
        final md = theme.extension<GptMarkdownThemeData>();
        expect(md, isNotNull, reason: 'theme carries GptMarkdownThemeData');
        expect(md!.h2!.fontFamily, kMonoFamily);
        expect(md.h2!.fontSize, 15.5);
      }
    });

    testWidgets('gpt_markdown resolves the heading styles from the theme', (
      tester,
    ) async {
      late GptMarkdownThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: Builder(
            builder: (context) {
              resolved = GptMarkdownTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // GptMarkdownTheme.of() falls back to the Material TextTheme when the
      // host registers no extension — which was the bug — so resolving the
      // styles here proves they actually reach gpt_markdown.
      expect(resolved.h2!.fontFamily, kMonoFamily);
      expect(resolved.h2!.fontSize, 15.5);
    });
  });
}
