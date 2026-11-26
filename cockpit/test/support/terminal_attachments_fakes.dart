import 'dart:typed_data';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_attachments.dart';

class FakeClipboard implements TerminalClipboardReader {
  TerminalClipboardContent content = const TerminalClipboardContent();
  bool unchanged = true;
  bool failCheck = false;
  @override
  Future<TerminalClipboardContent> read() async => content;
  @override
  Future<bool> stillContainsImage(TerminalClipboardContent content) async {
    if (failCheck) throw StateError('clipboard busy');
    return unchanged;
  }
}

class FakeAttachmentStore implements TerminalAttachmentStore {
  TerminalImportResult result = const TerminalImportResult([
    '/project/.cockpit/attachments/one/a.png',
  ], []);
  int calls = 0;
  Uint8List? receivedImage;
  List<String> receivedPaths = [];
  Future<void> Function()? beforeComplete;
  @override
  Future<TerminalImportResult> import({
    required String projectRoot,
    required List<String> paths,
    Uint8List? image,
    required bool Function() isAlive,
    required void Function(int completed, int total) onProgress,
  }) async {
    calls++;
    receivedImage = image;
    receivedPaths = paths;
    onProgress(0, paths.isEmpty ? 1 : paths.length);
    await beforeComplete?.call();
    return result;
  }
}

class FakePathConverter implements TerminalPathConverter {
  bool fail = false;
  final List<(String, String)> calls = [];
  @override
  Future<String> forWsl(String path, String distribution) async {
    calls.add((path, distribution));
    if (fail) throw StateError('inaccessible');
    return '/mnt/c/project/image.png';
  }
}
