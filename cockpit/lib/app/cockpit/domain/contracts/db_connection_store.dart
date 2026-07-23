import '../entities/db_connection.dart';

/// Conexões de banco de um workspace: registradas em
/// `.cockpit/databases.json` (versionado), overlay pessoal em
/// `.cockpit/databases.local.json` (gitignored, merge por cima, por nome) e
/// sqlites **detectados** no repo (magic header — nunca persistidos).
abstract interface class DbConnectionStore {
  /// Carrega tudo, na ordem: registradas → locais → detectadas (sem duplicar
  /// path já registrado).
  Future<List<DbConnection>> load(String workspaceRoot);

  /// Persiste as conexões de origem `registered` (as `local` ficam no
  /// arquivo local; `detected` nunca é escrito).
  Future<void> save(String workspaceRoot, List<DbConnection> connections);
}

/// Segredos de conexão no cofre nativo do SO (`flutter_secure_storage`:
/// Keychain / Credential Manager / Secret Service). Chave composta pelo
/// chamador (`cockpit.db.<workspaceId>.<nome>`). Falhas do cofre lançam —
/// nunca degradar silenciosamente (lição do pareamento).
abstract interface class DbSecrets {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}
