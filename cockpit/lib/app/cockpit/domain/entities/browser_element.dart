/// Elemento interativo e visível da página, devolvido por `cockpit browser
/// read` (plano 61). O `id` é efêmero e só vale contra o `read` mais recente
/// daquela aba — [BrowserAutomationException] com `kind: 'stale_element_id'`
/// é o sinal de que ele expirou (novo `read`, ou a página navegou).
class BrowserElement {
  const BrowserElement({
    required this.id,
    required this.role,
    required this.text,
    required this.rect,
  });

  factory BrowserElement.fromJson(Map<String, dynamic> json) => BrowserElement(
    id: json['id'] as String,
    role: json['role'] as String,
    text: json['text'] as String? ?? '',
    rect: BrowserElementRect.fromJson(json['rect'] as Map<String, dynamic>),
  );

  /// Id efêmero, único dentro da mesma leitura (`data-cockpit-id` no DOM).
  final String id;

  /// `link`, `button`, `textbox`, `combobox`, `generic` — de `role=` explícito
  /// ou inferido da tag (ver `browser_bridge.js`).
  final String role;

  /// Texto visível/label do elemento, truncado a um tamanho razoável.
  final String text;

  /// Retângulo do elemento no viewport (px CSS).
  final BrowserElementRect rect;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    'rect': rect.toJson(),
  };
}

/// Retângulo `{x, y, w, h}` em px CSS, vindo de `getBoundingClientRect()`.
class BrowserElementRect {
  const BrowserElementRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory BrowserElementRect.fromJson(Map<String, dynamic> json) =>
      BrowserElementRect(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );

  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

/// Erro tipado dos subcomandos `browser *` (mesma forma de [DbQueryException]
/// em `db_result.dart`): `kind` estável pra CLI reconstruir
/// `{"error":{kind,message}}`, `message` livre pro humano/agente.
class BrowserAutomationException implements Exception {
  const BrowserAutomationException(this.kind, this.message);

  /// `no_browser_tab` | `tab_closed` | `stale_element_id` | `eval_failed` |
  /// `ambiguous_browser_tab`.
  final String kind;
  final String message;

  @override
  String toString() => 'BrowserAutomationException($kind): $message';
}
