// Testes do Shift+Enter no terminal: rastreio do kitty keyboard protocol e a
// escolha do byte (CSI-u quando ativo, `\n` quando legado).

import 'package:cockpit/app/cockpit/ui/session/terminal_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';

TerminalKeyboardEvent _event(
  TerminalKey key, {
  bool shift = false,
  bool ctrl = false,
  bool alt = false,
}) {
  return TerminalKeyboardEvent(
    key: key,
    shift: shift,
    ctrl: ctrl,
    alt: alt,
    state: Terminal(),
    altBuffer: false,
    platform: TerminalTargetPlatform.macos,
  );
}

void main() {
  group('KittyKeyboardTracker', () {
    test('começa inativo', () {
      expect(KittyKeyboardTracker().active, isFalse);
    });

    test('push (CSI > flags u) ativa; pop (CSI < u) desativa', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>7u'); // pi empurra flags=7 ao iniciar
      expect(k.active, isTrue);
      k.feed('\x1b[<u'); // remove ao sair
      expect(k.active, isFalse);
    });

    test('push de flags 0 não conta como ativo', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>0u');
      expect(k.active, isFalse);
    });

    test('query (CSI ? u) sozinha não ativa — só observamos passivamente', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[?u');
      expect(k.active, isFalse);
    });

    test('RIS (ESC c) reseta o estado', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>7u');
      expect(k.active, isTrue);
      k.feed('\x1bc');
      expect(k.active, isFalse);
    });

    test('set (CSI = flags ; mode u) liga e desliga', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[=5;1u'); // set flags=5
      expect(k.active, isTrue);
      k.feed('\x1b[=5;3u'); // and-not 5 -> 0
      expect(k.active, isFalse);
    });

    test('sequência partida entre chunks ainda é detectada', () {
      final k = KittyKeyboardTracker();
      k.feed('saída qualquer\x1b[>');
      expect(k.active, isFalse); // ainda incompleta
      k.feed('7u mais saída');
      expect(k.active, isTrue);
    });

    test('texto comum não liga o protocolo por engano', () {
      final k = KittyKeyboardTracker();
      k.feed('echo \x1b[31mvermelho\x1b[0m e \x1b[2J limpa');
      expect(k.active, isFalse);
    });

    test('push aninhado: pop volta ao nível anterior ativo', () {
      final k = KittyKeyboardTracker();
      k.feed('\x1b[>1u'); // nível 1
      k.feed('\x1b[>15u'); // nível 2
      k.feed('\x1b[<u'); // volta pro nível 1 (ainda ativo)
      expect(k.active, isTrue);
      k.feed('\x1b[<u'); // remove o último
      expect(k.active, isFalse);
    });
  });

  group('ShiftEnterInputHandler', () {
    test('Shift+Enter sem kitty -> line feed', () {
      final k = KittyKeyboardTracker();
      final h = ShiftEnterInputHandler(k);
      expect(h(_event(TerminalKey.enter, shift: true)), '\n');
    });

    test('Shift+Enter com kitty ativo -> CSI 13 ; 2 u', () {
      final k = KittyKeyboardTracker()..feed('\x1b[>7u');
      final h = ShiftEnterInputHandler(k);
      expect(h(_event(TerminalKey.enter, shift: true)), '\x1b[13;2u');
    });

    test('Enter puro (sem shift) cai pro handler padrão (null)', () {
      final h = ShiftEnterInputHandler(KittyKeyboardTracker());
      expect(h(_event(TerminalKey.enter)), isNull);
    });

    test('Ctrl+Shift+Enter e Alt+Shift+Enter não são tratados aqui', () {
      final h = ShiftEnterInputHandler(KittyKeyboardTracker());
      expect(h(_event(TerminalKey.enter, shift: true, ctrl: true)), isNull);
      expect(h(_event(TerminalKey.enter, shift: true, alt: true)), isNull);
    });

    test('outras teclas com shift não são tratadas aqui', () {
      final h = ShiftEnterInputHandler(KittyKeyboardTracker());
      expect(h(_event(TerminalKey.keyA, shift: true)), isNull);
    });
  });
}
