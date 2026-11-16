import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Cmd/Ctrl+X sem seleção recorta a linha inteira (issue #285). Roda com a
/// plataforma simulada em macOS e Windows: o editor decide o modificador por
/// `defaultTargetPlatform`, e os atalhos padrão do campo (recorte com seleção,
/// colar normal, desfazer) também seguem a plataforma simulada.
void main() {
  final desktop = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.macOS,
    TargetPlatform.windows,
  });

  Widget harness(CodeEditingController ctrl, FocusNode focus) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: SizedBox(
          width: 300,
          height: 200,
          child: CodeEditor(
            controller: ctrl,
            focusNode: focus,
            filePath: 'main.dart',
          ),
        ),
      ),
    );
  }

  /// Área de transferência falsa no canal de plataforma.
  late String? clipboard;
  setUp(() => clipboard = null);

  void mockClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return clipboard == null ? null : {'text': clipboard};
          case 'Clipboard.hasStrings':
            return {'value': clipboard?.isNotEmpty ?? false};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  /// Meta no macOS, Control no Windows: o atalho "nativo" de cada um.
  LogicalKeyboardKey mod() => defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    final m = modifier ?? mod();
    await tester.sendKeyDownEvent(m);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(m);
    // Clipboard.getData é assíncrono: deixa o colar terminar.
    await tester.pumpAndSettle();
  }

  Future<CodeEditingController> mount(
    WidgetTester tester,
    String text,
    TextSelection sel,
  ) async {
    mockClipboard(tester);
    final ctrl = CodeEditingController(text: text, language: 'dart');
    final focus = FocusNode();
    addTearDown(() {
      ctrl.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(harness(ctrl, focus));
    focus.requestFocus();
    await tester.pump();
    ctrl.selection = sel;
    await tester.pump();
    return ctrl;
  }

  testWidgets(
    'sem seleção recorta a linha do cursor para a área de transferência',
    (tester) async {
      final ctrl = await mount(
        tester,
        'one\ntwo\nthree',
        const TextSelection.collapsed(offset: 6),
      );
      await shortcut(tester, LogicalKeyboardKey.keyX);
      expect(ctrl.text, 'one\nthree');
      expect(ctrl.selection, const TextSelection.collapsed(offset: 6));
      expect(clipboard, 'two\n');
    },
    variant: desktop,
  );

  testWidgets('Ctrl+X também recorta a linha no macOS', (tester) async {
    final ctrl = await mount(
      tester,
      'one\ntwo',
      const TextSelection.collapsed(offset: 1),
    );
    await shortcut(
      tester,
      LogicalKeyboardKey.keyX,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(ctrl.text, 'two');
    expect(clipboard, 'one\n');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('com seleção o recorte continua só do trecho', (tester) async {
    final ctrl = await mount(
      tester,
      'one\ntwo',
      const TextSelection(baseOffset: 4, extentOffset: 6),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, 'one\no');
    expect(clipboard, 'tw');
  }, variant: desktop);

  testWidgets('colar logo depois do recorte insere a linha acima do cursor', (
    tester,
  ) async {
    final ctrl = await mount(
      tester,
      'one\ntwo\nthree',
      const TextSelection.collapsed(offset: 0),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, 'two\nthree');
    // Cursor no meio de "three": a linha entra inteira acima dela.
    ctrl.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyV);
    expect(ctrl.text, 'two\none\nthree');
    expect(ctrl.selection, const TextSelection.collapsed(offset: 10));
  }, variant: desktop);

  testWidgets(
    'área de transferência trocada depois do recorte cola normal no cursor',
    (tester) async {
      final ctrl = await mount(
        tester,
        'one\ntwo',
        const TextSelection.collapsed(offset: 0),
      );
      await shortcut(tester, LogicalKeyboardKey.keyX);
      clipboard = 'XY';
      ctrl.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      expect(ctrl.text, 'tXYwo');
    },
    variant: desktop,
  );

  testWidgets('colar com seleção substitui a seleção', (tester) async {
    final ctrl = await mount(
      tester,
      'one\ntwo',
      const TextSelection.collapsed(offset: 0),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(clipboard, 'one\n');
    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyV);
    expect(ctrl.text, 'one\n');
  }, variant: desktop);

  testWidgets('desfazer traz a linha de volta num passo só', (tester) async {
    final ctrl = await mount(
      tester,
      'one\ntwo\nthree',
      const TextSelection.collapsed(offset: 5),
    );
    // A pilha de undo do campo agrupa mudanças próximas no tempo.
    await tester.pump(const Duration(seconds: 1));
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, 'one\nthree');
    await tester.pump(const Duration(seconds: 1));
    await shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(ctrl.text, 'one\ntwo\nthree');
  }, variant: desktop);

  testWidgets('recortes seguidos sobrescrevem a área de transferência', (
    tester,
  ) async {
    final ctrl = await mount(
      tester,
      'a\nb\nc',
      const TextSelection.collapsed(offset: 0),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(clipboard, 'a\n');
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(clipboard, 'b\n');
    expect(ctrl.text, 'c');
  }, variant: desktop);

  testWidgets('\\r\\n preservado no recorte e no colar', (tester) async {
    final ctrl = await mount(
      tester,
      'a\r\nb\r\nc',
      const TextSelection.collapsed(offset: 3),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(clipboard, 'b\r\n');
    expect(ctrl.text, 'a\r\nc');
    await shortcut(tester, LogicalKeyboardKey.keyV);
    expect(ctrl.text, 'a\r\nb\r\nc');
  }, variant: desktop);

  testWidgets('última linha sem quebra e arquivo de uma linha', (tester) async {
    final ctrl = await mount(
      tester,
      'a\nb',
      const TextSelection.collapsed(offset: 3),
    );
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, 'a');
    expect(clipboard, 'b\n');
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, '');
    expect(clipboard, 'a');
    // Arquivo vazio: o atalho não faz nada nem quebra.
    await shortcut(tester, LogicalKeyboardKey.keyX);
    expect(ctrl.text, '');
    expect(clipboard, 'a');
  }, variant: desktop);
}
