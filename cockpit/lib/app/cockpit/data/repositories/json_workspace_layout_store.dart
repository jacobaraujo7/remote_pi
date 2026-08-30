import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';

/// Persiste o documento de layout num [JsonStateStore], **uma String JSON por
/// `projectId`** — mesmo formato que a Box antiga guardava, então a migração
/// Hive→JSON preserva os valores byte a byte. Serializar pra String também
/// mantém o contrato de devolver sempre um `Map<String, dynamic>` limpo.
class JsonWorkspaceLayoutStore implements WorkspaceLayoutStore {
  JsonWorkspaceLayoutStore(this._store);

  final JsonStateStore _store;

  static const String storeName = 'layouts';

  @override
  Future<Map<String, dynamic>?> load(String projectId) async {
    final raw = _store.get(projectId);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // documento corrompido → trata como inexistente
    }
  }

  @override
  Future<void> save(String projectId, Map<String, dynamic> document) =>
      _store.put(projectId, jsonEncode(document));

  @override
  Future<void> remove(String projectId) => _store.delete(projectId);

  @override
  Future<Map<String, Map<String, dynamic>>> loadAll() async {
    final out = <String, Map<String, dynamic>>{};
    // `keys` é snapshot: carregar dentro do loop não itera o mapa vivo.
    for (final id in _store.keys.toList()) {
      final doc = await load(id);
      if (doc != null) out[id] = doc;
    }
    return out;
  }
}
