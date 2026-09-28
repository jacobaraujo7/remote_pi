// Desembrulha o que vem em volta da linha antes do parser ver o conteúdo:
// `flutter: `, logcat, docker compose, concurrently, timestamps. É a parte
// chata de verdade (plano 66, contrato do parser, passo 2).

class Unwrapped {
  const Unwrapped(this.text, {this.service});
  final String text;

  /// Nome do serviço quando o prefixo o carrega (docker compose `api-1 |`).
  final String? service;
}

final _builtins = <RegExp>[
  // flutter run (desktop/iOS) e logcat
  RegExp(r'^flutter:\s?'),
  RegExp(r'^[IWEDVF]/flutter\s*\(\s*\d+\):\s?'),
  // concurrently / turbo
  RegExp(r'^\[\d+\]\s'),
  RegExp(r'^[a-z][\w:@./-]*:(?:build|dev|start|test)?:\s'),
  // timestamps à esquerda
  RegExp(
    r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+',
  ),
  RegExp(r'^\[\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\]\s?'),
  RegExp(r'^\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s+(?=[\[{A-Za-z#])'),
];

// docker compose: `api-1  | ...` / `web | ...` (nome antes do pipe).
final _compose = RegExp(r'^([a-zA-Z][\w.-]*)\s+\|\s?');

/// Remove prefixos conhecidos (e os [extra] do `.cockpit/telemetry.json`),
/// repetidamente, porque eles se empilham (`api-1 | 2026-... {json}`).
Unwrapped unwrapPrefixes(String line, {List<RegExp> extra = const []}) {
  var text = line;
  String? service;
  for (var pass = 0; pass < 4; pass++) {
    var changed = false;
    final c = _compose.firstMatch(text);
    if (c != null) {
      service ??= c.group(1);
      text = text.substring(c.end);
      changed = true;
    }
    for (final re in extra.followedBy(_builtins)) {
      final m = re.firstMatch(text);
      if (m != null && m.end > 0) {
        text = text.substring(m.end);
        changed = true;
      }
    }
    if (!changed) break;
  }
  return Unwrapped(text, service: service);
}
