import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/redis_key.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';

/// Operações da tabela Redis (plano 52) sobre o [DbQueryService.redisBatch] —
/// os comandos são os mesmos que um agente mandaria via `cockpit redis`
/// (decisão G: paridade agent-first por construção).
///
/// Regras herdadas do plano:
/// - SCAN paginado sempre, nunca `KEYS *` (decisão E);
/// - edição parte de [readFull], nunca do preview truncado (decisão C);
/// - reescrever composto = DEL + recriar preservando TTL (a natureza do
///   Redis; o serviço lê o TTL antes e o re-aplica).
class RedisBrowseService {
  RedisBrowseService(this._db);

  final DbQueryService _db;

  /// COUNT do SCAN — tamanho aproximado da página.
  static const scanCount = 100;

  /// Elementos de composto lidos pro preview (o resto fica pro [readFull]).
  static const _previewElems = 20;

  /// Bytes de STRING lidos pro preview (GETRANGE — não puxa blobs gigantes).
  static const _previewChars = 300;

  ({String root, String id, String conn})? _target;

  /// Aponta o serviço pra conexão da tab. Chamado pelo widget no mount/update.
  void target({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
  }) => _target = (root: workspaceRoot, id: workspaceId, conn: connName);

  Future<List<Object?>> _batch(List<List<String>> commands) {
    final t = _target;
    if (t == null) {
      throw const DbQueryException('query_failed', 'No connection targeted.');
    }
    return _db.redisBatch(
      workspaceRoot: t.root,
      workspaceId: t.id,
      connName: t.conn,
      commands: commands,
    );
  }

  /// Uma página de chaves: SCAN + TYPE/TTL/preview de cada chave da página.
  Future<RedisScanPage> scan({String pattern = '', String cursor = '0'}) async {
    final scanReply = await _batch([
      [
        'SCAN',
        cursor,
        if (pattern.isNotEmpty && pattern != '*') ...['MATCH', pattern],
        'COUNT',
        '$scanCount',
      ],
    ]);
    final page = scanReply.first;
    if (page is! List || page.length < 2 || page[1] is! List) {
      throw DbQueryException('query_failed', 'Unexpected SCAN reply: $page');
    }
    final next = '${page[0]}';
    final keys = [for (final k in page[1] as List) '$k'];
    if (keys.isEmpty) return RedisScanPage(entries: const [], cursor: next);

    // TYPE + TTL de todas as chaves, numa conexão só.
    final meta = await _batch([
      for (final k in keys) ...[
        ['TYPE', k],
        ['TTL', k],
      ],
    ]);
    final kinds = <RedisValueKind>[];
    final ttls = <int>[];
    for (var i = 0; i < keys.length; i++) {
      kinds.add(RedisValueKind.fromRaw('${meta[i * 2]}'));
      ttls.add(int.tryParse('${meta[i * 2 + 1]}') ?? -1);
    }

    // Preview por tipo (chaves que sumiram entre o SCAN e aqui viram 'none' →
    // kind other com preview vazio; o refresh as remove).
    final previewCmds = <List<String>>[];
    final previewOwner = <int>[];
    for (var i = 0; i < keys.length; i++) {
      final cmd = _previewCommand(keys[i], kinds[i]);
      if (cmd != null) {
        previewCmds.add(cmd);
        previewOwner.add(i);
      }
    }
    final previews = List<String>.filled(keys.length, '');
    if (previewCmds.isNotEmpty) {
      final replies = await _batch(previewCmds);
      for (var i = 0; i < replies.length; i++) {
        final owner = previewOwner[i];
        previews[owner] = _formatPreview(kinds[owner], replies[i]);
      }
    }

    return RedisScanPage(
      entries: [
        for (var i = 0; i < keys.length; i++)
          RedisKeyEntry(
            key: keys[i],
            kind: kinds[i],
            ttl: ttls[i],
            preview: previews[i],
          ),
      ],
      cursor: next,
    );
  }

