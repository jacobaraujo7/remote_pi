import 'dart:typed_data';
import 'dart:ui';

import 'package:libghostty/libghostty.dart';
import 'package:meta/meta.dart';

/// Converts raw RGBA image bytes into a Flutter [Image].
///
/// The decoder may retain [pixels] until it invokes [callback], but not after.
/// The cache serializes calls and can reuse the buffer after that boundary.
typedef KittyImageDecoder =
    void Function(
      Uint8List pixels,
      int width,
      int height,
      PixelFormat format,
      ImageDecoderCallback callback,
    );

/// Async decoder cache that maps Kitty image ids to drawable [Image]s.
///
/// PNG payloads are already decoded to RGBA by libghostty via the
/// decoder installed with [LibGhostty.setPngDecoder], so only RGB and
/// RGBA formats reach this cache; anything else is stored as
/// [KittyImageUnsupported] so subsequent paints do not retry.
///
/// Re-transmissions under the same id are detected by
/// [KittyImage.generation], so same-sized replacements cannot reuse stale
/// decoded images.
///
/// Decodes are serialized. Requests retain Dart-owned source bytes while
/// queued, allowing eviction to discard obsolete animation frames before RGB
/// expansion and Flutter image decoding begin.
class KittyImageCache {
  final VoidCallback _onImageReady;
  final KittyImageDecoder _decodeImage;
  final Map<int, int> _requestTokens = {};
  final Map<int, int> _requestedGenerations = {};
  final Map<int, KittyImageCacheEntry> _entries = {};
  final Map<int, _KittyDecodeRequest> _queuedRequests = {};
  _KittyDecodeRequest? _activeRequest;
  Uint8List? _rgbSourceBuffer;
  Uint8List? _rgbDecodeBuffer;
  var _nextRequestToken = 0;
  var _disposed = false;

  /// [onImageReady] fires when a pending decode completes; typically
  /// wired to a render box's `markNeedsPaint`.
  KittyImageCache({
    required this._onImageReady,
    this._decodeImage = decodeImageFromPixels,
  });

  /// Releases every cached entry. Call before discarding the cache.
  void dispose() {
    for (final entry in _entries.values) {
      if (entry is KittyImageReady) entry.image.dispose();
    }
    _entries.clear();
    _requestedGenerations.clear();
    _requestTokens.clear();
    _queuedRequests.clear();
    _activeRequest = null;
    _rgbSourceBuffer = null;
    _rgbDecodeBuffer = null;
    _disposed = true;
  }

  /// Releases any cached entries whose id is not in [live].
  void evict(Set<int> live) {
    _entries.removeWhere((id, entry) {
      if (live.contains(id)) return false;
      if (entry is KittyImageReady) entry.image.dispose();
      _requestedGenerations.remove(id);
      _requestTokens.remove(id);
      _queuedRequests.remove(id);
      return true;
    });
  }

  /// Returns the entry for [image], starting a decode on first lookup
  /// or when the image's generation has changed. Never blocks.
  /// Callers that already read [KittyImage.generation] may pass it through to
  /// avoid repeating the native accessor.
  ///
  /// A ready entry remains drawable while its replacement decodes. Only the
  /// latest requested generation may replace it, so rapid updates skip stale
  /// intermediate results without producing a blank frame.
  KittyImageCacheEntry lookup(KittyImage image, {int? generation}) {
    if (_disposed) throw StateError('KittyImageCache is disposed.');
    generation ??= image.generation;
    final existing = _entries[image.id];
    if (existing != null && _requestedGenerations[image.id] == generation) {
      return existing;
    }
    final previousGeneration = _requestedGenerations[image.id];
    _requestedGenerations[image.id] = generation;
    try {
      _beginDecode(image, existing);
    } catch (_) {
      if (previousGeneration == null) {
        _requestedGenerations.remove(image.id);
      } else {
        _requestedGenerations[image.id] = previousGeneration;
      }
      _requestTokens.remove(image.id);
      if (existing == null) {
        _entries.remove(image.id);
      } else {
        _entries[image.id] = existing;
      }
      rethrow;
    }
    return _entries[image.id]!;
  }

