import 'package:cockpit/app/cockpit/ui/session/agent_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final make in <AgentEntry Function()>[
    AssistantTextEntry.new,
    ThinkingEntry.new,
  ]) {
    test('${make().runtimeType} acumula deltas e cacheia o snapshot', () {
      final entry = make();
      switch (entry) {
        case final AssistantTextEntry text:
          text
            ..append('hello')
            ..append(' world');
          final first = text.text;
          expect(first, 'hello world');
          expect(identical(first, text.text), isTrue);
          text.append('!');
          expect(text.text, 'hello world!');
          text.text = 'final';
          expect(text.text, 'final');
        case final ThinkingEntry text:
          text
            ..append('hello')
            ..append(' world');
          final first = text.text;
          expect(first, 'hello world');
          expect(identical(first, text.text), isTrue);
          text.append('!');
          expect(text.text, 'hello world!');
          text.text = 'final';
          expect(text.text, 'final');
        default:
          fail('unexpected entry type');
      }
    });
  }
}
