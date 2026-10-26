import 'dart:typed_data';

class TerminalClipboardContent {
  const TerminalClipboardContent({
    this.files = const [],
    this.image,
    this.text,
    this.sequence,
  });
  final List<String> files;
  final Uint8List? image;
  final String? text;
  final int? sequence;
  bool get hasImage => image != null && image!.isNotEmpty;
}

abstract interface class TerminalClipboardReader {
  Future<TerminalClipboardContent> read();
  Future<bool> stillContainsImage(TerminalClipboardContent content);
}

class TerminalImportResult {
  const TerminalImportResult(this.paths, this.errors);
  final List<String> paths;
  final List<String> errors;
}

abstract interface class TerminalAttachmentStore {
  Future<TerminalImportResult> import({
    required String projectRoot,
    required List<String> paths,
    Uint8List? image,
    required bool Function() isAlive,
    required void Function(int completed, int total) onProgress,
  });
}

abstract interface class TerminalPathConverter {
  Future<String> forWsl(String path, String distribution);
}
