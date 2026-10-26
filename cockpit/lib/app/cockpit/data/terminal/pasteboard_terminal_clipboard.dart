import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../domain/contracts/terminal_attachments.dart';

class PasteboardTerminalClipboard implements TerminalClipboardReader {
  const PasteboardTerminalClipboard();
  static const channel = MethodChannel('cockpit/terminal_clipboard');

  @override
  Future<TerminalClipboardContent> read() async {
    if (Platform.isWindows) {
      final data = await channel.invokeMapMethod<String, dynamic>('read');
      if (data == null) return const TerminalClipboardContent();
      return TerminalClipboardContent(
        files: (data['files'] as List?)?.cast<String>() ?? const [],
        image: data['image'] as Uint8List?,
        text: data['text'] as String?,
        sequence: data['sequence'] as int?,
      );
    }
    final files = await Pasteboard.files();
    if (files.isNotEmpty) return TerminalClipboardContent(files: files);
    final image = await Pasteboard.image;
    if (image != null && image.isNotEmpty) {
      return TerminalClipboardContent(image: image);
    }
    return TerminalClipboardContent(text: await Pasteboard.text);
  }

  @override
  Future<bool> stillContainsImage(TerminalClipboardContent content) async {
    if (!content.hasImage) return false;
    if (Platform.isWindows) {
      return content.sequence != null &&
          await channel.invokeMethod<int>('sequence') == content.sequence;
    }
    final current = await read();
    return current.files.isEmpty && listEquals(current.image, content.image);
  }
}
