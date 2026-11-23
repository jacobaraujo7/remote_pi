import 'dart:ui' as ui;

import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_body_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        ServicesBinding,
        LogicalKeyboardKey,
        PhysicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

// O simulador padrão usa mapas Android/GLFW sem os keysyms de teclas mortas.
// Reproduz os dois canais enviados pelo engine GTK deste SDK.
extension _GtkKeyEvents on WidgetTester {
  Future<bool> _sendGtkKey(
    LogicalKeyboardKey key,
    PhysicalKeyboardKey physical, {
    required bool down,
  }) async {
    // ignore: deprecated_member_use -- reproduz o protocolo ainda enviado pelo engine GTK deste SDK.
    final manager = ServicesBinding.instance.keyEventManager;
    // ignore: deprecated_member_use -- necessário junto ao canal de compatibilidade GTK abaixo.
    manager.handleKeyData(
      ui.KeyData(
        type: down ? ui.KeyEventType.down : ui.KeyEventType.up,
        physical: physical.usbHidUsage,
        logical: key.keyId,
        timeStamp: Duration.zero,
        character: null,
        synthesized: false,
      ),
    );
    final keys = HardwareKeyboard.instance;
    // ignore: deprecated_member_use -- canal de compatibilidade usado pelo engine GTK.
    final response = await manager.handleRawKeyMessage({
      'type': down ? 'keydown' : 'keyup',
      'keymap': 'linux',
      'toolkit': 'gtk',
      'keyCode': key.keyId & 0xffffffff,
      'scanCode': 48,
      'specifiedLogicalKey': key.keyId,
      'unicodeScalarValues': 0,
      'modifiers':
          (keys.isShiftPressed ? 1 : 0) |
          (keys.isControlPressed ? 4 : 0) |
          (keys.isAltPressed ? 8 : 0) |
          (keys.isMetaPressed ? 1 << 26 : 0),
    });
    return response['handled'] == true;
  }

  Future<bool> sendDeadKeyDownEvent(
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey physicalKey = PhysicalKeyboardKey.quote,
  }) => _sendGtkKey(key, physicalKey, down: true);

  Future<bool> sendDeadKeyUpEvent(
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey physicalKey = PhysicalKeyboardKey.quote,
  }) => _sendGtkKey(key, physicalKey, down: false);
}

