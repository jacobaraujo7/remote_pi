import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Um host **Windows** responde na codepage local (CP850/CP1252), não em
/// UTF-8. A mensagem acentuada do cmd — "'uname' não é reconhecido como um
/// comando interno" — carrega bytes inválidos em UTF-8, e a decodificação
/// estrita estourava `FormatException: Missing extension byte`, escondendo o
/// erro real atrás de um erro de decodificação.
void main() {
  /// "'uname' não é reconhecido como um comando interno ou externo" em CP850,
  /// que é o que o cmd do Windows em português devolve.
  final cp850 = <int>[
    ...utf8.encode("'uname' n"),
    0xA3, // ã em CP850
    ...utf8.encode('o '),
    0x82, // é em CP850
    ...utf8.encode(' reconhecido como um comando interno ou externo'),
  ];

  test('decodificação estrita estoura no byte da codepage', () {
    expect(
      () => utf8.decode(cp850),
      throwsA(isA<FormatException>()),
      reason: 'é este o FormatException que o usuário via na tela',
    );
  });

  test('tolerante devolve a mensagem legível, sem estourar', () {
    final text = utf8.decode(cp850, allowMalformed: true);
    // Os bytes inválidos viram U+FFFD, mas o essencial da mensagem sobrevive —
    // e é o que permite reconhecer o host como Windows em vez de reportar um
    // erro de parsing.
    expect(text, contains('uname'));
    expect(text, contains('reconhecido'));
    expect(text, contains('comando interno'));
  });

  test('o mesmo vale para o stream (transform), não só para decode', () async {
    final decoded = await Stream<List<int>>.value(
      cp850,
    ).transform(const Utf8Decoder(allowMalformed: true)).join();
    expect(decoded, contains('uname'));
  });
}
