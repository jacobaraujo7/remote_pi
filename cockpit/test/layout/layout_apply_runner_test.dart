import 'package:cockpit/app/cockpit/domain/entities/layout_spec.dart';
import 'package:cockpit/app/cockpit/domain/services/layout_apply_runner.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Workspace de mentira: só o que o runner toca (fechar tudo / criar panes).
/// O `CockpitViewModel` real tem 31 deps — o contrato de ordem (validar →
/// fechar → aplicar) é o que se testa aqui, com os mesmos callbacks que o VM
/// injeta no [LayoutApplyRunner.run].
class _Workspace {
  _Workspace(this.tabs);

  final List<String> tabs;
  final log = <String>[];

  Future<int> closeAll() async {
    log.add('close');
    final n = tabs.length;
    tabs.clear();
    return n;
  }

  Future<Result<LayoutApplyReport, String>> apply(LayoutSpec spec) async {
    log.add('apply');
    final created = <String>[];
    final skipped = <String>[];
    for (final p in spec.panes) {
      if (tabs.contains(p.name)) {
        skipped.add(p.name);
      } else {
        tabs.add(p.name);
        created.add(p.name);
      }
    }
    return Success(LayoutApplyReport(created: created, skipped: skipped));
  }
}

const _spec = LayoutSpec(
  name: 'dev',
  panes: [
    LayoutPane(name: 'Frontend'),
    LayoutPane(name: 'Backend'),
  ],
);

Future<Result<LayoutSpec, String>> _ok() async => const Success(_spec);
Future<Result<LayoutSpec, String>> _bad() async =>
    const Failure('panes: must be a non-empty list');

void main() {
  const runner = LayoutApplyRunner();

  test(
    'replace (default): fecha as abas atuais e depois cria os panes',
    () async {
      final ws = _Workspace(['Shell', 'Backend']);
      final res = await runner.run(
        mode: LayoutApplyMode.replace,
        load: _ok,
        closeAll: ws.closeAll,
        apply: ws.apply,
      );
      final report = (res as Success<LayoutApplyReport, String>).value;
      expect(ws.log, ['close', 'apply']);
      expect(ws.tabs, ['Frontend', 'Backend']); // 'Shell' sumiu, nada pulado
      expect(report.closed, 2);
      expect(report.created, ['Frontend', 'Backend']);
      expect(report.skipped, isEmpty);
    },
  );

  test('append: mantém as abas e faz merge (nome repetido é pulado)', () async {
    final ws = _Workspace(['Shell', 'Backend']);
    final res = await runner.run(
      mode: LayoutApplyMode.append,
      load: _ok,
      closeAll: ws.closeAll,
      apply: ws.apply,
    );
    final report = (res as Success<LayoutApplyReport, String>).value;
    expect(ws.log, ['apply']); // nunca fechou
    expect(ws.tabs, ['Shell', 'Backend', 'Frontend']);
    expect(report.closed, 0);
    expect(report.created, ['Frontend']);
    expect(report.skipped, ['Backend']);
  });

  test('arquivo inválido: não fecha nem cria nada, mesmo em replace', () async {
    final ws = _Workspace(['Shell', 'Backend']);
    final res = await runner.run(
      mode: LayoutApplyMode.replace,
      load: _bad,
      closeAll: ws.closeAll,
      apply: ws.apply,
    );
    expect(res, isA<Failure<LayoutApplyReport, String>>());
    expect((res as Failure).error, contains('panes'));
    expect(ws.log, isEmpty);
    expect(ws.tabs, ['Shell', 'Backend']);
  });

  test('falha ao aplicar depois do fechamento propaga o erro', () async {
    final ws = _Workspace(['Shell']);
    final res = await runner.run(
      mode: LayoutApplyMode.replace,
      load: _ok,
      closeAll: ws.closeAll,
      apply: (_) async => const Failure('pane "Frontend": directory not found'),
    );
    expect(res, isA<Failure<LayoutApplyReport, String>>());
    expect(ws.log, ['close']);
  });
}
