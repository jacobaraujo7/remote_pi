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

  /// Lê o segredo de [key].
  ///
  /// [legacyKey] é a chave do formato ANTERIOR ao cofre único (plano 62): as
  /// senhas locais viviam no cofre do SO, chaveadas pelo `workspaceId`, que é
  /// gerado por máquina. Quando [key] não existe e [legacyKey] sim, o valor é
  /// **migrado** para o cofre novo e apagado do antigo — é o que faz a senha
  /// digitada no host, antes desta versão, passar a valer para os clientes
  /// remotos sem ninguém redigitar.
  Future<String?> read(String key, {String? legacyKey});

  Future<void> delete(String key);
}