  /// Returns the cached entry for [imageId], or null if none. Unlike
  /// [lookup], does not start a decode so it is safe to call from paint.
  KittyImageCacheEntry? lookupById(int imageId) => _entries[imageId];

  /// Inserts a pre-decoded [image] under [imageId].
  @visibleForTesting
  void putReady(int imageId, Image image, {int generation = 0}) {
    final existing = _entries[imageId];
    if (existing is KittyImageReady) existing.image.dispose();
    _entries[imageId] = KittyImageReady(image, generation: generation);
    _requestedGenerations[imageId] = generation;
    _requestTokens.remove(imageId);
    _queuedRequests.remove(imageId);
  }

  void _beginDecode(KittyImage image, KittyImageCacheEntry? existing) {
    final imageId = image.id;
    final generation = _requestedGenerations[imageId];
    final request = _captureRequest(image, generation!);
    if (request == null) {
      if (existing is KittyImageReady) existing.image.dispose();
      _requestTokens.remove(imageId);
      _queuedRequests.remove(imageId);
      _entries[imageId] = const KittyImageUnsupported();
      return;
    }
    if (existing is! KittyImageReady) {
      _entries[imageId] = const KittyImagePending();
    }
    final requestToken = ++_nextRequestToken;
    _requestTokens[imageId] = requestToken;
    final queued = request.withToken(requestToken);
    if (_activeRequest == null) {
      _startDecode(queued);
    } else {
      // Keep native-to-Dart copies valid, but defer RGB expansion and Flutter
      // decoding. Eviction can then discard superseded animation frames before
      // they consume UI-isolate and raster-thread work.
      // Refreshing an ID moves it behind other live work so one animated image
      // cannot starve independent queued placements.
      _queuedRequests
        ..remove(imageId)
        ..[imageId] = queued;
    }
  }

  _KittyDecodeRequest? _captureRequest(KittyImage image, int generation) {
    if (image.compression != .none) return null;
    final format = image.format;
    switch (format) {
      case KittyImageFormat.rgba:
      case KittyImageFormat.rgb:
        final pixelCount = image.width * image.height;
        final bytesPerPixel = format == .rgb ? 3 : 4;
        final byteLength = pixelCount * bytesPerPixel;
        // A request that starts immediately consumes RGB synchronously during
        // expansion. Queued requests still allocate independent snapshots so
        // later terminal mutations cannot alter their pixels.
        final src = format == .rgb && _activeRequest == null
            ? _copyRgbPixels(image, byteLength)
            : _copyPixels(image, byteLength);
        if (src.length < byteLength) return null;
        return _KittyDecodeRequest(
          imageId: image.id,
          generation: generation,
          width: image.width,
          height: image.height,
          format: format,
          pixels: src,
        );
      case KittyImageFormat.png:
      case KittyImageFormat.grayAlpha:
      case KittyImageFormat.gray:
        return null;
    }
  }

  void _completeDecode(_KittyDecodeRequest request, Image decoded) {
    if (identical(_activeRequest, request)) _activeRequest = null;
    try {
      if (_requestedGenerations[request.imageId] == request.generation &&
          _requestTokens[request.imageId] == request.token) {
        final previous = _entries[request.imageId];
        _requestTokens.remove(request.imageId);
        _entries[request.imageId] = KittyImageReady(
          decoded,
          generation: request.generation,
        );
        if (previous is KittyImageReady) previous.image.dispose();
        _onImageReady();
      } else {
        decoded.dispose();
      }
    } finally {
      _startNextDecode();
    }
  }

  Uint8List _copyRgbPixels(KittyImage image, int byteLength) {
    final destination = _rgbSourceBuffer?.length == byteLength
        ? _rgbSourceBuffer!
        : Uint8List(byteLength);
    final written = image.copyPixelDataInto(destination);
    _rgbSourceBuffer = destination;
    return written == destination.length
        ? destination
        : Uint8List.sublistView(destination, 0, written);
  }