  /// Re-lê TYPE/TTL/preview de uma chave (pós-escrita). `null` = chave sumiu.
  Future<RedisKeyEntry?> refreshEntry(String key) async {
    final meta = await _batch([
      ['TYPE', key],
      ['TTL', key],
    ]);
    final kind = RedisValueKind.fromRaw('${meta[0]}');
    if ('${meta[0]}' == 'none') return null;
    final ttl = int.tryParse('${meta[1]}') ?? -1;
    final cmd = _previewCommand(key, kind);
    final preview = cmd == null
        ? ''
        : _formatPreview(kind, (await _batch([cmd])).first);
    return RedisKeyEntry(key: key, kind: kind, ttl: ttl, preview: preview);
  }

  /// Valor completo pro editor — STRING crua; compostos como JSON indentado.
  Future<String> readFull(String key, RedisValueKind kind) async {
    final reply = (await _batch([_fullCommand(key, kind)])).first;
    if (kind == RedisValueKind.string) return reply == null ? '' : '$reply';
    return const JsonEncoder.withIndent('  ').convert(_decode(kind, reply));
  }

  /// STRING: SET preservando o TTL (KEEPTTL — sem ele o SET zera a expiração).
  Future<void> writeString(String key, String value) async {
    await _batch([
      ['SET', key, value, 'KEEPTTL'],
    ]);
  }

  /// Composto: DEL + recriar a partir do JSON validado, re-aplicando o TTL
  /// vigente. Lança [DbQueryException] `query_failed` em JSON inválido —
  /// nada chega ao servidor nesse caso (decisão C).
  Future<void> writeComposite(
    String key,
    RedisValueKind kind,
    String jsonText,
  ) async {
    final build = _buildCommand(key, kind, jsonText); // valida ANTES do DEL
    final ttlReply = await _batch([
      ['TTL', key],
    ]);
    final ttl = int.tryParse('${ttlReply.first}') ?? -1;
    await _batch([
      ['DEL', key],
      build,
      if (ttl > 0) ['EXPIRE', key, '$ttl'],
    ]);
  }

  /// Renomeia uma chave (valor e TTL preservados — RENAME é atômico).
  /// RENAMENX, não RENAME: recusa sobrescrever uma chave destino existente,
  /// mesma filosofia do [create].
  Future<void> rename(String key, String newKey) async {
    if (newKey.isEmpty) {
      throw const DbQueryException('query_failed', 'Key must not be empty.');
    }
    if (newKey == key) return;
    final reply = await _batch([
      ['RENAMENX', key, newKey],
    ]);
    if ('${reply.first}' == '0') {
      throw DbQueryException('query_failed', 'Key "$newKey" already exists.');
    }
  }

  /// TTL: segundos > 0 = EXPIRE; `null` = PERSIST (sem expiração).
  Future<void> setTtl(String key, int? seconds) async {
    await _batch([
      if (seconds == null || seconds < 0)
        ['PERSIST', key]
      else
        ['EXPIRE', key, '$seconds'],
    ]);
  }

  Future<void> delete(String key) async {
    await _batch([
      ['DEL', key],
    ]);
  }

  /// Cria uma chave nova. Recusa sobrescrever silenciosamente ([DbQueryException]
  /// se a chave já existe). [valueText]: STRING crua; compostos em JSON.
  Future<void> create(
    String key,
    RedisValueKind kind,
    String valueText, {
    int? ttl,
  }) async {
    if (key.isEmpty) {
      throw const DbQueryException('query_failed', 'Key must not be empty.');
    }
    final build = kind == RedisValueKind.string
        ? ['SET', key, valueText]
        : _buildCommand(key, kind, valueText);
    final exists = await _batch([
      ['EXISTS', key],
    ]);
    if ('${exists.first}' == '1') {
      throw DbQueryException('query_failed', 'Key "$key" already exists.');
    }
    await _batch([
      build,
      if (ttl != null && ttl > 0) ['EXPIRE', key, '$ttl'],
    ]);
  }

  // ── comandos por tipo ──────────────────────────────────────────────────────

  static List<String>? _previewCommand(String key, RedisValueKind kind) =>
      switch (kind) {
        RedisValueKind.string => ['GETRANGE', key, '0', '$_previewChars'],
        RedisValueKind.hash => ['HGETALL', key],
        RedisValueKind.list => ['LRANGE', key, '0', '${_previewElems - 1}'],
        RedisValueKind.set => ['SMEMBERS', key],
        RedisValueKind.zset => [
          'ZRANGE',
          key,
          '0',
          '${_previewElems - 1}',
          'WITHSCORES',
        ],
        RedisValueKind.other => null,
      };

