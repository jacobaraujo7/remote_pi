import 'dart:collection';

/// Buffer textual limitado que remove chunks da frente sem copiar todo o
/// histórico a cada trim. A materialização contígua acontece apenas no flush.
final class BoundedTextBuffer {
  BoundedTextBuffer({required this.maxLength, int? retainedLength})
    : retainedLength = retainedLength ?? maxLength * 3 ~/ 4 {
    if (maxLength <= 0 ||
        this.retainedLength <= 0 ||
        this.retainedLength >= maxLength) {
      throw ArgumentError('expected 0 < retainedLength < maxLength');
    }
  }

  final int maxLength;
  final int retainedLength;
  final ListQueue<String> _chunks = ListQueue<String>();
  int _headOffset = 0;
  int _length = 0;

  int get length => _length;

  void add(String value) {
    if (value.isEmpty) return;
    _chunks.addLast(value);
    _length += value.length;
    if (_length > maxLength) _trimFront(_length - retainedLength);
  }

  void _trimFront(int count) {
    var remaining = count;
    while (remaining > 0 && _chunks.isNotEmpty) {
      final available = _chunks.first.length - _headOffset;
      if (remaining >= available) {
        remaining -= available;
        _length -= available;
        _chunks.removeFirst();
        _headOffset = 0;
        continue;
      }
      var cut = _headOffset + remaining;
      // Nunca deixe o buffer começar no low surrogate de um par UTF-16.
      final chunk = _chunks.first;
      if (cut < chunk.length &&
          cut > 0 &&
          _isHighSurrogate(chunk.codeUnitAt(cut - 1)) &&
          _isLowSurrogate(chunk.codeUnitAt(cut))) {
        cut++;
        remaining++;
      }
      _headOffset = cut;
      _length -= remaining;
      remaining = 0;
    }
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  @override
  String toString() {
    final out = StringBuffer();
    var first = true;
    for (final chunk in _chunks) {
      out.write(first ? chunk.substring(_headOffset) : chunk);
      first = false;
    }
    return out.toString();
  }
}
