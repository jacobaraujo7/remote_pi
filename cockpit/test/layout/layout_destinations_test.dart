import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/services/layout_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

Project _p(String id, String path, {String realmId = 'r1'}) => Project(
  id: id,
  name: id,
  path: path,
  colorValue: 0,
  createdAt: DateTime(2026),
  realmId: realmId,
);

void main() {
  test('um workspace contendo o arquivo é o destino', () {
    final projects = [_p('a', '/home/j/app'), _p('b', '/home/j/other')];
    final d = layoutDestinationsFor('/home/j/app/dev.ckp', projects);
    expect(d.map((p) => p.id), ['a']);
  });

  test('nenhum workspace contém o arquivo (Downloads)', () {
    final projects = [_p('a', '/home/j/app')];
    expect(layoutDestinationsFor('/home/j/Downloads/x.ckp', projects), isEmpty);
  });

  test('o mesmo path em dois realms devolve os dois (a UI pergunta)', () {
    final projects = [
      _p('a', '/home/j/app'),
      _p('b', '/home/j/app', realmId: 'r2'),
    ];
    final d = layoutDestinationsFor('/home/j/app/dev.ckp', projects);
    expect(d.map((p) => p.id), containsAll(<String>['a', 'b']));
    expect(d, hasLength(2));
  });

  test('aninhados: o mais específico vem primeiro', () {
    final projects = [_p('mono', '/home/j'), _p('app', '/home/j/app')];
    final d = layoutDestinationsFor('/home/j/app/dev.ckp', projects);
    expect(d.map((p) => p.id), ['app', 'mono']);
  });

  test('prefixo parcial não conta como "dentro"', () {
    final projects = [_p('a', '/home/j/app')];
    expect(layoutDestinationsFor('/home/j/app2/dev.ckp', projects), isEmpty);
  });

  test('workspace sem pasta local (Cockpit sintético) nunca é destino', () {
    final projects = [Project.systemTerminal()];
    expect(layoutDestinationsFor('/home/j/app/dev.ckp', projects), isEmpty);
  });
}
