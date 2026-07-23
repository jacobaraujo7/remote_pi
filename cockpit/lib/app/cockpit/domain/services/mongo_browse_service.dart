import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/db_result.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';

/// Operações do collection browser Mongo (plano 53) sobre o
/// [DbQueryService.mongoCommand] — mesmos `runCommand` que um agente mandaria
/// via `cockpit mongo` (decisão F: paridade agent-first por construção).
///
/// Documentos trafegam como **relaxed extended JSON** puro (`{"$oid":…}`,
/// `{"$date":…}`) — o runner roda com `extendedJsonCodec: false` (decisão C),
/// então editar e salvar de volta preserva os tipos BSON.
class MongoBrowseService {
  MongoBrowseService(this._db);

  final DbQueryService _db;

  /// Documentos por página do `find`.
  static const pageSize = 50;

  ({String root, String id, String conn})? _target;

  /// Aponta o serviço pra conexão da tab. Chamado pelo widget no mount/update.
  void target({
    required String workspaceRoot,
    required String workspaceId,
    required String connName,
  }) => _target = (root: workspaceRoot, id: workspaceId, conn: connName);

  Future<Map<String, dynamic>> _run(Map<String, dynamic> command) async {
    final t = _target;
    if (t == null) {
      throw const DbQueryException('query_failed', 'No connection targeted.');
    }
    final reply = await _db.mongoCommand(
      workspaceRoot: t.root,
      workspaceId: t.id,
      connName: t.conn,
      command: command,
    );
    if (reply is! Map) {
      throw DbQueryException('query_failed', 'Unexpected reply: $reply');
    }
    final doc = Map<String, dynamic>.from(reply);
    _checkOk(doc);
    return doc;
  }

  /// Falha de comando/write vira [DbQueryException] com a mensagem do servidor.
  static void _checkOk(Map<String, dynamic> doc) {
    final ok = doc['ok'];
    if (ok is num && ok != 1) {
      throw DbQueryException(
        'query_failed',
        '${doc['errmsg'] ?? doc['codeName'] ?? 'Command failed.'}',
      );
    }
    final writeErrors = doc['writeErrors'];
    if (writeErrors is List && writeErrors.isNotEmpty) {
      final first = writeErrors.first;
      throw DbQueryException(
        'query_failed',
        first is Map ? '${first['errmsg'] ?? first}' : '$first',
      );
    }
  }

  /// Nomes das collections do database da conexão, ordenados.
  Future<List<String>> listCollections() async {
    final reply = await _run({'listCollections': 1, 'nameOnly': true});
    final batch = _cursorBatch(reply);
    final names = [
      for (final c in batch)
        if (c is Map && c['name'] is String) c['name'] as String,
    ]..sort();
    return names;
  }

  /// Uma página de documentos. [filterJson] vazio = `{}`; JSON inválido lança
  /// **antes** de tocar o servidor.
  Future<List<Map<String, dynamic>>> find(
    String collection, {
    String filterJson = '',
    int skip = 0,
    int limit = pageSize,
  }) async {
    final reply = await _run({
      'find': collection,
      'filter': parseFilter(filterJson),
      if (skip > 0) 'skip': skip,
      'limit': limit,
      'batchSize': limit,
      // singleBatch: o browser pagina por skip/limit — nunca deixa cursor
      // aberto no servidor.
      'singleBatch': true,
    });
    return [
      for (final d in _cursorBatch(reply))
        if (d is Map) Map<String, dynamic>.from(d),
    ];
  }

  /// Substitui o documento inteiro, ancorado no `_id` que veio DENTRO do
  /// próprio JSON editado — documento sem `_id` é recusado (não há âncora).
  Future<void> replaceOne(String collection, String docJson) async {
    final doc = parseDocument(docJson);
    final id = doc['_id'];
    if (id == null) {
      throw const DbQueryException(
        'query_failed',
        'The document must keep its "_id" field.',
      );
    }
    final reply = await _run({
      'update': collection,
      'updates': [
        {
          'q': {'_id': id},
          'u': doc,
        },
      ],
    });
    if (reply['n'] is num && reply['n'] == 0) {
      throw const DbQueryException(
        'query_failed',
        'No document matched this "_id" (was it deleted?).',
      );
    }
  }

  /// Insere um documento (o servidor gera `_id` se o JSON não trouxer um).
  Future<void> insertOne(String collection, String docJson) async {
    await _run({
      'insert': collection,
      'documents': [parseDocument(docJson)],
    });
  }

  /// Deleta o documento de [id] (valor extended JSON cru, ex. `{"$oid": …}`).
  Future<void> deleteOne(String collection, Object? id) async {
    await _run({
      'delete': collection,
      'deletes': [
        {
          'q': {'_id': id},
          'limit': 1,
        },
      ],
    });
  }

  static List _cursorBatch(Map<String, dynamic> reply) {
    final cursor = reply['cursor'];
    final batch = cursor is Map
        ? (cursor['firstBatch'] ?? cursor['nextBatch'])
        : null;
    return batch is List ? batch : const [];
  }

  /// Filter bar → mapa. Vazio/`{}` = sem filtro. Erros viram
  /// [DbQueryException] `query_failed` com mensagem apontando o problema.
  static Map<String, dynamic> parseFilter(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const {};
    final decoded = _parseJson(trimmed, what: 'filter');
    if (decoded is! Map) {
      throw const DbQueryException(
        'query_failed',
        'The filter must be a JSON object, e.g. {"status": "active"}.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Editor de documento → mapa (objeto JSON obrigatório).
  static Map<String, dynamic> parseDocument(String text) {
    final decoded = _parseJson(text.trim(), what: 'document');
    if (decoded is! Map) {
      throw const DbQueryException(
        'query_failed',
        'A document must be a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Object? _parseJson(String text, {required String what}) {
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw DbQueryException(
        'query_failed',
        'Invalid $what JSON: ${e.message}',
      );
    }
  }
}
