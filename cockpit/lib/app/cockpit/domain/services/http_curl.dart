import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:path/path.dart' as p;

/// Exports a request as a POSIX shell command without executing its scripts.
abstract final class HttpCurl {
  /// Unlike the editor's execution fallback, only matches a containing request.
  static int requestIndexAtLine(HttpDocument document, int line) {
    for (var i = 0; i < document.requests.length; i++) {
      final request = document.requests[i];
      if (line >= request.startLine && line < request.endLine) return i;
    }
    return -1;
  }

  static String generate(HttpRequestSpec request, {String baseDir = ''}) {
    final parts = <String>[
      'curl --globoff',
      request.method == 'HEAD'
          ? '--head'
          : '--request ${quote(request.method)}',
      '--url ${quote(request.url)}',
      for (final header in request.headers)
        '--header ${quote('${header.name}: ${header.value}')}',
    ];
    if (request.bodyFile != null) {
      final path = baseDir.isEmpty || p.isAbsolute(request.bodyFile!)
          ? request.bodyFile!
          : p.normalize(p.join(baseDir, request.bodyFile!));
      parts.add('--data-binary ${quote('@$path')}');
    } else if (request.body != null) {
      // --data-raw preserves newlines and never interprets a leading @ as a file.
      parts.add('--data-raw ${quote(request.body!)}');
    }
    return parts.join(' \\\n  ');
  }

  static String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
