import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/file_ops_controller.dart';
import 'package:cockpit/app/core/domain/exceptions/file_operation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registra as chamadas; `copy`/`rename` não tocam o disco (o controller só
/// consulta o disco pra escolher o nome livre).
class _SpyMutator implements FileSystemMutator {
  final List<String> calls = [];

  @override
  Future<Result<void, FileOperationError>> copy(String from, String to) async {
    calls.add('copy $from -> $to');
    return const Success(null);
  }

  @override
  Future<Result<void, FileOperationError>> rename(
    String from,
    String to,
  ) async {
    calls.add('move $from -> $to');
    return const Success(null);
  }

  @override
  Future<Result<void, FileOperationError>> createFile(String path) async =>
      const Success(null);

  @override
  Future<Result<void, FileOperationError>> createDirectory(String path) async =>
      const Success(null);

  @override
  Future<Result<void, FileOperationError>> moveToTrash(String path) async =>
      const Success(null);
}

void main() {
  late Directory tmp;
  late _SpyMutator mutator;
  late FileOpsController ctrl;
  var bumps = 0;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ops_import');
    mutator = _SpyMutator();
    bumps = 0;
    ctrl = FileOpsController(mutator)..onTreeChanged = () => bumps++;
  });

  tearDown(() => tmp.delete(recursive: true));

  test(
    'copies external sources and moves sources already in the workspace',
    () async {
      final root = tmp.path;
      final r = await ctrl.importInto(
        ['/Users/x/Downloads/a.txt', '$root/src/b.txt'],
        '$root/docs',
        workspaceRoot: root,
      );
      expect(r.isSuccess, isTrue);
      expect(mutator.calls, [
        'copy /Users/x/Downloads/a.txt -> $root/docs/a.txt',
        'move $root/src/b.txt -> $root/docs/b.txt',
      ]);
      expect(bumps, 1);
    },
  );

  test('picks a free name when the destination already exists', () async {
    final root = tmp.path;
    await Directory('$root/docs').create();
    await File('$root/docs/a.txt').writeAsString('x');
    await ctrl.importInto(
      ['/elsewhere/a.txt'],
      '$root/docs',
      workspaceRoot: root,
    );
    expect(mutator.calls, ['copy /elsewhere/a.txt -> $root/docs/a copy.txt']);
  });

  test('refuses to drop a folder into itself', () async {
    final root = tmp.path;
    final r = await ctrl.importInto(
      ['$root/src'],
      '$root/src/inner',
      workspaceRoot: root,
    );
    expect(r.isFailure, isTrue);
    expect(mutator.calls, isEmpty);
    expect(bumps, 0);
  });

  test('a source already in the target folder is a no-op', () async {
    final root = tmp.path;
    final r = await ctrl.importInto(
      ['$root/docs/a.txt'],
      '$root/docs',
      workspaceRoot: root,
    );
    expect(r.isSuccess, isTrue);
    expect(mutator.calls, isEmpty);
  });
}
