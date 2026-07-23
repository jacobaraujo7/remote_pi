/// Tipos de valor do Redis que a tabela conhece (plano 52). `other` cobre
/// stream/módulos — visíveis mas read-only.
enum RedisValueKind {
  string,
  hash,
  list,
  set,
  zset,
  other;

  /// Label user-facing da coluna "type".
  String get label => switch (this) {
    RedisValueKind.string => 'STRING',
    RedisValueKind.hash => 'HASH',
    RedisValueKind.list => 'LIST',
    RedisValueKind.set => 'SET',
    RedisValueKind.zset => 'ZSET',
    RedisValueKind.other => 'OTHER',
  };

  /// Editável pela tabela? Compostos editam via expansão; `other` não edita.
  bool get editable => this != RedisValueKind.other;

  /// Reply do comando `TYPE` → kind.
  static RedisValueKind fromRaw(String raw) => switch (raw) {
    'string' => RedisValueKind.string,
    'hash' => RedisValueKind.hash,
    'list' => RedisValueKind.list,
    'set' => RedisValueKind.set,
    'zset' => RedisValueKind.zset,
    _ => RedisValueKind.other,
  };
}

/// Uma linha da tabela: chave + tipo + TTL + preview do valor. O [preview] é
/// **só exibição** (pode estar truncado) — edição sempre parte de
/// `RedisBrowseService.readFull` (decisão C do plano 52).
class RedisKeyEntry {
  const RedisKeyEntry({
    required this.key,
    required this.kind,
    required this.ttl,
    required this.preview,
  });

  final String key;
  final RedisValueKind kind;

  /// TTL em segundos; `-1` = sem expiração.
  final int ttl;

  final String preview;

  RedisKeyEntry copyWith({int? ttl, String? preview}) => RedisKeyEntry(
    key: key,
    kind: kind,
    ttl: ttl ?? this.ttl,
    preview: preview ?? this.preview,
  );
}

/// Uma página do SCAN: entradas + cursor pra próxima página (`'0'` = fim).
class RedisScanPage {
  const RedisScanPage({required this.entries, required this.cursor});

  final List<RedisKeyEntry> entries;
  final String cursor;

  bool get done => cursor == '0';
}
