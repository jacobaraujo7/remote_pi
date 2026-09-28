// Um `TelemetryStore` por workspace (plano 66, decisão 5), no cache local do
// Cockpit — nunca dentro do repo, e não segue o override de storage (é
// cache, como o scrollback).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/contracts/telemetry_store.dart';
import 'sqlite_telemetry_store.dart';

/// Abre uma base pro [workspaceId] (o registry cacheia as abertas).
typedef TelemetryStoreOpener =
    Future<TelemetryStore> Function(String workspaceId);

class TelemetryStoreRegistry implements TelemetryStoreProvider {
  TelemetryStoreRegistry({TelemetryStoreOpener? opener})
    : _opener = opener ?? _openOnDisk;

  final TelemetryStoreOpener _opener;
  final _stores = <String, Future<TelemetryStore>>{};

  /// Diretório das bases: `<applicationSupport>/telemetry/`.
  static Future<String> directory() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'telemetry');
  }

  static Future<TelemetryStore> _openOnDisk(String workspaceId) async {
    final dir = Directory(await directory());
    await dir.create(recursive: true);
    // Id de workspace é UUID; sanitiza mesmo assim (ids legados/forks).
    final safe = workspaceId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return SqliteTelemetryStore.open(p.join(dir.path, '$safe.sqlite'));
  }

  @override
  Future<TelemetryStore> forWorkspace(String workspaceId) =>
      _stores.putIfAbsent(workspaceId, () => _opener(workspaceId));

  /// Bases já abertas nesta sessão (pra vacuum/fechamento).
  Iterable<String> get openIds => _stores.keys;

  Future<void> closeAll() async {
    final all = _stores.values.toList();
    _stores.clear();
    for (final f in all) {
      await (await f).close();
    }
  }
}
