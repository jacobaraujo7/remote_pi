/// Um arquivo `.http`: variáveis `@nome = valor` e requests separados por
/// `###`, no dialeto do REST Client (VS Code) / HTTP Client (JetBrains).
///
/// ```http
/// @baseUrl = https://api.example.com
///
/// ### Listar usuários
/// GET {{baseUrl}}/users?page=1
/// Accept: application/json
///
/// ### Criar usuário
/// POST {{baseUrl}}/users
/// Content-Type: application/json
///
/// {"name": "Jacob"}
/// ```
///
/// O parse é **tolerante por design**: linha que não casa com nada é ignorada
/// em vez de derrubar o arquivo — um `.http` sendo digitado passa a maior parte
/// do tempo inválido. Escopo suportado: `###` (separador + nome), `@var`,
/// `{{var}}`, request-line com verbo + URL (versão `HTTP/1.1` opcional),
/// headers, body e `< arquivo` (body importado de arquivo). Fora do escopo:
/// `> saida.json`, blocos gRPC/GraphQL/WebSocket.
library;

/// Um par header, preservando a ordem e permitindo repetição (`Set-Cookie`).
typedef HttpHeader = ({String name, String value});

/// Um request declarado no arquivo.
class HttpRequestSpec {
  const HttpRequestSpec({
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    this.bodyFile,
    this.preScript,
    this.postScript,
    required this.startLine,
    required this.requestLine,
    required this.endLine,
  });

  /// Rótulo do `###` (ou `# @name`); vazio quando o request não foi nomeado —
  /// a UI mostra `method url` nesse caso.
  final String name;

  final String method;
  final String url;
  final List<HttpHeader> headers;

  /// Body literal do arquivo (`null` = sem body).
  final String? body;

  /// Caminho de `< ./body.json` — resolvido contra a pasta do `.http` na hora
  /// de executar (o domínio não toca em disco).
  final String? bodyFile;
  final String? preScript;
  final String? postScript;

  /// Faixa de linhas `[startLine, endLine)`, base 0 — usada para casar o cursor
  /// do editor com o request corrente.
  final int startLine;

  /// Linha do verbo HTTP, usada para posicionar a ação de executar no editor.
  final int requestLine;
  final int endLine;

  /// Rótulo curto para a UI e para a CLI.
  String get label => name.isNotEmpty ? name : '$method $url';

  HttpRequestSpec copyWith({
    String? url,
    List<HttpHeader>? headers,
    String? body,
  }) => HttpRequestSpec(
    name: name,
    method: method,
    url: url ?? this.url,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    bodyFile: bodyFile,
    preScript: preScript,
    postScript: postScript,
    startLine: startLine,
    requestLine: requestLine,
    endLine: endLine,
  );
}

/// O arquivo inteiro já dividido em variáveis + requests.
class HttpDocument {
  const HttpDocument({required this.variables, required this.requests});

  /// `@nome = valor`, na ordem de declaração. Uma variável pode referenciar
  /// outra declarada **antes** dela (ver [resolve]).
  final Map<String, String> variables;

  final List<HttpRequestSpec> requests;

  static final _varLine = RegExp(
    r'^\s*@([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.*)$',
  );
  static final _separator = RegExp(r'^\s*###+\s*(.*)$');
  static final _namePragma = RegExp(r'^\s*(?://|#)\s*@name\s+(.+)$');
  static final _comment = RegExp(r'^\s*(?://|#)');
  static final _bodyFileLine = RegExp(r'^\s*<\s+(\S.*)$');
  static final _headerLine = RegExp(
    r'^\s*([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$',
  );
  static final _requestLine = RegExp(
    r'^\s*(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE)\s+(\S+)(?:\s+HTTP/[\d.]+)?\s*$',
    caseSensitive: false,
  );

  /// Interpolação `{{nome}}` — nome vazio ou com `{`/`}` não casa.
  static final interpolation = RegExp(r'\{\{\s*([^{}\s]+)\s*\}\}');

