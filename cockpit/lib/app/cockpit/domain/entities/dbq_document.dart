/// Um arquivo `.dbq`: frontmatter em comentários SQL + corpo SQL puro.
///
/// ```sql
/// -- db: dev-local
/// -- limit: 100
/// SELECT * FROM orders;
/// ```
///
/// O frontmatter é a **persistência** da tab (conexão escolhida no popup,
/// limite) — o editor mostra só o [sql]. O parse é conservador: consome apenas
/// o bloco inicial de linhas `-- <chave-conhecida>: <valor>`; a primeira linha
/// que não casar (inclusive comentário comum) já é corpo. Round-trip estável:
/// `parse(serialize(d)) == d`.
class DbqDocument {
  const DbqDocument({this.db, this.limit, required this.sql});

  /// Nome da conexão registrada (`-- db: <nome>`); null = tab pede picker.
  final String? db;

  /// Override de `-- limit: <N>`; null = default da execução.
  final int? limit;

  /// Corpo SQL, sem o frontmatter.
  final String sql;

  static final _keyLine = RegExp(r'^--\s*([a-z][a-z0-9-]*)\s*:\s*(.*?)\s*$');
  static const _knownKeys = {'db', 'limit'};

  static DbqDocument parse(String content) {
    final lines = content.split('\n');
    String? db;
    int? limit;
    var bodyStart = 0;
    for (final line in lines) {
      final m = _keyLine.firstMatch(line);
      if (m == null || !_knownKeys.contains(m.group(1))) break;
      switch (m.group(1)) {
        case 'db':
          db = m.group(2)!.isEmpty ? null : m.group(2);
        case 'limit':
          limit = int.tryParse(m.group(2)!);
      }
      bodyStart++;
    }
    // Uma linha em branco separando frontmatter do corpo é cosmética — não
    // pertence ao SQL.
    if (bodyStart > 0 && bodyStart < lines.length && lines[bodyStart].isEmpty) {
      bodyStart++;
    }
    return DbqDocument(
      db: db,
      limit: limit,
      sql: lines.sublist(bodyStart).join('\n'),
    );
  }

  /// Reconstrói o conteúdo do arquivo (frontmatter + linha em branco + SQL).
  String serialize() {
    final head = StringBuffer();
    if (db != null) head.writeln('-- db: $db');
    if (limit != null) head.writeln('-- limit: $limit');
    if (head.isEmpty) return sql;
    return '$head\n$sql';
  }

  DbqDocument copyWith({String? db, int? limit, String? sql}) => DbqDocument(
    db: db ?? this.db,
    limit: limit ?? this.limit,
    sql: sql ?? this.sql,
  );

  @override
  bool operator ==(Object other) =>
      other is DbqDocument &&
      other.db == db &&
      other.limit == limit &&
      other.sql == sql;

  @override
  int get hashCode => Object.hash(db, limit, sql);
}
