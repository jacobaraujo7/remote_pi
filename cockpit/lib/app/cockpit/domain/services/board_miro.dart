import 'dart:convert';
import 'dart:io';
import '../entities/board_document.dart';

/// Uses a user-authorized token only for the fixed Miro API origin.
class BoardMiro {
  BoardMiro(this.token, String board)
    : base = Uri.https(
        'api.miro.com',
        '/v2/boards/${Uri.encodeComponent(board.trim())}',
      ) {
    if (token.trim().isEmpty || board.trim().isEmpty) {
      throw const FormatException('Miro board ID and access token required');
    }
  }
  final HttpClient client = HttpClient();
  final Uri base;
  final String token;
  Future<Map<String, dynamic>> request(
    String method,
    String resource, {
    Map<String, String>? query,
    Map<String, dynamic>? data,
  }) async {
    final uri = base.replace(
      path: '${base.path}/$resource',
      queryParameters: query,
    );
    final req = await client.openUrl(method, uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (data != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(data));
    }
    final response = await req.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Miro HTTP ${response.statusCode}', uri: uri);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> list(String resource) async {
    final items = <dynamic>[], seen = <String>{};
    String? cursor;
    do {
      final page = await request(
        'GET',
        resource,
        query: {'limit': '50', 'cursor': ?cursor},
      );
      items.addAll(page['data'] as List);
      cursor = page['cursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('Invalid Miro pagination');
      }
    } while (cursor != null && cursor.isNotEmpty);
    return items;
  }

  Future<({BoardDocument board, Set<String> skipped})> read() async {
    final nodes = <String, BoardItem>{}, skipped = <String>{};
    for (final e in await list('items')) {
      final type = e['type'] as String;
      final kind = switch (type) {
        'shape' =>
          e['data']?['shape'] == 'rhombus'
              ? BoardKind.decision
              : BoardKind.process,
        'sticky_note' => BoardKind.note,
        'text' => BoardKind.text,
        'frame' => BoardKind.container,
        _ => null,
      };
      if (kind == null) {
        if (type != 'connector') skipped.add(type);
        continue;
      }
      final width = (e['geometry']?['width'] as num? ?? 136).toDouble(),
          height = (e['geometry']?['height'] as num? ?? 64).toDouble();
      final id = e['id'] as String;
      final text = (e['data']?['content'] ?? e['data']?['title'] ?? '')
          .toString()
          .replaceAll(RegExp('<[^>]*>'), '')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');
      nodes[id] = BoardItem(
        id,
        kind,
        (e['position']?['x'] as num? ?? 0) - width / 2,
        (e['position']?['y'] as num? ?? 0) - height / 2,
        width: width,
        height: height,
        label: text,
      );
    }
    for (final e in await list('connectors')) {
      final a = e['startItem']?['id'], b = e['endItem']?['id'];
      if (!nodes.containsKey(a) || !nodes.containsKey(b)) {
        skipped.add('connector');
        continue;
      }
      final id = e['id'] as String;
      nodes[id] = BoardItem(
        id,
        BoardKind.arrow,
        0,
        0,
        from: a,
        to: b,
        label:
            (e['captions'] as List?)?.firstOrNull?['content'] as String? ?? '',
      );
    }
    return (board: BoardDocument(nodes.values), skipped: skipped);
  }

  Future<void> publish(BoardDocument doc) async {
    final ids = <String, String>{};
    try {
      for (final i in doc.items.values.where(
        (v) => v.kind != BoardKind.arrow,
      )) {
        if (i.kind == BoardKind.stroke || i.kind == BoardKind.mermaid) continue;
        final text = const HtmlEscape().convert(i.label);
        final resource = switch (i.kind) {
          BoardKind.note => 'sticky_notes',
          BoardKind.text => 'texts',
          BoardKind.container || BoardKind.lane => 'frames',
          _ => 'shapes',
        };
        final reply = await request(
          'POST',
          resource,
          data: {
            'data': {
              if (resource == 'frames') 'title': i.label else 'content': text,
              if (resource == 'shapes')
                'shape': i.kind == BoardKind.decision ? 'rhombus' : 'rectangle',
            },
            'position': {'x': i.x + i.width / 2, 'y': i.y + i.height / 2},
            'geometry': {
              'width': i.width,
              if (resource == 'shapes' || resource == 'frames')
                'height': i.height,
            },
          },
        );
        ids[i.id] = reply['id'] as String;
      }
      for (final i in doc.items.values.where(
        (v) => v.kind == BoardKind.arrow,
      )) {
        if (!ids.containsKey(i.from) || !ids.containsKey(i.to)) continue;
        final result = await request(
          'POST',
          'connectors',
          data: {
            'startItem': {'id': ids[i.from]},
            'endItem': {'id': ids[i.to]},
            'shape': 'elbowed',
            if (i.label.isNotEmpty)
              'captions': [
                {'content': const HtmlEscape().convert(i.label)},
              ],
          },
        );
        ids[i.id] = result['id'] as String;
      }
    } catch (e) {
      throw StateError(
        'Miro: ${ids.length} items published before failure. $e',
      );
    }
  }

  void close() => client.close(force: true);
}
