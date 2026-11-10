import 'package:cockpit/app/cockpit/domain/entities/http_runtime_variable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tipos validam e serializam valores de execução', () {
    expect(
      const HttpRuntimeVariable('', HttpRuntimeValueType.string).value,
      '',
    );
    expect(
      const HttpRuntimeVariable('12.5', HttpRuntimeValueType.number).value,
      '12.5',
    );
    expect(
      const HttpRuntimeVariable('TRUE', HttpRuntimeValueType.boolean).value,
      'true',
    );
    expect(
      const HttpRuntimeVariable('{"a": 1}', HttpRuntimeValueType.json).value,
      '{"a":1}',
    );
    expect(
      const HttpRuntimeVariable(
        'abc',
        HttpRuntimeValueType.number,
      ).validationError,
      isNotNull,
    );
    expect(
      const HttpRuntimeVariable(
        'yes',
        HttpRuntimeValueType.boolean,
      ).validationError,
      isNotNull,
    );
    expect(HttpRuntimeVariable.inferType(null), HttpRuntimeValueType.string);
    expect(HttpRuntimeVariable.inferType('true'), HttpRuntimeValueType.boolean);
    expect(HttpRuntimeVariable.inferType('[1]'), HttpRuntimeValueType.json);
  });
}
