import 'package:cockpit/app/cockpit/data/repositories/hive_project_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/uid.dart';
import 'package:hive/hive.dart';

/// Migração one-shot do schema pré-realm (id == path) pro schema atual
/// (id = UUID + campo `realm`). Roda no bootstrap do módulo, antes de qualquer
/// leitura; é **idempotente** — registro já migrado (id ≠ path) é ignorado.
///
/// O que migra, mantendo tudo que o usuário tinha:
/// - box `projects`: re-key path → UUID, grava `realm: default` no registro;
/// - box `layouts`: re-key da mesma chave (o layout segue o workspace);
/// - `__last_selected__` legado (global) → `__last_selected__::default`.
class ProjectSchemaMigrator {
  const ProjectSchemaMigrator();

  Future<void> run(Box<dynamic> projectBox, Box<dynamic> layoutBox) async {
    for (final key in projectBox.keys.toList()) {
      final value = projectBox.get(key);
      if (value is! Map) continue;
      final id = value['id'];
      final path = value['path'];
      if (id is! String || path is! String) continue;
      if (id != path) continue; // já migrado (UUID)

      final uid = newUid();
      final migrated = Map<dynamic, dynamic>.of(value)
        ..['id'] = uid
        ..['realm'] = value['realm'] as String? ?? Realm.defaultId;
      await projectBox.put(uid, migrated);
      if (key != uid) await projectBox.delete(key);

      // Layout acompanha o workspace (mesma chave antiga = path).
      final layout = layoutBox.get(id);
      if (layout != null) {
        await layoutBox.put(uid, layout);
        await layoutBox.delete(id);
      }

      // Ponteiro legado de seleção apontava pra este workspace? Re-aponta.
      final legacy = projectBox.get(HiveProjectRepository.lastSelectedPrefix);
      if (legacy == id) {
        await projectBox.put(HiveProjectRepository.lastSelectedPrefix, uid);
      }
    }

    // Ponteiro legado (global, sem sufixo de realm) → per-realm do Default.
    // Fora do loop: cobre também o caso do valor ser `__cockpit__` (nenhum
    // registro re-keyed o teria tocado).
    final legacy = projectBox.get(HiveProjectRepository.lastSelectedPrefix);
    if (legacy is String) {
      await projectBox.put(
        '${HiveProjectRepository.lastSelectedPrefix}::${Realm.defaultId}',
        legacy,
      );
      await projectBox.delete(HiveProjectRepository.lastSelectedPrefix);
    }
  }
}
