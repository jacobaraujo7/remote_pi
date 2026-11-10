import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/services/file_nesting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FileNode file(String name) =>
      FileNode(name: name, path: '/project/$name', isDirectory: false);

  test('groups matching siblings and allows nested generated files', () {
    final nodes = [
      file('app.ts'),
      file('app.js'),
      file('app.js.map'),
      file('other.js'),
    ];
    final groups = nestFiles(nodes, {
      '*.ts': r'${capture}.js',
      '*.js': r'${capture}.js.map',
    });
    expect(groups['/project/app.ts']?.map((n) => n.name), ['app.js']);
    expect(groups['/project/app.js']?.map((n) => n.name), ['app.js.map']);
    expect(
      groups.values.expand((v) => v).map((n) => n.name),
      isNot(contains('other.js')),
    );
  });

  test('does not group directories or form cycles', () {
    final nodes = [
      file('a'),
      file('b'),
      const FileNode(name: 'b', path: '/project/subdir', isDirectory: true),
    ];
    final groups = nestFiles(nodes, {'a': 'b', 'b': 'a'});
    expect(groups['/project/a']?.single.path, '/project/b');
    expect(groups['/project/b'], isNull);
  });
}
