import 'dart:convert';

import '../../domain/entities/orchestration_document.dart';

/// A resumable migration of one legacy app tab, never of a workspace inventory.
/// Every filesystem side effect follows a verified local layout checkpoint.
/// No terminal/process operation is exposed by this service.
class OrchestrationOwnershipMigration {
  const OrchestrationOwnershipMigration({
    required this.checkpoint,
    required this.read,
    required this.createNew,
    required this.newPath,
    required this.validDestination,
    required this.seed,
  });

  final Future<void> Function(Map<String, dynamic>) checkpoint;
  final Future<String?> Function(String) read;
  final Future<bool> Function(String, String) createNew;
  final String Function() newPath;
  final bool Function(String) validDestination;
  final OrchestrationDocument Function() seed;

  Future<Map<String, dynamic>> migrate(Map<String, dynamic> original) async {
    var state = _copy(original);
    if (state['ownershipVersion'] == 2) {
      // A previous attempt may have failed verifying this final checkpoint.
      await checkpoint(state);
      return state;
    }
    if (state['ownershipVersion'] != null ||
        state['type'] != 'orchestration' ||
        state['path'] is! String ||
        (state['path'] as String).isEmpty) {
      throw const FormatException(
        'Unsupported legacy orchestration descriptor',
      );
    }
    for (var attempt = 0; attempt < 16; attempt++) {
      var journal = state['ownershipMigration'];
      if (journal == null) {
        journal = {
          'version': 1,
          'sourcePath': state['path'],
          'targetPath': newPath(),
          'document': seed().encode(),
          'created': false,
        };
        state['ownershipMigration'] = journal;
      }
      if (journal is! Map ||
          journal['version'] != 1 ||
          journal['sourcePath'] != state['path'] ||
          journal['targetPath'] is! String ||
          journal['document'] is! String) {
        throw const FormatException('Invalid ownership migration journal');
      }
      final target = journal['targetPath'] as String;
      if (!validDestination(target) || target == state['path']) {
        throw const FormatException('Invalid ownership migration destination');
      }
      final planned = OrchestrationDocument.parse(
        journal['document'] as String,
      );
      await checkpoint(_copy(state));
      var text = await read(target);
      if (text == null) {
        if (!await createNew(target, planned.encode())) {
          // Another creator won the path. A distinct checkpoint must reserve
          // the next candidate before attempting to create it.
          state.remove('ownershipMigration');
          continue;
        }
        text = await read(target);
        if (text == null) {
          throw StateError('New orchestration file is unavailable');
        }
      } else if (journal['created'] != true && text != planned.encode()) {
        // Unknown/partial files are preserved, never repaired or overwritten.
        state.remove('ownershipMigration');
        continue;
      }
      final document = OrchestrationDocument.parse(text);
      journal['created'] = true;
      await checkpoint(_copy(state));
      final completed = <String, dynamic>{
        'type': 'orchestration',
        'ownershipVersion': 2,
        'path': target,
        'document': document.encode(),
        'bindings': <String, String>{},
        'sessions': <String, dynamic>{},
        'multiplexer': <String, dynamic>{},
        'dirty': false,
        'ownershipMigration': {
          'version': 1,
          'sourcePath': journal['sourcePath'],
          'targetPath': target,
          'completed': true,
        },
      };
      await checkpoint(_copy(completed));
      return completed;
    }
    throw StateError('Could not reserve a new orchestration file');
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
}
