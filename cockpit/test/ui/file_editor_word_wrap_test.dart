import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fileEditorWordWrap', () {
    test('without a choice, wraps prose and leaves code unwrapped', () {
      for (final lang in ['markdown', 'md', 'txt', 'text']) {
        expect(fileEditorWordWrap(chosen: null, language: lang), isTrue);
      }
      for (final lang in ['dart', 'yaml', 'json', null]) {
        expect(fileEditorWordWrap(chosen: null, language: lang), isFalse);
      }
    });

    test('an explicit choice wins over the language default', () {
      expect(fileEditorWordWrap(chosen: false, language: 'markdown'), isFalse);
      expect(fileEditorWordWrap(chosen: true, language: 'dart'), isTrue);
    });
  });
}
