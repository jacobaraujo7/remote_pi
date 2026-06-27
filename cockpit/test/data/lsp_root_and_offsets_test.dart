import 'dart:io';

import 'package:cockpit/app/core/data/lsp/project_root_finder.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

String join(String a, String b) => '$a${Platform.pathSeparator}$b';

LspDiagnostic diag(
  int sl,
  int sc,
  int el,
  int ec, [
  LspSeverity sev = LspSeverity.error,
]) {
  return LspDiagnostic(
    range: LspRange(LspPosition(sl, sc), LspPosition(el, ec)),
    severity: sev,
    message: 'x',
  );
}

void main() {
  group('diagnosticRangesFor (line/char UTF-16 → offset)', () {
    test('range numa linha do meio', () {
      const text = 'abc\ndefg\nhij'; // linha1 começa em 4
      final r = diagnosticRangesFor(text, [diag(1, 1, 1, 3)]);
      expect(r, hasLength(1));
      expect(r.first.start, 5); // 4 + 1
      expect(r.first.end, 7); // 4 + 3
    });

    test('largura zero vira 1 caractere', () {
      const text = 'abc';
      final r = diagnosticRangesFor(text, [diag(0, 1, 0, 1)]);
      expect(r.first.start, 1);
      expect(r.first.end, 2);
    });

    test('character além do fim da linha é clampado ao fim do conteúdo', () {
      const text = 'ab\ncd'; // linha0 conteúdo = 'ab', fim em offset 2 (o \n)
      final r = diagnosticRangesFor(text, [diag(0, 99, 0, 99)]);
      // start clampado a 2; zero-width → end 3 clampado a len(5) ok
      expect(r.first.start, 2);
    });

    test('linha fora do range cai no fim do texto', () {
      const text = 'abc';
      final r = diagnosticRangesFor(text, [diag(9, 0, 9, 1)]);
      // start=end=text.length → zero-width expandido mas clampado → descartado
      expect(r, isEmpty);
    });

    test('emoji (surrogate pair) conta como 2 code units, igual ao LSP', () {
      const text = '🚀ab'; // '🚀' = 2 code units (0,1); 'a'=2, 'b'=3
      final r = diagnosticRangesFor(text, [diag(0, 2, 0, 3)]);
      expect(r.first.start, 2);
      expect(r.first.end, 3);
    });
  });

  group('ProjectRootFinder', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lsp_root_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('acha a raiz pelo marcador exato (monorepo)', () {
      // tmp/pkg/pubspec.yaml ; arquivo em tmp/pkg/lib/main.dart
      final pkg = Directory(join(tmp.path, 'pkg'))..createSync();
      File(join(pkg.path, 'pubspec.yaml')).writeAsStringSync('name: x');
      final lib = Directory(join(pkg.path, 'lib'))..createSync();
      final file = join(lib.path, 'main.dart');

      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, pkg.path);
    });

    test('escolhe a raiz mais próxima (pacote aninhado)', () {
      // tmp/pubspec.yaml E tmp/inner/pubspec.yaml → arquivo em inner usa inner
      File(join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: outer');
      final inner = Directory(join(tmp.path, 'inner'))..createSync();
      File(join(inner.path, 'pubspec.yaml')).writeAsStringSync('name: inner');
      final file = join(inner.path, 'a.dart');

      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, inner.path);
    });

    test('marcador por sufixo (*.csproj)', () {
      File(join(tmp.path, 'App.csproj')).writeAsStringSync('<Project/>');
      final file = join(tmp.path, 'Program.cs');
      final root = const ProjectRootFinder().findRoot(file, ['*.csproj']);
      expect(root, tmp.path);
    });

    test('sem marcador retorna null', () {
      final file = join(tmp.path, 'orphan.dart');
      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, isNull);
    });
  });
}
