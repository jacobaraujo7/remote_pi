import 'package:cockpit/app/core/terminal/json_log_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envolve [token] no SGR indexado [color] — mesma forma que o highlighter emite.
String sgr(int color, String token) => '\x1b[${color}m$token\x1b[0m';

void main() {
  late JsonLogHighlighter highlighter;

  setUp(() => highlighter = JsonLogHighlighter());

  test('pinta chave, string, número e literal de um log JSON', () {
    final out = highlighter.process('{"svc":"api","port":8080,"tls":false}\n');

    expect(
      out,
      '${sgr(90, '{')}${sgr(36, '"svc"')}${sgr(90, ':')}${sgr(32, '"api"')}'
      '${sgr(90, ',')}${sgr(36, '"port"')}${sgr(90, ':')}${sgr(33, '8080')}'
      '${sgr(90, ',')}${sgr(36, '"tls"')}${sgr(90, ':')}${sgr(35, 'false')}'
      '${sgr(90, '}')}\n',
    );
  });

  test('nível error pinta a chave e o valor de vermelho', () {
    final out = highlighter.process('{"level":"error","msg":"db down"}\n');

    expect(out, contains(sgr(91, '"level"')));
    expect(out, contains(sgr(91, '"error"')));
    expect(out, contains(sgr(97, '"db down"'))); // msg em destaque
  });

  test('nível warn/info/debug e nível numérico do pino', () {
    expect(
      highlighter.process('{"level":"warn"}\n'),
      contains(sgr(93, '"warn"')),
    );
    expect(
      highlighter.process('{"level":"info"}\n'),
      contains(sgr(94, '"info"')),
    );
    expect(
      highlighter.process('{"level":"debug"}\n'),
      contains(sgr(90, '"debug"')),
    );
    expect(highlighter.process('{"level":50}\n'), contains(sgr(91, '50')));
    expect(highlighter.process('{"level":30}\n'), contains(sgr(94, '30')));
  });

  test('campo error sem campo level ainda destaca o erro', () {
    final out = highlighter.process('{"msg":"retry","error":"conn refused"}\n');

    expect(out, contains(sgr(91, '"error"')));
    expect(out, contains(sgr(91, '"conn refused"')));
  });

  test('timestamp e caller recuam', () {
    final out = highlighter.process(
      '{"ts":"2026-08-22T10:00:00Z","level":"info"}\n',
    );

    expect(out, contains(sgr(90, '"ts"')));
    expect(out, contains(sgr(90, '"2026-08-22T10:00:00Z"')));
  });

  test('chave especial só vale no nível 1 — aninhado fica neutro', () {
    final out = highlighter.process('{"ctx":{"level":"error"}}\n');

    expect(out, isNot(contains(sgr(91, '"level"'))));
    expect(out, contains(sgr(36, '"level"')));
    expect(out, contains(sgr(32, '"error"')));
  });

  test('linha com ANSI passa intacta (não estraga Flutter/Vite)', () {
    const line = '\x1b[32m{"level":"info"}\x1b[0m\n';

    expect(highlighter.process(line), line);
  });

  test('linha que não é JSON passa intacta', () {
    const line = 'Running "go build" {not json}\n';

    expect(highlighter.process(line), line);
  });

  test('JSON malformado passa intacto', () {
    const line = '{"level":"error",}\n';

    expect(highlighter.process(line), line);
  });

  test('array no topo não é transformado', () {
    const line = '[1,2,3]\n';

    expect(highlighter.process(line), line);
  });

  test('indentação e sufixo fora do objeto são preservados', () {
    final out = highlighter.process('  {"a":1}  \n');

    expect(out, startsWith('  '));
    expect(out, endsWith('  \n'));
  });

  test('CRLF é preservado', () {
    final out = highlighter.process('{"a":1}\r\n');

    expect(out, endsWith('\r\n'));
    expect(out, contains(sgr(33, '1')));
  });

  test('linha JSON partida entre chunks é pintada ao fechar', () {
    expect(highlighter.process('{"level":"err'), '');
    final out = highlighter.process('or","msg":"boom"}\n');

    expect(out, contains(sgr(91, '"error"')));
    expect(out, contains(sgr(97, '"boom"')));
  });

  test('cauda que não começa com { sai na hora (não trava prompt)', () {
    expect(highlighter.process('Enter password: '), 'Enter password: ');
    expect(highlighter.process('{"a":'), '');
  });

  test('flushPending devolve a cauda crua e esvazia', () {
    highlighter.process('{"a":1');

    expect(highlighter.flushPending(), '{"a":1');
    expect(highlighter.flushPending(), '');
  });

  test('múltiplas linhas num chunk só, misturando JSON e texto', () {
    final out = highlighter.process('boot ok\n{"level":"warn"}\nbye\n');

    expect(out, startsWith('boot ok\n'));
    expect(out, endsWith('\nbye\n'));
    expect(out, contains(sgr(93, '"warn"')));
  });
}
