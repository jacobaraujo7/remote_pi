// Proxy HTTP local (plano 66, passo 10): o front aponta pra porta do proxy, o
// proxy repassa pro backend e grava request/response como eventos
// `stream: proxy` (corpos redigidos e com teto). Injeta `x-request-id` e
// `traceparent` quando o cliente não manda, então o log do backend correlaciona
// sem SDK. Também replay: reenvia os requests de uma janela (marca).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import '../../domain/entities/telemetry_event.dart';
import 'fingerprint.dart';
import 'redaction.dart';
import 'telemetry_workspace_config.dart';

class HttpTelemetryProxy {
  HttpTelemetryProxy({
    required this.config,
    required this.runId,
    required this.sink,
  });

  final TelemetryProxyConfig config;
  final String runId;
  final void Function(List<TelemetryEvent> events) sink;
  final _client = HttpClient()..autoUncompress = false;
  HttpServer? _server;
  final _rnd = Random.secure();

  static const _bodyCap = 64 * 1024;
  static const _hopHeaders = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'host',
    'content-length',
  };

  bool get isRunning => _server != null;

  Future<bool> start() async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        config.listen,
      );
    } on SocketException {
      return false; // porta ocupada: o painel/CLI mostram sem proxy
    }
    unawaited(_serve());
    return true;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final req in server) {
      unawaited(_handle(req));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final started = DateTime.now();
    final sw = Stopwatch()..start();
    final reqId = req.headers.value('x-request-id') ?? _hex(8);
    var traceparent = req.headers.value('traceparent');
    final traceId = traceparent?.split('-').elementAtOrNull(1) ?? _hex(16);
    traceparent ??= '00-$traceId-${_hex(8)}-01';

    final reqBytes = await _collect(req);
    final target = config.upstream.replace(
      path: req.uri.path,
      query: req.uri.hasQuery ? req.uri.query : null,
    );
    int status;
    List<int> resBytes = const [];
    String? resType;
    String? failure;
    try {
      final up = await _client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        if (_hopHeaders.contains(name.toLowerCase())) return;
        for (final v in values) {
          up.headers.add(name, v);
        }
      });
      up.headers.set('x-request-id', reqId);
      up.headers.set('traceparent', traceparent);
      up.contentLength = reqBytes.length;
      up.add(reqBytes);
      final res = await up.close().timeout(const Duration(seconds: 120));
      status = res.statusCode;
      resType = res.headers.contentType?.mimeType;
      req.response.statusCode = status;
      res.headers.forEach((name, values) {
        if (_hopHeaders.contains(name.toLowerCase())) return;
        req.response.headers.set(name, values.join(', '));
      });
      req.response.headers.set('x-request-id', reqId);
      final buf = BytesBuilder(copy: false);
      await for (final chunk in res) {
        req.response.add(chunk);
        if (buf.length < _bodyCap) buf.add(chunk);
      }
      resBytes = buf.takeBytes();
    } on Object catch (e) {
      status = HttpStatus.badGateway;
      failure = e.toString();
      req.response.statusCode = status;
      req.response.write('cockpit telemetry proxy: upstream unreachable');
    }
    try {
      await req.response.close();
    } on Object {
      // cliente desistiu
    }
    sw.stop();
    _record(
      started: started,
      method: req.method,
      path: req.uri.toString(),
      status: status,
      ms: sw.elapsedMilliseconds,
      reqId: reqId,
      traceId: traceId,
      reqType: req.headers.contentType?.mimeType,
      reqBody: reqBytes,
      resType: resType,
      resBody: resBytes,
      failure: failure,
    );
  }

  void _record({
    required DateTime started,
    required String method,
    required String path,
    required int status,
    required int ms,
    required String reqId,
    required String traceId,
    required String? reqType,
    required List<int> reqBody,
    required String? resType,
    required List<int> resBody,
    required String? failure,
  }) {
    final route = path.split('?').first;
    TelemetryError? err;
    if (failure != null) {
      err = TelemetryError(
        type: 'UpstreamUnreachable',
        message: '$method $route',
      );
    } else if (status >= 500) {
      err = TelemetryError(type: 'HTTP $status', message: '$method $route');
    }
    final sev = err != null
        ? TelemetrySeverity.error
        : (status >= 400 ? TelemetrySeverity.warn : TelemetrySeverity.debug);
    sink([
      TelemetryEvent(
        runId: runId,
        ts: started,
        stream: TelemetryStream.proxy,
        severity: sev,
        body: '$method $route $status ${ms}ms',
        attrs: {
          'method': method,
          'route': route,
          'path': path,
          'status': status,
          'duration_ms': ms,
          'request_id': reqId,
          'req_type': ?reqType,
          if (reqBody.isNotEmpty && _isText(reqType))
            'req_body': redactText(_text(reqBody)),
          'res_type': ?resType,
          if (resBody.isNotEmpty && _isText(resType))
            'res_body': redactText(_text(resBody)),
          'failure': ?failure,
        },
        error: err,
        fingerprint: err == null ? null : fingerprintOf(err),
        traceId: traceId,
        requestId: reqId,
      ),
    ]);
  }

  /// Reenvia requests gravados (eventos `proxy`) pro upstream. Devolve
  /// quantos foram enviados. Só método/rota/corpo; headers de auth não são
  /// guardados (redação), então rotas autenticadas voltam 401 de propósito.
  Future<int> replay(List<TelemetryEvent> events) async {
    var n = 0;
    for (final e in events) {
      if (e.stream != TelemetryStream.proxy) continue;
      final method = e.attrs['method']?.toString();
      final path = e.attrs['path']?.toString() ?? e.attrs['route']?.toString();
      if (method == null || path == null) continue;
      try {
        final uri = Uri.parse(path);
        final target = config.upstream.replace(
          path: uri.path,
          query: uri.hasQuery ? uri.query : null,
        );
        final up = await _client.openUrl(method, target);
        up.headers.set('x-request-id', '${e.requestId ?? _hex(8)}-replay');
        final type = e.attrs['req_type']?.toString();
        final body = e.attrs['req_body']?.toString();
        if (body != null && body.isNotEmpty && !body.contains(redacted)) {
          if (type != null) up.headers.contentType = ContentType.parse(type);
          up.write(body);
        }
        final res = await up.close().timeout(const Duration(seconds: 60));
        await res.drain<void>();
        n++;
      } on Object {
        // upstream fora: conta como não enviado
      }
    }
    return n;
  }

  Future<List<int>> _collect(HttpRequest req) async {
    final buf = BytesBuilder(copy: false);
    await for (final chunk in req) {
      buf.add(chunk);
    }
    return buf.takeBytes();
  }

  static bool _isText(String? mime) =>
      mime != null &&
      (mime.startsWith('text/') ||
          mime.contains('json') ||
          mime.contains('xml') ||
          mime.contains('x-www-form-urlencoded'));

  static String _text(List<int> bytes) => utf8.decode(
    bytes.length > _bodyCap ? bytes.sublist(0, _bodyCap) : bytes,
    allowMalformed: true,
  );

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
