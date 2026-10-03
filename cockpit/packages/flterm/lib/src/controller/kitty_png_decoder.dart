import 'dart:typed_data';

import 'package:image/image.dart' show decodePng;
import 'package:libghostty/libghostty.dart';

var _installed = false;

/// Installs flterm's default PNG decoder for Kitty graphics.
///
/// Installation is idempotent across terminal sessions.
void installDefaultKittyPngDecoder() {
  if (_installed) return;
  _installed = true;
  LibGhostty.setPngDecoder(_decodePng);
}

DecodedImage? _decodePng(Uint8List bytes) {
  final decoded = decodePng(bytes);
  if (decoded == null) return null;
  final rgba = decoded.convert(format: .uint8, numChannels: 4);
  return DecodedImage(
    width: rgba.width,
    height: rgba.height,
    rgba: rgba.toUint8List(),
  );
}
