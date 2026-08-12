/// Descoberta de famílias de fonte disponíveis para o seletor das Configurações.
///
/// O Flutter não expõe a lista de fontes do sistema, e não há plugin no
/// projeto que o faça (seria código nativo nos três runners: CoreText,
/// DirectWrite, fontconfig). A saída aqui é indireta e 100% Dart: uma lista de
/// candidatas conhecidas é **medida** com o próprio motor de texto, e a que
/// mede igual ao fallback é considerada ausente.
///
/// Isso cobre bem o caso real (escolher entre as monoespaçadas boas que a
/// máquina tem) sem travar a feature esperando código nativo. Um dia o nível
/// nativo pode substituir [_candidates] mantendo o resto igual.
library;

import 'dart:io' show Platform;

import 'package:flutter/painting.dart';

/// Uma família candidata, já classificada pela medição.
class FontOption {
  const FontOption({
    required this.family,
    required this.monospaced,
    required this.bundled,
  });

  final String family;

  /// Avanço de `i` igual ao de `M`: serve para terminal e código.
  final bool monospaced;

  /// Vem com o app (via `google_fonts`), então existe em qualquer máquina.
  final bool bundled;

  @override
  bool operator ==(Object other) =>
      other is FontOption &&
      other.family == family &&
      other.monospaced == monospaced &&
      other.bundled == bundled;

  @override
  int get hashCode => Object.hash(family, monospaced, bundled);

  @override
  String toString() => 'FontOption($family, mono: $monospaced)';
}

/// Nome que garantidamente não existe: mede o fallback do motor de texto.
/// Qualquer família ausente resolve para o mesmo tipo, então mede igual a ele.
const _absentFamilySentinel = '__cockpit_absent_family__';

/// Famílias que o app serve por conta própria (`google_fonts`), então estão
/// disponíveis independentemente do que a máquina tem instalado.
const _appFonts = <String>['JetBrains Mono', 'Space Grotesk', 'Hanken Grotesk'];

/// Candidatas por plataforma. Não é exaustivo por definição — é uma lista de
/// suspeitas comuns, e o texto livre continua existindo para o resto.
List<String> _candidates() => <String>[
  ..._appFonts,
  // Monoespaçadas populares, instaláveis em qualquer sistema.
  'Fira Code',
  'Fira Mono',
  'IBM Plex Mono',
  'Source Code Pro',
  'Roboto Mono',
  'Ubuntu Mono',
  'Inconsolata',
  'Hack',
  'Iosevka',
  'Cascadia Code',
  'Cascadia Mono',
  'MesloLGS NF',
  'Victor Mono',
  'Anonymous Pro',
  'PT Mono',
  'Courier New',
  if (Platform.isMacOS) ...[
    'SF Mono',
    'Menlo',
    'Monaco',
    'Andale Mono',
    'Helvetica Neue',
    'SF Pro Text',
    'Avenir Next',
  ],
  if (Platform.isWindows) ...[
    'Consolas',
    'Lucida Console',
    'Segoe UI',
    'Segoe UI Mono',
    'Calibri',
    'Arial',
  ],
  if (Platform.isLinux) ...[
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'Ubuntu',
    'Cantarell',
  ],
  // Sans comuns para a fonte de interface.
  'Inter',
  'Roboto',
  'Open Sans',
  'Lato',
  'Nunito Sans',
];

/// Mede o avanço de [text] na [family] (`null` = fallback do motor).
double _advance(String text, String? family) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: 48),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Se [family] resolve para ela mesma, e não para o fallback.
///
/// Heurística, não garantia: uma família cujas métricas coincidam **exatamente**
/// com as do fallback daria falso negativo. Na prática isso só acontece quando
/// a família *é* o fallback, e o custo do erro é baixo (a fonte fica fora da
/// lista, mas o texto livre continua aceitando o nome).
bool isFontAvailable(String family) {
  // Texto com formas variadas: aumenta a chance de duas famílias diferentes
  // divergirem em pelo menos um glifo.
  const probe = 'MWiljq10OÇã';
  final absent = _advance(probe, _absentFamilySentinel);
  final requested = _advance(probe, family);
  return (requested - absent).abs() > 0.01;
}

/// Se [family] tem avanço uniforme (é monoespaçada).
bool isFontMonospaced(String family) {
  final narrow = _advance('i', family);
  final wide = _advance('M', family);
  return (narrow - wide).abs() < 0.01;
}

/// Famílias disponíveis nesta máquina, ordenadas: as do app primeiro (sempre
/// presentes), depois o resto em ordem alfabética.
///
/// A medição é síncrona e barata (algumas dezenas de layouts de texto curto),
/// mas ainda assim vale cachear por chamada de tela em vez de por frame.
List<FontOption> availableFonts() {
  final seen = <String>{};
  final options = <FontOption>[];

  for (final family in _candidates()) {
    if (!seen.add(family)) continue;
    final bundled = _appFonts.contains(family);
    // As do app são servidas pelo `google_fonts`; podem ainda não ter sido
    // baixadas no primeiro uso, então não as submetemos ao teste de presença.
    if (!bundled && !isFontAvailable(family)) continue;
    options.add(
      FontOption(
        family: family,
        monospaced: isFontMonospaced(family),
        bundled: bundled,
      ),
    );
  }

  options.sort((a, b) {
    if (a.bundled != b.bundled) return a.bundled ? -1 : 1;
    return a.family.toLowerCase().compareTo(b.family.toLowerCase());
  });
  return options;
}
