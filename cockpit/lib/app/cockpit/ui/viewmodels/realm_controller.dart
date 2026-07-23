import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:cockpit/app/cockpit/domain/contracts/realm_repository.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/uid.dart';
import 'package:flutter/foundation.dart';

/// Coleção de realms + recorte ativo, extraída do `CockpitViewModel`
/// (refactor 2026-07-19). Dona da lista, do id ativo e da persistência
/// ([RealmRepository]); a **orquestração** de troca (seleção de workspace,
/// migração de projetos ao excluir) permanece no VM, que delega o estado
/// pra cá.
class RealmController extends ChangeNotifier {
  RealmController(this._repo);

  final RealmRepository _repo;

  final List<Realm> _list = <Realm>[];
  String _activeId = Realm.defaultId;

  /// Realms na ordem de exibição do dropdown do footer.
  List<Realm> get realms => List<Realm>.unmodifiable(_list);

  String get activeId => _activeId;

  Realm get active => _list.firstWhere(
    (r) => r.id == _activeId,
    orElse: () => Realm(
      id: Realm.defaultId,
      name: 'Default',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );

  bool exists(String id) => _list.any((r) => r.id == id);

  /// Carrega lista + ativo do repositório (boot). Ativo que sumiu (dado
  /// corrompido) cai pro Default.
  Future<void> load() async {
    _list
      ..clear()
      ..addAll(await _repo.all());
    _activeId = await _repo.loadActive();
    if (!exists(_activeId)) _activeId = Realm.defaultId;
  }

  /// Marca [id] como ativo e persiste. `false` se o realm não existe ou já é
  /// o ativo — o chamador (VM) só orquestra a troca quando devolve `true`.
  bool setActive(String id) {
    if (_activeId == id || !exists(id)) return false;
    _activeId = id;
    unawaited(_repo.saveActive(id));
    return true;
  }

  /// Realm vizinho na ordem do seletor (⌘` / ⌘⇧`): [delta] +1 avança, -1
  /// volta, com wrap-around. `null` com 0–1 realms.
  Realm? neighbor(int delta) {
    if (_list.length < 2) return null;
    final idx = _list.indexWhere((r) => r.id == _activeId);
    return _list[(idx + delta + _list.length) % _list.length];
  }

  /// Cria um realm novo (não troca o ativo — a UI decide se troca em seguida).
  Future<Realm> create(String name) async {
    final nextOrder = _list.isEmpty
        ? 0
        : _list.map((r) => r.order).reduce(max) + 1;
    final realm = Realm(
      id: newUid(),
      name: name.trim(),
      createdAt: DateTime.now(),
      order: nextOrder,
    );
    _list.add(realm);
    await _repo.save(realm);
    notifyListeners();
    return realm;
  }

  Future<void> rename(String id, String name) async {
    final idx = _list.indexWhere((r) => r.id == id);
    if (idx < 0 || name.trim().isEmpty) return;
    final renamed = _list[idx].copyWith(name: name.trim());
    _list[idx] = renamed;
    await _repo.save(renamed);
    notifyListeners();
  }

  /// Remove [id] da coleção e do repositório. O Default é indelével; a
  /// migração dos workspaces e a troca de ativo são responsabilidade do VM
  /// (que chama isto por último).
  Future<void> remove(String id) async {
    if (id == Realm.defaultId) return;
    _list.removeWhere((r) => r.id == id);
    await _repo.remove(id);
    notifyListeners();
  }
}