  static List<String> _fullCommand(String key, RedisValueKind kind) =>
      switch (kind) {
        RedisValueKind.string => ['GET', key],
        RedisValueKind.hash => ['HGETALL', key],
        RedisValueKind.list => ['LRANGE', key, '0', '-1'],
        RedisValueKind.set => ['SMEMBERS', key],
        RedisValueKind.zset => ['ZRANGE', key, '0', '-1', 'WITHSCORES'],
        RedisValueKind.other => throw const DbQueryException(
          'query_failed',
          'This value type is read-only in the table.',
        ),
      };

  /// Normaliza o reply do tipo pra estrutura JSON canônica do editor:
  /// hash → objeto; list/set → array; zset → array de `{value, score}`.
  static Object _decode(RedisValueKind kind, Object? reply) {
    switch (kind) {
      case RedisValueKind.hash:
        if (reply is Map) {
          return {for (final e in reply.entries) '${e.key}': '${e.value}'};
        }
        // Reply plano [f1, v1, f2, v2, …].
        final flat = reply is List ? reply : const [];
        return {
          for (var i = 0; i + 1 < flat.length; i += 2)
            '${flat[i]}': '${flat[i + 1]}',
        };
      case RedisValueKind.zset:
        final flat = reply is List ? reply : const [];
        // WITHSCORES: plano [m1, s1, …] ou pares aninhados [[m1, s1], …].
        if (flat.isNotEmpty && flat.first is List) {
          return [
            for (final pair in flat.cast<List>())
              {'value': '${pair.first}', 'score': '${pair.last}'},
          ];
        }
        return [
          for (var i = 0; i + 1 < flat.length; i += 2)
            {'value': '${flat[i]}', 'score': '${flat[i + 1]}'},
        ];
      case RedisValueKind.list || RedisValueKind.set:
        return [for (final v in (reply is List ? reply : const [])) '$v'];
      case RedisValueKind.string || RedisValueKind.other:
        return '${reply ?? ''}';
    }
  }

  static String _formatPreview(RedisValueKind kind, Object? reply) {
    if (kind == RedisValueKind.string) return '${reply ?? ''}';
    return jsonEncode(_decode(kind, reply));
  }

  /// Comando que recria o valor composto a partir do JSON do editor. Valida a
  /// forma toda antes de devolver (nada parcial chega ao servidor).
  static List<String> _buildCommand(
    String key,
    RedisValueKind kind,
    String jsonText,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw DbQueryException('query_failed', 'Invalid JSON: ${e.message}');
    }
    String str(Object? v) => v is String ? v : jsonEncode(v);
    switch (kind) {
      case RedisValueKind.hash:
        if (decoded is! Map || decoded.isEmpty) {
          throw const DbQueryException(
            'query_failed',
            'A hash is a non-empty JSON object: {"field": "value"}.',
          );
        }
        return [
          'HSET',
          key,
          for (final e in decoded.entries) ...['${e.key}', str(e.value)],
        ];
      case RedisValueKind.list || RedisValueKind.set:
        if (decoded is! List || decoded.isEmpty) {
          throw DbQueryException(
            'query_failed',
            'A ${kind.label.toLowerCase()} is a non-empty JSON array.',
          );
        }
        return [
          kind == RedisValueKind.list ? 'RPUSH' : 'SADD',
          key,
          for (final v in decoded) str(v),
        ];
      case RedisValueKind.zset:
        if (decoded is! List || decoded.isEmpty) {
          throw const DbQueryException(
            'query_failed',
            'A zset is a non-empty JSON array of {"value": …, "score": …}.',
          );
        }
        final parts = <String>['ZADD', key];
        for (final item in decoded) {
          if (item is! Map || !item.containsKey('value')) {
            throw const DbQueryException(
              'query_failed',
              'Each zset item needs "value" and "score".',
            );
          }
          final score = num.tryParse('${item['score'] ?? ''}');
          if (score == null) {
            throw DbQueryException(
              'query_failed',
              'Invalid score for "${item['value']}".',
            );
          }
          parts
            ..add('$score')
            ..add(str(item['value']));
        }
        return parts;
      case RedisValueKind.string || RedisValueKind.other:
        throw const DbQueryException(
          'query_failed',
          'Not a composite value type.',
        );
    }
  }
}