  static HttpDocument parse(String content) {
    final lines = content.split('\n');
    final vars = <String, String>{};
    final requests = <HttpRequestSpec>[];

    // Estado do request em construção.
    String name = '';
    String? method;
    String? url;
    var headers = <HttpHeader>[];
    var bodyLines = <String>[];
    String? bodyFile;
    final preScripts = <String>[];
    final postScripts = <String>[];
    var inBody = false;
    var start = 0;
    var requestLine = 0;

    void flush(int end) {
      if (method != null && url != null) {
        // Linhas em branco no fim do body são cosméticas (o `###` seguinte
        // costuma vir depois de uma).
        while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
          bodyLines.removeLast();
        }
        requests.add(
          HttpRequestSpec(
            name: name,
            method: method!.toUpperCase(),
            url: url!,
            headers: List.unmodifiable(headers),
            body: bodyLines.isEmpty ? null : bodyLines.join('\n'),
            bodyFile: bodyFile,
            preScript: preScripts.isEmpty ? null : preScripts.join('\n'),
            postScript: postScripts.isEmpty ? null : postScripts.join('\n'),
            startLine: start,
            requestLine: requestLine,
            endLine: end,
          ),
        );
      }
      name = '';
      method = null;
      url = null;
      headers = <HttpHeader>[];
      bodyLines = <String>[];
      bodyFile = null;
      preScripts.clear();
      postScripts.clear();
      inBody = false;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      final sep = _separator.firstMatch(line);
      if (sep != null) {
        flush(i);
        start = i;
        name = sep.group(1)!.trim();
        continue;
      }

      // Os delimitadores de script têm prioridade sobre o body e sobre
      // `< arquivo`. O conteúdo JS nunca entra no payload HTTP.
      final scriptStart = RegExp(r'^\s*([<>])\s*\{%').firstMatch(line);
      if (scriptStart != null) {
        final parts = <String>[];
        var rest = line.substring(scriptStart.end);
        while (true) {
          final end = rest.indexOf('%}');
          if (end >= 0) {
            parts.add(rest.substring(0, end));
            break;
          }
          parts.add(rest);
          if (i + 1 >= lines.length) break;
          rest = lines[++i];
        }
        final script = parts.join('\n').trim();
        if (scriptStart.group(1) == '<') {
          preScripts.add(script);
        } else if (method != null) {
          postScripts.add(script);
        }
        continue;
      }

      // Dentro do body tudo é literal — inclusive `#`, que em JSON/YAML é dado.
      if (inBody) {
        bodyLines.add(line);
        continue;
      }

      final pragma = _namePragma.firstMatch(line);
      if (pragma != null) {
        name = pragma.group(1)!.trim();
        continue;
      }
      if (_comment.hasMatch(line)) continue;

      final v = _varLine.firstMatch(line);
      if (v != null && method == null) {
        vars[v.group(1)!] = v.group(2)!.trim();
        continue;
      }

      final req = _requestLine.firstMatch(line);
      if (req != null) {
        // Request sem `###` antes (arquivo de um request só, ou requests
        // coladas) ainda vira um item próprio.
        if (method != null) {
          flush(i);
          start = i;
        } else if (requests.isEmpty && headers.isEmpty && preScripts.isEmpty) {
          start = i;
        }
        method = req.group(1);
        url = req.group(2);
        requestLine = i;
        continue;
      }

      if (method == null) continue; // preâmbulo solto — ignora

      // JetBrains HTTP Client: parâmetros da URL podem continuar nas linhas
      // imediatamente abaixo do verbo. Não incluem espaços de indentação e
      // não entram no body nem nos headers.
      final continuation = line.trim();
      if (headers.isEmpty &&
          bodyFile == null &&
          (continuation.startsWith('?') || continuation.startsWith('&'))) {
        url = '${url!}$continuation';
        continue;
      }

      final file = _bodyFileLine.firstMatch(line);
      if (file != null) {
        bodyFile = file.group(1)!.trim();
        continue;
      }

      if (line.trim().isEmpty) {
        // Linha em branco depois dos headers abre o body. Antes deles (logo
        // após a request-line sem header nenhum) também.
        inBody = true;
        continue;
      }

      final h = _headerLine.firstMatch(line);
      if (h != null) {
        headers.add((name: h.group(1)!, value: h.group(2)!.trim()));
        continue;
      }
      // Linha que não é header nem branco depois da request-line: trata como
      // começo de body (tolerância — é o erro de digitação mais comum).
      inBody = true;
      bodyLines.add(line);
    }
    flush(lines.length);

