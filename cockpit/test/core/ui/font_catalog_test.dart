import 'package:cockpit/app/core/ui/font_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // O ambiente de teste do Flutter registra só uma fonte (Ahem) e resolve
  // qualquer família para ela. Isso limita o que dá para afirmar aqui: o que se
  // testa é a *forma* das heurísticas e dos invariantes da lista, não quais
  // fontes existem numa máquina real (isso é validação manual).

  test('família inexistente não é reportada como disponível', () {
    expect(isFontAvailable('__definitivamente_nao_existe__'), isFalse);
  });

  test('a detecção de monoespaçada compara avanços, não nomes', () {
    // No harness tudo resolve para Ahem, que É monoespaçada: o valor esperado
    // é o mesmo para qualquer nome, e é isso que se afirma — a função responde
    // pela métrica, sem consultar tabela de nomes conhecidos.
    expect(isFontMonospaced('Menlo'), isFontMonospaced('Helvetica'));
  });

  group('availableFonts', () {
    test('inclui as fontes do app, que não dependem da máquina', () {
      final families = availableFonts().map((o) => o.family).toList();

      expect(families, contains('JetBrains Mono'));
      expect(families, contains('Space Grotesk'));
      expect(families, contains('Hanken Grotesk'));
    });

    test('não repete famílias', () {
      final families = availableFonts().map((o) => o.family).toList();

      expect(families.toSet().length, families.length);
    });

    test('as do app vêm primeiro e o resto sai em ordem alfabética', () {
      final options = availableFonts();
      final firstNonBundled = options.indexWhere((o) => !o.bundled);

      if (firstNonBundled > 0) {
        // Nenhuma "inclusa" depois da primeira que não é.
        expect(options.skip(firstNonBundled).every((o) => !o.bundled), isTrue);
      }

      final tail = options
          .where((o) => !o.bundled)
          .map((o) => o.family.toLowerCase())
          .toList();
      final sorted = [...tail]..sort();
      expect(tail, sorted);
    });
  });
}