TextEditingValue _value(String source) {
  final caret = source.indexOf('|');
  return TextEditingValue(
    text: source.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

TextEditingValue _edit(TextEditingValue old, TextEditingValue value) {
  for (final formatter in const [
    HttpVariableBraceFormatter(),
    HttpScriptEditingFormatter(),
    HttpBodyEditingFormatter(),
  ]) {
    value = formatter.formatEditUpdate(old, value);
  }
  return value;
}

TextEditingValue _insert(
  TextEditingValue old,
  String char, {
  bool composing = false,
  bool collapsed = false,
}) {
  final start = old.selection.start;
  return TextEditingValue(
    text: old.text.replaceRange(start, old.selection.end, char),
    selection: TextSelection.collapsed(offset: start + char.length),
    composing: composing
        ? TextRange(start: start, end: start + char.length)
        : collapsed
        ? TextRange.collapsed(start + char.length)
        : TextRange.empty,
  );
}

void main() {
  Widget harness(
    CodeEditingController controller,
    FocusNode focus, {
    bool readOnly = false,
    bool http = true,
  }) => ShadcnApp(
    theme: buildTheme(brightness: Brightness.dark),
    home: Scaffold(
      child: SizedBox(
        width: 500,
        height: 300,
        child: CodeEditor(
          controller: controller,
          focusNode: focus,
          readOnly: readOnly,
          autoCloseHttpVariables: http,
          autoEditHttpScripts: http,
          autoEditHttpBody: http,
        ),
      ),
    ),
  );

  LogicalKeyboardKey deadKey(String quote) =>
      LogicalKeyboardKey(switch (quote) {
        "'" => 0x0150000fe51,
        '"' => 0x0150000fe57,
        _ => 0x0150000fe50,
      });

  final slots = [
    for (final marker in ['<', '>'])
      for (final quote in ["'", '"', '`'])
        (source: '$marker {%\n  client.log(|);\n%}', quote: quote),
    (
      source:
          'POST https://example.test\nContent-Type: application/json\n\n{"name": |}',
      quote: '"',
    ),
    for (final mime in ['application/xml', 'text/html'])
      for (final quote in ["'", '"'])
        (
          source:
              'POST https://example.test\nContent-Type: $mime\n\n<user name=|>',
          quote: quote,
        ),
  ];

  test('composição de aspa permanece intacta até confirmar com espaço', () {
    for (final slot in slots) {
      final old = _value(slot.source);
      final preedit = _insert(old, slot.quote, composing: true);
      expect(_edit(old, preedit), preedit);
      for (final range in [
        TextRange.empty,
        TextRange.collapsed(preedit.selection.start),
      ]) {
        final committed = preedit.copyWith(composing: range);
        final paired = _edit(preedit, committed);
        expect(
          paired.text,
          old.text.replaceRange(
            old.selection.start,
            old.selection.end,
            '${slot.quote}${slot.quote}',
          ),
          reason: slot.source,
        );
        expect(paired.selection.start, old.selection.start + 1);
        expect(paired.composing.isCollapsed, isTrue);
      }
    }
  });

  test(
    'aspa confirmada diretamente com intervalo de composição vazio fecha o par',
    () {
      for (final slot in slots) {
        final old = _value(slot.source);
        final committed = _insert(old, slot.quote, collapsed: true);
        final paired = _edit(old, committed);
        expect(
          paired.text,
          old.text.replaceRange(
            old.selection.start,
            old.selection.end,
            '${slot.quote}${slot.quote}',
          ),
        );
        expect(paired.selection.start, old.selection.start + 1);
      }
    },
  );

  test('pré-edição de acento pode se transformar em aspa ao confirmar', () {
    for (final pair in [('´', "'"), ('¨', '"')]) {
      final old = _value('> {%\n  client.log(|);\n%}');
      final preedit = _insert(old, pair.$1, composing: true);
      final committed = _insert(old, pair.$2);
      expect(
        _edit(preedit, committed).text,
        old.text.replaceRange(
          old.selection.start,
          old.selection.start,
          '${pair.$2}${pair.$2}',
        ),
      );
    }
  });

  test(
    'reproduz GTK Linux: cursor antes da pré-edição e aspa confirmada depois',
    () {
      // Sequência capturada no editor: ´/¨ em [cursor, cursor + 1], seleção
      // [cursor, cursor], seguida de '/" com seleção [cursor + 1, cursor + 1].
      for (final slot in slots) {
        final old = _value(slot.source);
        final mark = switch (slot.quote) {
          "'" => '´',
          '"' => '¨',
          _ => '`',
        };
        final preedit = _insert(
          old,
          mark,
          composing: true,
        ).copyWith(selection: old.selection);
        expect(_edit(old, preedit), preedit);
        final committed = _insert(old, slot.quote);
        final paired = _edit(preedit, committed);
        expect(
          paired.text,
          old.text.replaceRange(
            old.selection.start,
            old.selection.start,
            '${slot.quote}${slot.quote}',
          ),
          reason: slot.source,
        );
        expect(paired.selection.start, old.selection.start + 1);

        final content = _insert(paired, 'name');
        final closingPreedit = _insert(
          content,
          mark,
          composing: true,
        ).copyWith(selection: content.selection);
        final closed = _edit(closingPreedit, _insert(content, slot.quote));
        expect(closed.text, content.text);
        expect(closed.selection.start, content.selection.start + 1);
        expect(_edit(closingPreedit, content), content);

        final accent = _insert(old, 'á');
        expect(_edit(preedit, accent), accent);
      }
    },
  );

  test('aspa de fechamento confirmada pela composição pula a existente', () {
    for (final slot in slots) {
      final base = _value(slot.source);
      final opened = _edit(base, _insert(base, slot.quote));
      final content = _insert(opened, 'name');
      final preedit = _insert(content, slot.quote, composing: true);
      final closed = _edit(
        preedit,
        preedit.copyWith(composing: TextRange.empty),
      );
      expect(closed.text, content.text);
      expect(closed.selection.start, content.selection.start + 1);
    }
  });

  test('acentos, cancelamento e composição de texto maior não geram pares', () {
    for (final char in ['á', 'é', 'ã', 'ü', 'ê', '"text"', "'word'"]) {
      final old = _value('> {%\n  client.log(|);\n%}');
      final preedit = _insert(old, '´', composing: true);
      final committed = _insert(old, char);
      expect(_edit(preedit, committed), committed);
    }
    final old = _value('> {%\n  client.log(|);\n%}');
    final preedit = _insert(old, "'", composing: true);
    expect(_edit(preedit, old), old);
    final chunk = _insert(old, 'some text', composing: true);
    final quote = _insert(old, '"');
    expect(_edit(chunk, quote), quote);
  });

  test('commit de composição preserva strings, escapes e comentários', () {
    for (final source in [
      '> {%\n// comment |\n%}',
      '> {%\n/* comment | */\n%}',
      '> {%\nclient.log("escaped \\|");\n%}',
      '> {%\nclient.log("single | inside");\n%}',
      'POST https://example.test\nX-Header: |',
    ]) {
      final old = _value(source);
      final preedit = _insert(old, "'", composing: true);
      final committed = preedit.copyWith(composing: TextRange.empty);
      expect(_edit(preedit, committed), committed);
    }
  });

  test(
    'cancelar composição antes de aspa existente não apaga o fechamento',
    () {
      for (final slot in slots) {
        final old = _value(slot.source);
        final opened = _edit(old, _insert(old, slot.quote));
        final preedit = _insert(opened, slot.quote, composing: true);
        expect(_edit(preedit, opened), opened);
      }
    },
  );

  testWidgets(
    'tecla morta não insere aspas; o par só fecha quando a aspa é confirmada',
    (tester) async {
      final controller = CodeEditingController(text: '', language: 'http');
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });
      await tester.pumpWidget(harness(controller, focus));
      focus.requestFocus();
      await tester.pump();
      for (final slot in slots) {
        final old = _value(slot.source);
        controller.value = old;
        await tester.pump();
        expect(
          await tester.sendDeadKeyDownEvent(
            deadKey(slot.quote),
            physicalKey: PhysicalKeyboardKey.quote,
          ),
          isFalse,
          reason: slot.source,
        );
        await tester.sendDeadKeyUpEvent(
          deadKey(slot.quote),
          physicalKey: PhysicalKeyboardKey.quote,
        );
        expect(controller.value, old);
        final mark = switch (slot.quote) {
          "'" => '´',
          '"' => '¨',
          _ => '`',
        };
        final preedit = _insert(
          old,
          mark,
          composing: true,
        ).copyWith(selection: old.selection);
        tester.testTextInput.updateEditingValue(preedit);
        await tester.pump();
        expect(controller.value, preedit);
        tester.testTextInput.updateEditingValue(_insert(old, slot.quote));
        await tester.pump();
        expect(
          controller.text,
          old.text.replaceRange(
            old.selection.start,
            old.selection.start,
            '${slot.quote}${slot.quote}',
          ),
        );
        expect(controller.selection.start, old.selection.start + 1);
        expect(controller.value.composing.isCollapsed, isTrue);
        tester.testTextInput.updateEditingValue(
          _insert(controller.value, 'name'),
        );
        await tester.pump();
        expect(
          controller.text,
          old.text.replaceRange(
            old.selection.start,
            old.selection.start,
            '${slot.quote}name${slot.quote}',
          ),
        );
      }
      final plain = _value('> {%\n  client.log(|);\n%}');
      controller.value = plain;
      await tester.pump();
      tester.testTextInput.updateEditingValue(_insert(plain, "'"));
      await tester.pump();
      expect(
        controller.text,
        plain.text.replaceRange(
          plain.selection.start,
          plain.selection.start,
          "''",
        ),
      );
      final accentBase = _value('> {%\n  client.log(|);\n%}');
      controller.value = accentBase;
      await tester.pump();
      final accentPreedit = _insert(
        accentBase,
        '´',
        composing: true,
      ).copyWith(selection: accentBase.selection);
      tester.testTextInput.updateEditingValue(accentPreedit);
      await tester.pump();
      tester.testTextInput.updateEditingValue(_insert(accentBase, 'á'));
      await tester.pump();
      expect(
        controller.text,
        accentBase.text.replaceRange(
          accentBase.selection.start,
          accentBase.selection.start,
          'á',
        ),
      );
    },
  );

  testWidgets('tecla morta envolve seleção e o par participa do undo', (
    tester,
  ) async {
    final old = _value('> {%\n  client.log(|name);\n%}');
    final controller = CodeEditingController(text: old.text, language: 'http')
      ..selection = old.selection;
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(harness(controller, focus));
    focus.requestFocus();
    controller.selection = TextSelection(
      baseOffset: old.selection.start,
      extentOffset: old.selection.start + 4,
    );
    await tester.pump(const Duration(milliseconds: 600));
    final selected = controller.value;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: selected.text.replaceRange(
          selected.selection.start,
          selected.selection.end,
          '"',
        ),
        selection: TextSelection.collapsed(
          offset: selected.selection.start + 1,
        ),
      ),
    );
    await tester.pump();
    expect(controller.text, '> {%\n  client.log("name");\n%}');
    expect(controller.selection.textInside(controller.text), 'name');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, old.text);
  });

  testWidgets('strings e comentários preservam a composição de acentos', (
    tester,
  ) async {
    final controller = CodeEditingController(text: '', language: 'http');
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(harness(controller, focus));
    focus.requestFocus();
    await tester.pump();
    for (final source in [
      '> {%\n  client.log("ol|");\n%}',
      "> {%\n  client.log('ol|');\n%}",
      '> {%\n  // ol|\n%}',
      'POST https://example.test\nContent-Type: application/json\n\n{"name": "ol|"}',
      'POST https://example.test\nContent-Type: text/html\n\n<p title="ol|">',
    ]) {
      final old = _value(source);
      controller.value = old;
      await tester.pump();
      expect(
        await tester.sendDeadKeyDownEvent(
          deadKey("'"),
          physicalKey: PhysicalKeyboardKey.quote,
        ),
        isFalse,
      );
      await tester.sendDeadKeyUpEvent(
        deadKey("'"),
        physicalKey: PhysicalKeyboardKey.quote,
      );
      expect(controller.value, old);
      final preedit = _insert(
        old,
        '´',
        composing: true,
      ).copyWith(selection: old.selection);
      tester.testTextInput.updateEditingValue(preedit);
      await tester.pump();
      tester.testTextInput.updateEditingValue(_insert(old, 'á'));
      await tester.pump();
      expect(
        controller.text,
        old.text.replaceRange(old.selection.start, old.selection.start, 'á'),
      );
    }
  });

  testWidgets(
    'headers, outros editores, readonly, atalhos e composição ativa não interceptam a tecla morta',
    (tester) async {
      final old = _value('> {%\n  client.log(|);\n%}');
      final controller = CodeEditingController(text: old.text, language: 'http')
        ..selection = old.selection;
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });
      for (final setting in [
        (readOnly: true, http: true),
        (readOnly: false, http: false),
        (readOnly: false, http: true),
      ]) {
        await tester.pumpWidget(
          harness(
            controller,
            focus,
            readOnly: setting.readOnly,
            http: setting.http,
          ),
        );
        focus.requestFocus();
        controller.value = setting.readOnly || !setting.http
            ? old
            : _value('POST https://example.test\nX-Name: |');
        await tester.pump();
        final before = controller.value;
        expect(
          await tester.sendDeadKeyDownEvent(
            deadKey('"'),
            physicalKey: PhysicalKeyboardKey.quote,
          ),
          isFalse,
        );
        await tester.sendDeadKeyUpEvent(
          deadKey('"'),
          physicalKey: PhysicalKeyboardKey.quote,
        );
        expect(controller.value, before);
      }
      for (final mod in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.metaLeft,
      ]) {
        controller.value = old;
        await tester.pump();
        await tester.sendKeyDownEvent(mod);
        expect(
          await tester.sendDeadKeyDownEvent(
            deadKey('"'),
            physicalKey: PhysicalKeyboardKey.quote,
          ),
          isFalse,
        );
        await tester.sendDeadKeyUpEvent(
          deadKey('"'),
          physicalKey: PhysicalKeyboardKey.quote,
        );
        await tester.sendKeyUpEvent(mod);
        expect(controller.value, old);
      }
      final composing = _insert(
        old,
        '´',
        composing: true,
      ).copyWith(selection: old.selection);
      controller.value = composing;
      await tester.pump();
      expect(
        await tester.sendDeadKeyDownEvent(
          deadKey('"'),
          physicalKey: PhysicalKeyboardKey.quote,
        ),
        isFalse,
      );
      await tester.sendDeadKeyUpEvent(
        deadKey('"'),
        physicalKey: PhysicalKeyboardKey.quote,
      );
      expect(controller.value, composing);
    },
  );

  testWidgets(
    'CodeEditor fecha aspas no commit sem mudança de texto da plataforma',
    (tester) async {
      final controller = CodeEditingController(text: '', language: 'http');
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });
      await tester.pumpWidget(
        ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: SizedBox(
              width: 500,
              height: 300,
              child: CodeEditor(
                controller: controller,
                focusNode: focus,
                autoCloseHttpVariables: true,
                autoEditHttpScripts: true,
                autoEditHttpBody: true,
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      for (final slot in slots) {
        for (final gtk in [false, true]) {
          final old = _value(slot.source);
          controller.value = old;
          await tester.pump();
          final mark = gtk
              ? switch (slot.quote) {
                  "'" => '´',
                  '"' => '¨',
                  _ => '`',
                }
              : slot.quote;
          var preedit = _insert(old, mark, composing: true);
          if (gtk) preedit = preedit.copyWith(selection: old.selection);
          tester.testTextInput.updateEditingValue(preedit);
          await tester.pump();
          expect(controller.value, preedit);
          final committed = gtk
              ? _insert(old, slot.quote)
              : preedit.copyWith(
                  composing: TextRange.collapsed(preedit.selection.start),
                );
          tester.testTextInput.updateEditingValue(committed);
          await tester.pump();
          expect(
            controller.text,
            old.text.replaceRange(
              old.selection.start,
              old.selection.start,
              '${slot.quote}${slot.quote}',
            ),
          );
          expect(controller.selection.start, old.selection.start + 1);
          // O GTK reenvia o commit sem o fechamento ao terminar a composição.
          tester.testTextInput.updateEditingValue(committed);
          await tester.pump();
          expect(
            controller.text,
            old.text.replaceRange(
              old.selection.start,
              old.selection.start,
              '${slot.quote}${slot.quote}',
            ),
          );
          expect(controller.selection.start, old.selection.start + 1);
          // Depois do Espaço que confirmou a tecla morta, o texto entra no par.
          tester.testTextInput.updateEditingValue(
            _insert(controller.value, 'name'),
          );
          await tester.pump();
          expect(
            controller.text,
            old.text.replaceRange(
              old.selection.start,
              old.selection.start,
              '${slot.quote}name${slot.quote}',
            ),
          );
        }
      }
    },
  );

  testWidgets('Delete remove o fechamento depois que a composição terminou', (
    tester,
  ) async {
    final old = _value('> {%\n  client.log(|);\n%}');
    final controller = CodeEditingController(text: old.text, language: 'http')
      ..selection = old.selection;
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(harness(controller, focus));
    focus.requestFocus();
    await tester.pump();
    final preedit = _insert(
      old,
      '´',
      composing: true,
    ).copyWith(selection: old.selection);
    tester.testTextInput.updateEditingValue(preedit);
    await tester.pump();
    final committed = _insert(old, "'");
    tester.testTextInput.updateEditingValue(committed);
    await tester.pump();
    tester.testTextInput.updateEditingValue(committed);
    await tester.pump();
    expect(controller.text, "> {%\n  client.log('');\n%}");
    final opened = controller.value;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: opened.text.replaceRange(
          opened.selection.start,
          opened.selection.start + 1,
          '',
        ),
        selection: opened.selection,
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    expect(controller.text, "> {%\n  client.log(');\n%}");
  });
}
