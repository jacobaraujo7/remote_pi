import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = HttpVariableBraceFormatter();

  test('segunda chave abre o par e mantém o cursor entre as chaves', () {
    const oldValue = TextEditingValue(
      text: 'GET {',
      selection: TextSelection.collapsed(offset: 5),
    );
    const typed = TextEditingValue(
      text: 'GET {{',
      selection: TextSelection.collapsed(offset: 6),
    );
    final result = formatter.formatEditUpdate(oldValue, typed);
    expect(result.text, 'GET {{}}');
    expect(result.selection.baseOffset, 6);
  });

  test('não duplica fechamento já presente nem interfere em outras chaves', () {
    const oldValue = TextEditingValue(
      text: 'GET {}}',
      selection: TextSelection.collapsed(offset: 5),
    );
    const typed = TextEditingValue(
      text: 'GET {{}}',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(formatter.formatEditUpdate(oldValue, typed).text, 'GET {{}}');
    const unrelated = TextEditingValue(
      text: 'GET {',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(
      formatter
          .formatEditUpdate(
            const TextEditingValue(
              text: 'GET ',
              selection: TextSelection.collapsed(offset: 4),
            ),
            unrelated,
          )
          .text,
      'GET {',
    );
  });

  test('slot vazio espera interação e completar preserva as chaves', () {
    final empty = HttpVariableCompletion.slotAt('GET {{}}/users', 6);
    expect(empty?.prefix, '');
    final typed = HttpVariableCompletion.slotAt('GET {{ho}}/users', 8);
    expect(typed?.prefix, 'ho');
    final value = HttpVariableCompletion.complete(
      const TextEditingValue(
        text: 'GET {{ho}}/users',
        selection: TextSelection.collapsed(offset: 8),
      ),
      typed!,
      'host',
    );
    expect(value.text, 'GET {{host}}/users');
    expect(value.selection.baseOffset, 12);
    expect(
      HttpVariableCompletion.slotAt(value.text, value.selection.baseOffset),
      isNull,
    );
  });

  test('Ctrl+Space fora das chaves insere variável completa ao escolher', () {
    const before = TextEditingValue(
      text: 'GET /users',
      selection: TextSelection.collapsed(offset: 4),
    );
    final after = HttpVariableCompletion.insertAt(before, 4, 'host');
    expect(after.text, 'GET {{host}}/users');
    expect(after.selection.baseOffset, 12);
  });
}
