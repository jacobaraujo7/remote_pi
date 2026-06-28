import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit/app/core/data/jsonc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripJsonc', () {
    test('remove comentários de linha e bloco', () {
      const src = '''
{
  // line
  "a": 1, /* block */
  "b": 2
}''';
      expect(jsonDecode(stripJsonc(src)), {'a': 1, 'b': 2});
    });

    test('remove vírgulas finais em objeto e array', () {
      const src = '{ "a": [1, 2, 3,], "b": 2, }';
      expect(jsonDecode(stripJsonc(src)), {
        'a': [1, 2, 3],
        'b': 2,
      });
    });

    test('NÃO toca em // , /* dentro de strings', () {
      const src = '{ "url": "https://x.com/a", "re": "a, b", "c": "/* x */" }';
      expect(jsonDecode(stripJsonc(src)), {
        'url': 'https://x.com/a',
        're': 'a, b',
        'c': '/* x */',
      });
    });

    test('escapes em strings preservados', () {
      const src = r'{ "q": "say \"hi\" //", "b": 1, }';
      expect(jsonDecode(stripJsonc(src)), {'q': 'say "hi" //', 'b': 1});
    });
  });

  group('loader com JSONC', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('jsonc_loader');
      await Directory('${tmp.path}/.cockpit').create();
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('tasks.json com comentários e vírgula final carrega', () async {
      await File('${tmp.path}/.cockpit/tasks.json').writeAsString('''
{
  // comentário de topo
  "tasks": [
    { "label": "run", "command": "flutter", "args": ["run"], }, // trailing
  ],
}''');
      final tasks = await const TasksJsonLoader().load(tmp.path);
      expect(tasks.map((t) => t.label), ['run']);
    });
  });
}
