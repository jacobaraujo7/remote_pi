import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Project.effectiveRoot` existe por causa de um bug real: a CLI lia
/// `project.path` direto e, num workspace REMOTO, recebia vazio — a pasta vive
/// em `remotePath`. O efeito era `cockpit db`, `list-tasks` e `read-task`
/// recusarem a própria aba com "this pane has no workspace folder", enquanto a
/// UI funcionava (ela já resolvia a raiz certa por outro caminho).
void main() {
  test('workspace local: a raiz é o path', () {
    final p = Project(
      id: 'w1',
      name: 'app',
      path: '/home/jacob/app',
      colorValue: 0,
      createdAt: DateTime(2026),
    );
    expect(p.effectiveRoot, '/home/jacob/app');
  });

  test('workspace remoto: a raiz é a pasta do HOST, não o path vazio', () {
    final p = Project.remoteHost(
      pinId: '1::/Volumes/SUPORTE/Projects/Capitaliso',
      hostId: '1',
      name: 'Capitaliso',
      remotePath: '/Volumes/SUPORTE/Projects/Capitaliso',
      colorValue: 0,
    );
    // O path vazio é intencional (a pasta não existe no disco do cliente)…
    expect(p.path, isEmpty);
    // …mas quem pergunta pela raiz precisa da pasta de verdade.
    expect(p.effectiveRoot, '/Volumes/SUPORTE/Projects/Capitaliso');
  });

  test('terminal de sistema: sem pasta nenhuma, e isso é o único caso', () {
    // A raiz vazia passa a significar SÓ isto — era o que o guard da CLI
    // pretendia barrar quando começou a barrar workspace remoto junto.
    final p = Project(
      id: '__cockpit__',
      name: 'Cockpit',
      path: '',
      colorValue: 0,
      createdAt: DateTime(2026),
      kind: WorkspaceKind.systemTerminal,
    );
    expect(p.effectiveRoot, isEmpty);
  });
}
