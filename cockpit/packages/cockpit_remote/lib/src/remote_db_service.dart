import 'package:cockpit_core/cockpit_core.dart';

import 'remote_connection.dart';

/// Qual segredo da conexão o comando endereça: a senha do banco ou a
/// passphrase da chave SSH do túnel. São distintos, e a conexão pode ter um
/// sem o outro.
enum DbSecretKind {
  password('password'),
  sshPassphrase('sshPassphrase');

  const DbSecretKind(this.wire);
  final String wire;
}

/// [DbService] via protocolo (plano 58, Wave 4): manda o descritor de conexão
/// + SQL ao servidor, que executa no host e devolve o resultado já-JSON.
class RemoteDbService implements DbService {
  RemoteDbService(this._connection);

  final RemoteConnection _connection;

  @override
  Future<Map<String, Object?>> query(
    RemoteDbConnDescriptor conn,
    String sql, {
    int limit = 200,
    bool dml = false,
  }) async {
    try {
      final data = await _connection.call('db.query', {
        'conn': conn.toJson(),
        'sql': sql,
        'limit': limit,
        'dml': dml,
      });
      return (data as Map).cast<String, Object?>();
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Object?> redis(RemoteDbConnDescriptor conn, List<String> parts) async {
    try {
      return await _connection.call('db.redis', {
        'conn': conn.toJson(),
        'parts': parts,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<Object?>> redisMany(
    RemoteDbConnDescriptor conn,
    List<List<String>> commands,
  ) async {
    try {
      final data = await _connection.call('db.redisMany', {
        'conn': conn.toJson(),
        'commands': commands,
      });
      return (data as List).cast<Object?>();
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Object?> mongo(
    RemoteDbConnDescriptor conn,
    Map<String, Object?> command, {
    String? database,
  }) async {
    try {
      return await _connection.call('db.mongo', {
        'conn': conn.toJson(),
        'command': command,
        'database': ?database,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  /// Grava a senha da conexão **no cofre do host** (plano 62). Write-only por
  /// contrato: não existe leitura de volta, nem aqui nem no protocolo.
  Future<void> setSecret({
    required String workspaceRoot,
    required String connName,
    required String value,
    DbSecretKind kind = DbSecretKind.password,
  }) async {
    try {
      await _connection.call('db.secretSet', {
        'root': workspaceRoot,
        'conn': connName,
        'value': value,
        'kind': kind.wire,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  /// Move a senha de [fromConn] para [toConn] **dentro do host**.
  ///
  /// É um método próprio (e não delete+set) porque o cliente não pode ler o
  /// segredo para regravá-lo sob o nome novo: renomear sem isto perdia a senha.
  Future<void> renameSecret({
    required String workspaceRoot,
    required String fromConn,
    required String toConn,
  }) async {
    try {
      await _connection.call('db.secretRename', {
        'root': workspaceRoot,
        'from': fromConn,
        'to': toConn,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  /// Apaga a senha da conexão no cofre do host (conexão removida, renomeada,
  /// ou `savePassword` desligado).
  Future<void> deleteSecret({
    required String workspaceRoot,
    required String connName,
    DbSecretKind kind = DbSecretKind.password,
  }) async {
    try {
      await _connection.call('db.secretDelete', {
        'root': workspaceRoot,
        'conn': connName,
        'kind': kind.wire,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  /// Confia numa host key de bastion **no host**.
  ///
  /// Write-only, como o cofre: a decisão é do humano aqui (é o cliente que tem
  /// o diálogo com o fingerprint), o estado fica lá — é lá que o túnel abre.
  Future<void> trustHostKey({
    required String endpoint,
    required String fingerprint,
  }) async {
    try {
      await _connection.call('db.hostKeyTrust', {
        'endpoint': endpoint,
        'fingerprint': fingerprint,
      });
    } on RemoteRpcException catch (e) {
      throw _mapError(e);
    }
  }

  DbServiceException _mapError(RemoteRpcException e) => DbServiceException(
    DbErrorKind.values.asNameMap()[e.code] ?? DbErrorKind.queryFailed,
    e.detail,
  );
}
