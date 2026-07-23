import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/file_system_mutator_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSystemMutatorImpl', () {
    const mutator = FileSystemMutatorImpl();
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ck_fsm');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('createFile cria arquivo vazio', () async {
      final path = '${dir.path}/novo.txt';
      final r = await mutator.createFile(path);
      expect(r.isSuccess, isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), isEmpty);
    });

    test('createFile falha se já existir', () async {
      final path = '${dir.path}/dup.txt';
      File(path).writeAsStringSync('x');
      final r = await mutator.createFile(path);
      expect(r.isFailure, isTrue);
    });

    test('createDirectory cria pasta', () async {
      final path = '${dir.path}/sub';
      final r = await mutator.createDirectory(path);
      expect(r.isSuccess, isTrue);
      expect(Directory(path).existsSync(), isTrue);
    });

    test('rename move o arquivo para o novo nome', () async {
      final from = '${dir.path}/a.txt';
      final to = '${dir.path}/b.txt';
      File(from).writeAsStringSync('conteudo');
      final r = await mutator.rename(from, to);
      expect(r.isSuccess, isTrue);
      expect(File(from).existsSync(), isFalse);
      expect(File(to).readAsStringSync(), 'conteudo');
    });

    test('rename renomeia pasta (com conteúdo)', () async {
      final from = '${dir.path}/old';
      final to = '${dir.path}/new';
      Directory(from).createSync();
      File('$from/inner.txt').writeAsStringSync('hi');
      final r = await mutator.rename(from, to);
      expect(r.isSuccess, isTrue);
      expect(Directory(from).existsSync(), isFalse);
      expect(File('$to/inner.txt').readAsStringSync(), 'hi');
    });

    test('rename falha se o destino já existir', () async {
      final from = '${dir.path}/x.txt';
      final to = '${dir.path}/y.txt';
      File(from).writeAsStringSync('1');
      File(to).writeAsStringSync('2');
      final r = await mutator.rename(from, to);
      expect(r.isFailure, isTrue);
    });

    test('copy duplica o arquivo mantendo o original', () async {
      final from = '${dir.path}/src.txt';
      final to = '${dir.path}/copy.txt';
      File(from).writeAsStringSync('conteudo');
      final r = await mutator.copy(from, to);
      expect(r.isSuccess, isTrue);
      expect(File(from).readAsStringSync(), 'conteudo');
      expect(File(to).readAsStringSync(), 'conteudo');
    });

    test('copy duplica pasta recursivamente', () async {
      final from = '${dir.path}/tree';
      final to = '${dir.path}/tree-copy';
      Directory('$from/nested').createSync(recursive: true);
      File('$from/a.txt').writeAsStringSync('a');
      File('$from/nested/b.txt').writeAsStringSync('b');
      final r = await mutator.copy(from, to);
      expect(r.isSuccess, isTrue);
      expect(Directory(from).existsSync(), isTrue); // original intacto
      expect(File('$to/a.txt').readAsStringSync(), 'a');
      expect(File('$to/nested/b.txt').readAsStringSync(), 'b');
    });

    test('copy falha se o destino já existir', () async {
      final from = '${dir.path}/one.txt';
      final to = '${dir.path}/two.txt';
      File(from).writeAsStringSync('1');
      File(to).writeAsStringSync('2');
      final r = await mutator.copy(from, to);
      expect(r.isFailure, isTrue);
      expect(File(to).readAsStringSync(), '2'); // não sobrescreveu
    });

    test(
      'moveToTrash em caminho inexistente é sucesso (idempotente)',
      () async {
        final r = await mutator.moveToTrash('${dir.path}/ghost.txt');
        expect(r.isSuccess, isTrue);
      },
    );

    test('moveToTrash remove o arquivo do caminho original', () async {
      // useSystemTrash: false → deleção permanente em vez de mandar pra Lixeira
      // do macOS de verdade (senão cada `flutter test` suja a Lixeira).
      const fileMutator = FileSystemMutatorImpl(useSystemTrash: false);
      final path = '${dir.path}/trash-me.txt';
      File(path).writeAsStringSync('bye');
      final r = await fileMutator.moveToTrash(path);
      expect(r.isSuccess, isTrue);
      expect(File(path).existsSync(), isFalse);
    });
  });
}
