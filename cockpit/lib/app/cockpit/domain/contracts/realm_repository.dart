import 'package:cockpit/app/cockpit/domain/entities/realm.dart';

/// Persistência dos realms (conjuntos de workspaces). Contrato no domínio; a
/// implementação concreta (Hive) mora em `data/`.
abstract class RealmRepository {
  /// Todos os realms, ordenados por [Realm.order] (criação). Sempre inclui o
  /// Default — a implementação o garante.
  Future<List<Realm>> all();

  /// Cria ou atualiza um realm.
  Future<void> save(Realm realm);

  /// Remove um realm pelo id. O Default nunca é removido (no-op).
  Future<void> remove(String id);

  /// Id do realm ativo (o que o rail exibe). Default se nunca salvou.
  Future<String> loadActive();

  /// Persiste o realm ativo.
  Future<void> saveActive(String id);
}