  Uint8List _copyPixels(KittyImage image, int byteLength) {
    final destination = Uint8List(byteLength);
    final written = image.copyPixelDataInto(destination);
    return written == destination.length
        ? destination
        : Uint8List.sublistView(destination, 0, written);
  }

  void _startDecode(_KittyDecodeRequest request) {
    _activeRequest = request;
    try {
      // Only one decode is active, and its callback marks input consumption.
      // Reusing this staging buffer removes one full-frame allocation without
      // sharing mutable pixels between overlapping decoders.
      final pixels = request.takeRgba(_rgbDecodeBuffer);
      if (request.format == .rgb) _rgbDecodeBuffer = pixels;
      _decodeImage(
        pixels,
        request.width,
        request.height,
        .rgba8888,
        (decoded) => _completeDecode(request, decoded),
      );
    } catch (_) {
      if (identical(_activeRequest, request)) _activeRequest = null;
      rethrow;
    }
  }

  void _startNextDecode() {
    var decodeFailed = false;
    while (_activeRequest == null && _queuedRequests.isNotEmpty) {
      final imageId = _queuedRequests.keys.first;
      final request = _queuedRequests.remove(imageId)!;
      if (_requestedGenerations[imageId] != request.generation ||
          _requestTokens[imageId] != request.token) {
        continue;
      }
      try {
        _startDecode(request);
      } on Object {
        _requestedGenerations.remove(imageId);
        _requestTokens.remove(imageId);
        if (_entries[imageId] is KittyImagePending) _entries.remove(imageId);
        decodeFailed = true;
      }
    }
    if (decodeFailed) _onImageReady();
  }
}

/// Result of a cache lookup for a decoded image.
sealed class KittyImageCacheEntry {
  const KittyImageCacheEntry();
}

/// A decode is in flight. A later repaint will see a [KittyImageReady].
final class KittyImagePending extends KittyImageCacheEntry {
  const KittyImagePending();
}

/// The image is decoded and ready to draw.
final class KittyImageReady extends KittyImageCacheEntry {
  final Image image;
  final int generation;

  const KittyImageReady(this.image, {required this.generation});
}

/// The image was rejected due to an unsupported format or compression.
final class KittyImageUnsupported extends KittyImageCacheEntry {
  const KittyImageUnsupported();
}

final class _KittyDecodeRequest {
  final int imageId;
  final int generation;
  final int width;
  final int height;
  final KittyImageFormat format;
  Uint8List? pixels;
  final int token;

  _KittyDecodeRequest({
    required this.imageId,
    required this.generation,
    required this.width,
    required this.height,
    required this.format,
    required this.pixels,
    this.token = 0,
  });

  Uint8List takeRgba(Uint8List? reusable) {
    final source = pixels!;
    pixels = null;
    if (format == .rgba) return source;
    final pixelCount = width * height;
    final byteLength = pixelCount * 4;
    final result = reusable?.length == byteLength
        ? reusable!
        : Uint8List(byteLength);
    final rgba = Uint32List.view(result.buffer);
    // Advance the RGB offset once per pixel. Recomputing `pixel * 3` for each
    // channel measurably increases this per-frame conversion cost in profile.
    if (Endian.host == .little) {
      var sourceOffset = 0;
      for (var pixel = 0; pixel < pixelCount; pixel++) {
        rgba[pixel] =
            source[sourceOffset] |
            source[sourceOffset + 1] << 8 |
            source[sourceOffset + 2] << 16 |
            0xff000000;
        sourceOffset += 3;
      }
    } else {
      var sourceOffset = 0;
      for (var pixel = 0; pixel < pixelCount; pixel++) {
        rgba[pixel] =
            source[sourceOffset] << 24 |
            source[sourceOffset + 1] << 16 |
            source[sourceOffset + 2] << 8 |
            0xff;
        sourceOffset += 3;
      }
    }
    return result;
  }

  _KittyDecodeRequest withToken(int token) => _KittyDecodeRequest(
    imageId: imageId,
    generation: generation,
    width: width,
    height: height,
    format: format,
    pixels: pixels,
    token: token,
  );
}
