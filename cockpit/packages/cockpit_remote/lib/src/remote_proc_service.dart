import 'remote_connection.dart';

/// `proc.run` via protocolo: roda uma linha de shell NO HOST e devolve o mapa
/// `{code, stdout, stderr, timedOut}` do `exec` (mesmo formato do local). É o
/// que atende `cockpit exec` num terminal remoto e `cockpit("exec …")` num
/// `.panel` de workspace remoto. Erros tipados do servidor (`cwd_not_found`,
/// `bad_request`, `unknown_method` num server antigo) chegam como
/// [RemoteRpcException].
class RemoteProcService {
  RemoteProcService(this._connection);

  final RemoteConnection _connection;

  Future<Map<String, Object?>> run(
    String command, {
    String? cwd,
    int timeoutSeconds = 60,
  }) async {
    final result = await _connection.call('proc.run', {
      'command': command,
      if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
      'timeout': timeoutSeconds,
    });
    return result is Map ? result.cast<String, Object?>() : const {};
  }
}
