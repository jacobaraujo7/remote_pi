import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/clipboard_failure_feedback.dart';
import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'failed write shows localized feedback and disposing cancels timer',
    (tester) async {
      final service = TextClipboardService(
        writer: (_) async => throw PlatformException(code: 'denied'),
      );
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: ClipboardFailureFeedback(
              service: service,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(
        await service.write('not shown', operation: 'test'),
        TextClipboardResult.failed,
      );
      await tester.pump();
      expect(find.textContaining('Could not copy'), findsOneWidget);
      expect(find.text('not shown'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
