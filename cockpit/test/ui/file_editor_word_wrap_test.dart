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

  group('toggledEditorWordWrap', () {
    test('turning wrap off always stores Off', () {
      expect(toggledEditorWordWrap(chosen: null, language: 'markdown'), false);
      expect(toggledEditorWordWrap(chosen: true, language: 'markdown'), false);
      expect(toggledEditorWordWrap(chosen: true, language: 'dart'), false);
    });

    test('turning it on in a prose file goes back to the language default', () {
      for (final lang in ['markdown', 'md', 'txt', 'text']) {
        expect(toggledEditorWordWrap(chosen: false, language: lang), isNull);
      }
    });

    test('turning it on in a code file wraps all files', () {
      expect(toggledEditorWordWrap(chosen: false, language: 'dart'), isTrue);
      expect(toggledEditorWordWrap(chosen: null, language: 'dart'), isTrue);
      expect(toggledEditorWordWrap(chosen: false, language: null), isTrue);
    });

    test('Alt+Z twice in a Markdown file is back where it started', () {
      final off = toggledEditorWordWrap(chosen: null, language: 'markdown');
      expect(toggledEditorWordWrap(chosen: off, language: 'markdown'), isNull);
    });
  });
}
