import 'package:cockpit/app/cockpit/domain/contracts/realm_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:hive/hive.dart';

/// Persiste realms numa Box do Hive, um `Map` por id (mesmo estilo schemaless
/// do `HiveProjectRepository`). O realm Default é garantido em [all]: se a box
/// está vazia (instalação nova ou pré-realm), ele é criado na hora.
class HiveRealmRepository implements RealmRepository {
  HiveRealmRepository(this._box);

  final Box<dynamic> _box;

  static const String boxName = 'realms';

  /// Chave reservada (não-Map) pro id do realm ativo; `all()` a ignora.
  static const String _activeKey = '__active__';

  @override
  Future<List<Realm>> all() async {
    final realms = _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<Realm>()
        .toList();
    if (!realms.any((r) => r.isDefault)) {
      final def = Realm(
        id: Realm.defaultId,
        name: 'Default',
        createdAt: DateTime.now(),
      );
      await save(def);
      realms.insert(0, def);
    }
    realms.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return realms;
  }

  @override
  Future<void> save(Realm realm) => _box.put(realm.id, _toMap(realm));

  @override
  Future<void> remove(String id) async {
    if (id == Realm.defaultId) return; // Default é indelével
    await _box.delete(id);
  }

  @override
  Future<String> loadActive() async {
    final v = _box.get(_activeKey);
    return v is String ? v : Realm.defaultId;
  }

  @override
  Future<void> saveActive(String id) => _box.put(_activeKey, id);

  Map<String, dynamic> _toMap(Realm r) => <String, dynamic>{
    'id': r.id,
    'name': r.name,
    'createdAt': r.createdAt.millisecondsSinceEpoch,
    'order': r.order,
  };

  Realm? _fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    if (id is! String) return null;
    return Realm(
      id: id,
      name: map['name'] as String? ?? 'Realm',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }
}
