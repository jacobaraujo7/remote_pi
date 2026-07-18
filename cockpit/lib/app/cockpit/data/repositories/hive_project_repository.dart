import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:hive/hive.dart';

/// Persiste projetos numa Box do Hive, um `Map` por id (sem TypeAdapters —
/// só tipos primitivos, então não precisa de code-gen).
class HiveProjectRepository implements ProjectRepository {
  HiveProjectRepository(this._box);

  /// Box aberta no bootstrap (`config/`). Guarda `Map` por `project.id`.
  final Box<dynamic> _box;

  static const String boxName = 'projects';

  /// Prefixo das chaves reservadas (não-Map) do último workspace selecionado,
  /// **uma por realm** (`__last_selected__::<realmId>`). Não colide com ids de
  /// projeto (UUIDs) e o `all()` as ignora (`whereType<Map>`). A chave legada
  /// sem sufixo é migrada pro realm Default pelo `ProjectSchemaMigrator`.
  static const String lastSelectedPrefix = '__last_selected__';

  static String _lastSelectedKey(String realmId) =>
      '$lastSelectedPrefix::$realmId';

  @override
  Future<List<Project>> all() async {
    final projects = _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<Project>()
        .toList();
    // Ordem manual do usuário (drag-drop); `createdAt` como desempate e como
    // fallback para dados antigos (todos com order=0 → caem no createdAt).
    projects.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return projects;
  }

  @override
  Future<void> save(Project project) => _box.put(project.id, _toMap(project));

  @override
  Future<void> remove(String id) => _box.delete(id);

  @override
  Future<String?> loadLastSelected(String realmId) async {
    final v = _box.get(_lastSelectedKey(realmId));
    return v is String ? v : null;
  }

  @override
  Future<void> saveLastSelected(String realmId, String? id) async {
    if (id == null) {
      await _box.delete(_lastSelectedKey(realmId));
    } else {
      await _box.put(_lastSelectedKey(realmId), id);
    }
  }

  Map<String, dynamic> _toMap(Project p) => <String, dynamic>{
    'id': p.id,
    'name': p.name,
    'path': p.path,
    'color': p.colorValue,
    'createdAt': p.createdAt.millisecondsSinceEpoch,
    'order': p.order,
    'image': p.imagePath,
    'realm': p.realmId,
  };

  Project? _fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final path = map['path'];
    if (id is! String || path is! String) return null;
    return Project(
      id: id,
      name: map['name'] as String? ?? path,
      path: path,
      colorValue: (map['color'] as num?)?.toInt() ?? 0xFF2F6FF0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      // Ausente em dados de versões anteriores → 0 (ordena por createdAt).
      order: (map['order'] as num?)?.toInt() ?? 0,
      imagePath: map['image'] as String?,
      // Ausente em dados pré-realm → Default (o migrador normalmente já gravou).
      realmId: map['realm'] as String? ?? Realm.defaultId,
    );
  }
}
