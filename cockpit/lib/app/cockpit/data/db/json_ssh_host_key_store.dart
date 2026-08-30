import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';

/// Host keys confiadas (TOFU) numa chave própria do store de settings — reusa
/// o store (é só um mapa endpoint→fingerprint), no mesmo padrão do
/// `JsonDismissedUpdateStore`.
///
/// Deliberadamente **não** é o `known_hosts` do sistema: o `dartssh2` não lê
/// aquele arquivo (decisão C do plano 54), então manter o nosso é o que
/// permite detectar troca de host key.
class JsonSshHostKeyStore implements SshHostKeyStore {
  JsonSshHostKeyStore(this._store);

  final JsonStateStore _store;

  static const String _key = 'ssh_known_host_keys';

  Map<String, String> _all() {
    final raw = _store.get(_key);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  @override
  String? trusted(String endpoint) => _all()[endpoint];

  @override
  Future<void> trust(String endpoint, String fingerprint) =>
      _store.put(_key, _all()..[endpoint] = fingerprint);

  @override
  Future<void> forget(String endpoint) =>
      _store.put(_key, _all()..remove(endpoint));
}
