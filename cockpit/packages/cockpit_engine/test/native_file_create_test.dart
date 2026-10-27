import 'dart:io';
import 'dart:convert';
import 'package:cockpit_engine/cockpit_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  const files = NativeFileService();
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-exclusive-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });
  test(
    'concurrent creators preserve exactly one complete original file',
    () async {
      final path = '${temporary.path}/agents.orchestration';
      final results = await Future.wait(
        List.generate(
          8,
          (i) => files.createNew(path, utf8.encode('document $i')),
        ),
      );
      expect(results.where((created) => created).length, 1);
      final original = await File(path).readAsString();
      expect(original, 'document ${results.indexOf(true)}');
      expect(await files.createNew(path, utf8.encode('replacement')), isFalse);
      expect(await File(path).readAsString(), original);
    },
  );
  test('an existing directory is preserved', () async {
    final path = '${temporary.path}/existing';
    await Directory(path).create();
    expect(await files.createNew(path, utf8.encode('replacement')), isFalse);
    expect(await Directory(path).exists(), isTrue);
  });
}
