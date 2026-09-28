/// Incrementally converts line feeds to terminal-friendly CRLF without
/// changing existing CRLF or buffering whole lines.
///
/// A trailing CR is held for one chunk so `"\r"` + `"\n"` remains one line
/// ending. Bare CR is preserved for progress output that intentionally rewrites
/// the current line. Memory use is constant even for arbitrarily long lines.
class TerminalLineEndingNormalizer {
  bool _pendingCr = false;

  String add(String chunk) {
    if (chunk.isEmpty) return '';
    final out = StringBuffer();
    var i = 0;
    if (_pendingCr) {
      _pendingCr = false;
      if (chunk.codeUnitAt(0) == _lf) {
        out.write('\r\n');
        i = 1;
      } else {
        out.write('\r');
      }
    }
    while (i < chunk.length) {
      final code = chunk.codeUnitAt(i);
      if (code == _cr) {
        if (i + 1 == chunk.length) {
          _pendingCr = true;
        } else if (chunk.codeUnitAt(i + 1) == _lf) {
          out.write('\r\n');
          i++;
        } else {
          out.write('\r');
        }
      } else if (code == _lf) {
        out.write('\r\n');
      } else {
        out.writeCharCode(code);
      }
      i++;
    }
    return out.toString();
  }

  /// Flushes a trailing bare CR when the source stream ends.
  String close() {
    if (!_pendingCr) return '';
    _pendingCr = false;
    return '\r';
  }

  static const int _cr = 13;
  static const int _lf = 10;
}
