/// Normaliza SGR bold para o peso base antes de o VT chegar ao `flterm`.
///
/// O renderer do `flterm` 0.0.4 fixa SGR 1 em `FontWeight.bold` (700), sem um
/// knob separado para o peso de destaque. No rasterizador do Flutter esse peso
/// fica perceptivelmente mais forte que no Ghostty nativo. SGR 22 mantém cor e
/// demais atributos, mas volta ao peso regular configurado no tema.
final class GhosttySgrWeightNormalizer {
  String _pending = '';

  String add(String chunk) {
    if (chunk.isEmpty) return '';
    final input = '$_pending$chunk';
    _pending = '';
    final output = StringBuffer();
    var index = 0;

    while (index < input.length) {
      if (input.codeUnitAt(index) != 0x1b) {
        output.writeCharCode(input.codeUnitAt(index));
        index++;
        continue;
      }

      if (index + 1 >= input.length) {
        _pending = input.substring(index);
        break;
      }
      if (input.codeUnitAt(index + 1) != 0x5b) {
        output.writeCharCode(0x1b);
        index++;
        continue;
      }

      var end = index + 2;
      while (end < input.length) {
        final code = input.codeUnitAt(end);
        if (code >= 0x40 && code <= 0x7e) break;
        end++;
      }
      if (end >= input.length) {
        _pending = input.substring(index);
        break;
      }

      final finalByte = input.codeUnitAt(end);
      if (finalByte != 0x6d) {
        output.write(input.substring(index, end + 1));
        index = end + 1;
        continue;
      }

      final parameters = input.substring(index + 2, end).split(';');
      output
        ..write('\x1b[')
        ..writeAll(parameters.map((value) => value == '1' ? '22' : value), ';')
        ..write('m');
      index = end + 1;
    }

    return output.toString();
  }
}