    return HttpDocument(
      variables: Map.unmodifiable(vars),
      requests: List.unmodifiable(requests),
    );
  }

  /// Índice do request que contém [line] (base 0). `-1` se o arquivo não tem
  /// request nenhum; o último request vale para tudo que vier depois dele.
  int requestIndexAtLine(int line) {
    if (requests.isEmpty) return -1;
    for (var i = requests.length - 1; i >= 0; i--) {
      if (line >= requests[i].startLine) return i;
    }
    return 0;
  }

  /// Substitui `{{nome}}` por [variables], resolvendo referências entre
  /// variáveis na ordem de declaração. Nome desconhecido fica **intacto** — a
  /// execução acusa como variável não resolvida em vez de mandar `{{x}}` no ar.
  String interpolate(
    String input, {
    Map<String, String> extra = const {},
    Map<String, String> requestVariables = const {},
    Map<String, String> overrides = const {},
  }) {
    final resolved = <String, String>{
      ...extra,
      ...requestVariables,
      ...overrides,
    };
    for (final e in variables.entries) {
      if (!requestVariables.containsKey(e.key) &&
          !overrides.containsKey(e.key)) {
        resolved[e.key] = _expand(e.value, resolved);
      }
    }
    return _expand(input, resolved);
  }

  static String _expand(String input, Map<String, String> vars) => input
      .replaceAllMapped(interpolation, (m) => vars[m.group(1)!] ?? m.group(0)!);

  /// [spec] com URL, headers e body já interpolados.
  HttpRequestSpec resolveRequest(
    HttpRequestSpec spec, {
    Map<String, String> environment = const {},
    Map<String, String> globals = const {},
    Map<String, String> requestVariables = const {},
    Map<String, String> overrides = const {},
  }) {
    final values = <String, String>{
      ...environment,
      ...globals,
      ...requestVariables,
      ...overrides,
    };
    for (final e in variables.entries) {
      if (!requestVariables.containsKey(e.key) &&
          !overrides.containsKey(e.key)) {
        values[e.key] = _expand(e.value, values);
      }
    }
    String resolve(String input) => _expand(input, values);
    return spec.copyWith(
      url: resolve(spec.url),
      headers: [
        for (final h in spec.headers) (name: h.name, value: resolve(h.value)),
      ],
      body: spec.body == null ? null : resolve(spec.body!),
    );
  }

  /// Nomes de variáveis ainda não resolvidas em [spec] (depois de
  /// [resolveRequest]) — vira erro antes de tocar a rede.
  static List<String> unresolvedIn(HttpRequestSpec spec) => [
    for (final m in interpolation.allMatches(
      [
        spec.url,
        for (final h in spec.headers) h.value,
        spec.body ?? '',
      ].join('\n'),
    ))
      m.group(1)!,
  ];

  /// Placeholders sem valor no editor, ignorando comentários de linha.
  /// Offsets são UTF-16, iguais aos usados pelo `TextEditingController`.
  static List<({int start, int end, String name})> unresolvedPlaceholders(
    String source, {
    Map<String, String> environment = const {},
    Map<String, String> globals = const {},
    Map<String, String> overrides = const {},
    Map<int, Map<String, String>> requestVariablesByIndex = const {},
  }) {
    final doc = HttpDocument.parse(source);
    final missing = <({int start, int end, String name})>[];
    var lineStart = 0;
    var lineNumber = 0;
    var inScript = false;
    for (final line in source.split('\n')) {
      final requestIndex = doc.requestIndexAtLine(lineNumber);
      final requestVariables = requestIndex < 0
          ? const <String, String>{}
          : requestVariablesByIndex[requestIndex] ?? const <String, String>{};
      final trimmed = line.trimLeft();
      final startsScript = RegExp(r'^[<>]\s*\{%').hasMatch(trimmed);
      if (startsScript) inScript = true;
      if (!inScript && !trimmed.startsWith('#') && !trimmed.startsWith('//')) {
        for (final match in interpolation.allMatches(line)) {
          final token = match.group(0)!;
          if (doc.interpolate(
                token,
                extra: {...environment, ...globals},
                requestVariables: requestVariables,
                overrides: overrides,
              ) ==
              token) {
            missing.add((
              start: lineStart + match.start,
              end: lineStart + match.end,
              name: match.group(1)!,
            ));
          }
        }
      }
      if (inScript && line.contains('%}')) inScript = false;
      lineStart += line.length + 1;
      lineNumber++;
    }
    return missing;
  }
}
