import '../entities/db_connection.dart';

/// Executor CLI-only de comandos NoSQL/cache (Redis, Mongo). Fora do contrato
/// SQL [DbDriver]: recebe o comando cru e devolve o reply já JSON-serializável
/// (null | num | bool | String | List | Map). Plano 51 (CLI-only).
/// > O parâmetro `workspaceRoot` é a raiz do workspace **no host** e só o
/// > runner remoto o usa: é metade da chave do segredo no cofre de lá (plano
/// > 62). O runner local ignora — o segredo dele vem do cofre do SO desta
/// > máquina, chaveado por workspaceId.
abstract interface class NoSqlRunner {
  /// Redis: envia `parts` (`['GET','foo']`) → reply decodificado.
  Future<Object?> redis(
    DbConnection conn,
    List<String> parts, {
    String? password,
    String workspaceRoot = '',
  });

  /// Redis em lote: roda [commands] em sequência numa **única conexão** e
  /// devolve os replies na mesma ordem. Usado pela tabela Redis (plano 52) —
  /// uma página de SCAN dispara dezenas de TYPE/TTL/preview e o modelo
  /// efêmero por comando seria proibitivo. Um comando que falha aborta o
  /// lote (comandos anteriores já executaram — não é transação).
  Future<List<Object?>> redisMany(
    DbConnection conn,
    List<List<String>> commands, {
    String? password,
    String workspaceRoot = '',
  });

  /// Mongo: roda `command` via `runCommand` → documento de resposta.
  ///
  /// [database] sobrepõe o database alvo. Ausente = o da URL da conexão (e,
  /// faltando esse, o fallback do runner). Existe porque URL de Atlas
  /// (`mongodb+srv://…/?…`) costuma vir **sem** path de database: quem browseia
  /// escolhe um e passa aqui.
  Future<Object?> mongo(
    DbConnection conn,
    Map<String, dynamic> command, {
    String? password,
    String? database,
    String workspaceRoot = '',
  });
}
