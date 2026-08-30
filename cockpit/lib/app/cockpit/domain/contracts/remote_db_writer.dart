import '../entities/db_connection.dart';

/// Escrita da configuração de banco de um workspace **remoto** (plano 62).
///
/// A leitura já existia (`loadRemoteConnections`, via `fs.read`); a escrita
/// não, e por isso salvar uma conexão num workspace remoto era impossível: o
/// `DatabaseViewModel` chamava o store LOCAL com a raiz do host, e o
/// `File('<caminho do host>/.cockpit/databases.json').parent.create()`
/// estourava no disco do cliente antes de qualquer coisa ser gravada.
///
/// O segredo é **write-only** por contrato: dá pra gravar e apagar, nunca ler
/// de volta. Quem lê é o servidor do host, na hora de abrir a conexão.
abstract interface class RemoteDbWriter {
  /// Regrava o `databases.json` do workspace **no host**.
  Future<void> saveConnections(
    String workspaceRoot,
    List<DbConnection> connections,
  );

  /// Guarda a senha de [connName] no cofre **do host**.
  Future<void> setSecret(
    String workspaceRoot,
    String connName,
    String value,
  );

  /// Apaga a senha de [connName] no cofre do host (conexão removida ou com
  /// `savePassword` desligado).
  Future<void> deleteSecret(String workspaceRoot, String connName);

  /// Move a senha de [fromConn] para [toConn] no cofre do host, sem que o valor
  /// passe por aqui — o cliente não pode lê-lo (write-only).
  Future<void> renameSecret(
    String workspaceRoot,
    String fromConn,
    String toConn,
  );

  /// Guarda (ou apaga, com [value] nulo) a **passphrase da chave SSH** do túnel
  /// no cofre do host. Segredo distinto da senha do banco: quem abre o bastion
  /// é o host, com a chave privada de lá.
  Future<void> setSshPassphrase(
    String workspaceRoot,
    String connName,
    String? value,
  );

  /// Confia numa host key de bastion no host. O humano decide aqui (é o cliente
  /// que mostra o fingerprint); o estado fica lá, onde o túnel abre.
  Future<void> trustHostKey(String endpoint, String fingerprint);
}
