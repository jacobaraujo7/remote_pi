/// Guardrails do caminho **dos agentes (CLI)** sobre conexões `read`
/// (plano 51 / conversa 2026-07-20). Funções puras — o enforcement mora no
/// `CockpitCliHandler`; a GUI (tab `.dbq`, browsers) não passa por aqui.
///
/// Filosofia: errar pro lado seguro. O gate é textual (não um parser SQL
/// completo), então um SELECT exótico pode ser recusado — o agente recebe um
/// erro claro e o humano libera trocando o `access` da conexão pra
/// `readwrite`. O contrário (escrita passando como leitura) é o que não pode.
library;

/// Primeira palavra de cada statement SQL aceita numa conexão `read`.
const _readKeywords = {
  'select',
  'with', // CTE — validado também contra palavras de escrita no corpo
  'explain',
  'show',
  'describe',
  'desc',
  'pragma', // leitura de pragma; atribuição (`pragma x = y`) é recusada
  'values',
};

/// Palavras que denunciam escrita dentro de um statement (cobre o corpo de
/// CTEs `WITH ... INSERT`, `EXPLAIN ANALYZE` de DML etc.).
final _writeWordRe = RegExp(
  r'\b(insert|update|delete|merge|replace|upsert|drop|create|alter|truncate|'
  r'grant|revoke|vacuum|attach|detach|reindex|copy|call|exec|execute|set|'
  r'lock|rename)\b',
  caseSensitive: false,
);

/// Comentários SQL (`--` até o fim da linha, `/* ... */`) — removidos antes
/// da análise pra palavra de escrita comentada não gerar recusa falsa.
final _sqlCommentRe = RegExp(r'--[^\n]*|/\*.*?\*/', dotAll: true);

/// Valida [sql] (um statement OU script `;`-separado) pra uma conexão `read`.
/// Devolve `null` quando é leitura; senão a mensagem de erro (kind
/// `read_only_connection`) explicando o que foi recusado.
String? sqlReadViolation(String sql) {
  final cleaned = sql.replaceAll(_sqlCommentRe, ' ');
  // Split ingênuo por `;` é suficiente aqui: um `;` dentro de string literal
  // geraria um "statement" extra que, se contiver palavra de escrita, recusa
  // — falso positivo aceitável (nunca falso negativo).
  for (final raw in cleaned.split(';')) {
    final st = raw.trim();
    if (st.isEmpty) continue;
    final first = st.split(RegExp(r'\s+')).first.toLowerCase();
    if (!_readKeywords.contains(first)) {
      return 'read_only_connection: "${first.toUpperCase()}" is not allowed '
          'on a read-only connection — enable Read & write on this '
          'connection in the Database panel';
    }
    // `pragma x = y` escreve configuração; leitura de pragma não tem `=`.
    if (first == 'pragma' && st.contains('=')) {
      return 'read_only_connection: PRAGMA assignment is not allowed on a '
          'read-only connection';
    }
    // Metadados (`SHOW CREATE TABLE`, `DESCRIBE`…) carregam palavras de
    // escrita no NOME do que descrevem, sem executá-las — o scan de corpo só
    // vale pra statements que executam o que contêm (SELECT/CTE/EXPLAIN,
    // onde `EXPLAIN ANALYZE <dml>` roda o DML de verdade).
    const scanBody = {'select', 'with', 'values', 'explain'};
    if (scanBody.contains(first) && _writeWordRe.hasMatch(st)) {
      final word = _writeWordRe.firstMatch(st)!.group(0)!.toUpperCase();
      return 'read_only_connection: statement contains "$word" — not allowed '
          'on a read-only connection (enable Read & write in the Database '
          'panel if this is intentional)';
    }
  }
  return null;
}

/// Comandos Redis permitidos numa conexão `read` (whitelist — comando fora
/// dela é recusado). Cobre leitura de todos os tipos + introspecção.
const _redisReadCommands = {
  'get', 'mget', 'strlen', 'getrange', 'exists', 'type', 'ttl', 'pttl',
  'keys', 'scan', 'randomkey', 'dbsize', 'memory', 'object', 'dump',
  // hash
  'hget', 'hmget', 'hgetall', 'hkeys', 'hvals', 'hlen', 'hexists', 'hscan',
  'hstrlen', 'hrandfield',
  // list
  'lrange', 'llen', 'lindex', 'lpos',
  // set
  'smembers', 'sismember', 'smismember', 'scard', 'srandmember', 'sscan',
  'sinter', 'sunion', 'sdiff', 'sintercard',
  // sorted set
  'zrange', 'zrangebyscore', 'zrangebylex', 'zrevrange', 'zcard', 'zcount',
  'zscore', 'zmscore', 'zrank', 'zrevrank', 'zscan', 'zrandmember',
  'zlexcount',
  // stream / bitmap / hll (leitura)
  'xrange', 'xrevrange', 'xlen', 'xread', 'xinfo', 'bitcount', 'bitpos',
  'getbit', 'pfcount',
  // server (introspecção)
  'ping', 'echo', 'info', 'time', 'command', 'client', 'config',
};

/// Valida um comando Redis (`['SET','k','v']`) pra conexão `read`.
/// `null` = permitido; senão a mensagem de recusa.
String? redisReadViolation(List<String> parts) {
  if (parts.isEmpty) return null;
  final cmd = parts.first.toLowerCase();
  if (_redisReadCommands.contains(cmd)) {
    // `CONFIG SET` / `CLIENT KILL` etc.: subcomando decide — só GET/LIST/INFO.
    if ((cmd == 'config' || cmd == 'client' || cmd == 'memory') &&
        parts.length > 1) {
      final sub = parts[1].toLowerCase();
      const readSubs = {'get', 'list', 'info', 'getname', 'usage', 'stats',
          'doctor', 'help'};
      if (!readSubs.contains(sub)) {
        return 'read_only_connection: "${parts.first.toUpperCase()} '
            '${parts[1].toUpperCase()}" is not allowed on a read-only '
            'connection';
      }
    }
    return null;
  }
  return 'read_only_connection: "${parts.first.toUpperCase()}" is not allowed '
      'on a read-only connection — enable Read & write on this connection '
      'in the Database panel';
}

/// Comandos Mongo (primeira chave do runCommand) permitidos em `read`.
const _mongoReadCommands = {
  'find', 'aggregate', 'count', 'distinct', 'listcollections',
  'listindexes', 'listdatabases', 'collstats', 'dbstats', 'explain',
  'buildinfo', 'hello', 'ismaster', 'ping', 'serverstatus',
};

/// Valida um runCommand Mongo pra conexão `read`. `aggregate` é leitura,
/// EXCETO com estágio `$out`/`$merge` (escrevem coleção). `null` = permitido.
String? mongoReadViolation(Map<String, dynamic> command) {
  if (command.isEmpty) return null;
  final cmd = command.keys.first.toLowerCase();
  if (!_mongoReadCommands.contains(cmd)) {
    return 'read_only_connection: "${command.keys.first}" is not allowed on '
        'a read-only connection — enable Read & write on this connection in '
        'the Database panel';
  }
  if (cmd == 'aggregate') {
    final pipeline = command['pipeline'];
    if (pipeline is List) {
      for (final stage in pipeline) {
        if (stage is Map &&
            (stage.containsKey(r'$out') || stage.containsKey(r'$merge'))) {
          return r'read_only_connection: aggregate with $out/$merge writes '
              'to a collection — not allowed on a read-only connection';
        }
      }
    }
  }
  return null;
}
