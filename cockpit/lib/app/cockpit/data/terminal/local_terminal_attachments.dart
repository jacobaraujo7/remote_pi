import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import '../../domain/contracts/terminal_attachments.dart';

class LocalTerminalAttachmentStore implements TerminalAttachmentStore {
  const LocalTerminalAttachmentStore();

  @override
  Future<TerminalImportResult> import({
    required String projectRoot,
    required List<String> paths,
    Uint8List? image,
    required bool Function() isAlive,
    required void Function(int completed, int total) onProgress,
  }) async {
    final imported = <String>[];
    final errors = <String>[];
    Directory? operation;
    Future<Directory> destination() async {
      if (operation != null) return operation!;
      if (projectRoot.isEmpty ||
          !p.isAbsolute(projectRoot) ||
          !await Directory(projectRoot).exists()) {
        throw const FileSystemException('Select a writable local project');
      }
      final root = await Directory(projectRoot).resolveSymbolicLinks();
      final metadata = Directory(p.join(root, '.cockpit'));
      Future<void> checkContained(Directory directory) async {
        if (await directory.exists()) {
          final resolved = await directory.resolveSymbolicLinks();
          if (!p.isWithin(root, resolved)) {
            throw FileSystemException(
              'Attachment directory points outside the project',
              directory.path,
            );
          }
        }
      }

      await checkContained(metadata);
      await metadata.create();
      final base = Directory(p.join(metadata.path, 'attachments'));
      await checkContained(base);
      await base.create();
      operation = await base.createTemp('paste-');
      return operation!;
    }

    final total = image != null ? 1 : paths.length;
    onProgress(0, total);
    if (image != null) {
      if (!isAlive()) return const TerminalImportResult([], []);
      try {
        final dir = await destination();
        if (!isAlive()) return const TerminalImportResult([], []);
        final file = File(p.join(dir.path, 'clipboard.png'));
        await file.writeAsBytes(image, flush: true);
        imported.add(file.path);
      } catch (error) {
        errors.add('clipboard.png: $error');
      }
      onProgress(1, total);
    } else {
      for (var i = 0; i < paths.length; i++) {
        if (!isAlive()) break;
        final path = paths[i];
        try {
          final type = await FileSystemEntity.type(path);
          if (type == FileSystemEntityType.directory) {
            imported.add(await Directory(path).resolveSymbolicLinks());
          } else if (type == FileSystemEntityType.file) {
            final dir = await destination();
            if (!isAlive()) break;
            final name = p.basename(path);
            var dest = p.join(dir.path, name);
            var suffix = 1;
            while (await FileSystemEntity.type(dest) !=
                FileSystemEntityType.notFound) {
              dest = p.join(
                dir.path,
                '${p.basenameWithoutExtension(name)}-${suffix++}${p.extension(name)}',
              );
            }
            // A private staging directory cannot collide with an imported
            // filename such as "report.partial". Publish only complete copies.
            final staging = await dir.createTemp('.copy-');
            try {
              final partial = await File(
                path,
              ).copy(p.join(staging.path, 'contents'));
              await partial.rename(dest);
              imported.add(dest);
            } finally {
              await staging.delete(recursive: true);
            }
          } else {
            throw FileSystemException('File not found or unsupported', path);
          }
        } catch (error) {
          errors.add('$path: $error');
        }
        onProgress(i + 1, total);
      }
    }
    return TerminalImportResult(imported, errors);
  }
}

typedef WslProcessRunner =
    Future<ProcessResult> Function(List<String> arguments);

Future<ProcessResult> _runWsl(List<String> arguments) => Process.run(
  'wsl.exe',
  arguments,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

class LocalTerminalPathConverter implements TerminalPathConverter {
  const LocalTerminalPathConverter({this._run = _runWsl});
  final WslProcessRunner _run;
  @override
  Future<String> forWsl(String path, String distribution) async {
    final result = await _run([
      '--distribution',
      distribution,
      '--exec',
      'wslpath',
      '-a',
      '-u',
      path,
    ]).timeout(const Duration(seconds: 10));
    final converted = result.stdout.toString().replaceFirst(
      RegExp(r'\r?\n$'),
      '',
    );
    if (result.exitCode != 0 || !converted.startsWith('/')) {
      throw FileSystemException(
        'Could not convert path for WSL: ${result.stderr}',
        path,
      );
    }
    final check = await _run([
      '--distribution',
      distribution,
      '--exec',
      'test',
      '-e',
      converted,
    ]).timeout(const Duration(seconds: 10));
    if (check.exitCode != 0) {
      throw FileSystemException('Path is not accessible in WSL', converted);
    }
    return converted;
  }
}
