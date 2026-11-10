import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/services/http_environment_catalog.dart';

class HttpCodeLink {
  const HttpCodeLink(this.start, this.end, {this.path, this.line, this.url});

  final int start;
  final int end;
  final String? path;
  final int? line; // base 1
  final String? url;
}

/// Resolve apenas referências de variáveis e verbos HTTP. Cabeçalhos não são
/// links, mesmo quando o editor genérico reconheceria a palavra sob o mouse.
class HttpCodeNavigation {
  static final _inline = RegExp(r'^\s*@([A-Za-z_][A-Za-z0-9_.-]*)\s*=');
  static final _method = RegExp(
    r'^\s*(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE)\b',
    caseSensitive: false,
  );

  static HttpCodeLink? linkAt({
    required String displayText,
    required int offset,
    required String sourceText,
    required String sourcePath,
    required int sourceLine,
    required String? environment,
    required HttpEnvironmentCatalog catalog,
    Map<String, String> globals = const {},
    Map<String, String> overrides = const {},
  }) {
    if (offset < 0 || offset >= displayText.length) return null;
    final start = displayText.lastIndexOf('\n', offset - 1) + 1;
    final endBreak = displayText.indexOf('\n', offset);
    final end = endBreak < 0 ? displayText.length : endBreak;
    final line = displayText.substring(start, end);
    if (line.trimLeft().startsWith('#') || line.trimLeft().startsWith('//')) {
      return null;
    }

    for (final match in HttpDocument.interpolation.allMatches(line)) {
      final from = start + match.start;
      final to = start + match.end;
      if (offset < from || offset >= to) continue;
      final name = match.group(1)!;
      final sourceLines = sourceText.split('\n');
      for (var i = 0; i < sourceLines.length; i++) {
        final declaration = _inline.firstMatch(sourceLines[i]);
        if (declaration?.group(1) == name) {
          return HttpCodeLink(from, to, path: sourcePath, line: i + 1);
        }
      }
      final definition = catalog.definitionFor(environment, name);
      if (definition != null) {
        return HttpCodeLink(
          from,
          to,
          path: definition.path,
          line: definition.line,
        );
      }
      return null;
    }

    final verb = _method.firstMatch(line);
    if (verb == null ||
        offset < start + verb.start ||
        offset >= start + verb.end) {
      return null;
    }
    final document = HttpDocument.parse(sourceText);
    for (final request in document.requests) {
      if (request.requestLine != sourceLine) continue;
      final resolved = document.resolveRequest(
        request,
        environment: catalog.valuesFor(environment),
        globals: globals,
        overrides: overrides,
      );
      final uri = Uri.tryParse(resolved.url);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          !resolved.url.contains('{{')) {
        return HttpCodeLink(
          start + verb.start,
          start + verb.end,
          url: uri.toString(),
        );
      }
    }
    return null;
  }
}
