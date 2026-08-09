import 'package:flutter/widgets.dart';

/// Cor de texto/ícone legível **sobre** [background].
///
/// Existe porque o Cockpit deixou de ter só duas paletas fixas: com tema
/// customizável, `accent`/`error` podem ser claros, e um `Colors.white`
/// hardcoded vira texto invisível. A escolha é por luminância relativa
/// (WCAG 2.x): abaixo do ponto de virada, texto claro; acima, texto escuro.
///
/// **O limiar não é 0.5.** Contraste WCAG não é linear na luminância, então o
/// ponto onde `light` e `dark` contrastam *igual* sai da equação
/// `1.05 / (L + 0.05) == (L + 0.05) / (Ldark + 0.05)`. Com o `dark` padrão
/// (`#1A1A1F`, luminância ≈ 0.012) isso dá **L ≈ 0.205** — e não 0.5, nem o
/// 0.45 que este arquivo usou até o Violet aparecer.
///
/// Aquele 0.45 escolhia branco para qualquer cor de marca razoável, inclusive
/// as claras demais para isso: o roxo `#9B7BF7` recebia branco a 3,2:1 quando
/// texto escuro daria 5,4:1.
///
/// O valor abaixo fica um passo **acima** do ponto de virada, de propósito.
/// Essa folga cobre as superfícies vermelhas de ação destrutiva (`#E5484D`,
/// luminância ≈ 0.216), onde o branco está 0,4 ponto atrás do texto escuro em
/// contraste mas é a convenção universal — inverter ali pareceria defeito. É a
/// única concessão a gosto na função; fora dessa faixa estreita, quem manda é a
/// medida.
const double _lightTextThreshold = 0.24;

Color onColor(
  Color background, {
  Color light = const Color(0xFFFFFFFF),
  Color dark = const Color(0xFF1A1A1F),
}) => background.computeLuminance() < _lightTextThreshold ? light : dark;

/// Razão de contraste WCAG entre [a] e [b] (1.0 a 21.0). Usada pela validação
/// de temas importados: abaixo de 4.5 o par não passa em AA para texto normal.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}
