import 'package:cockpit/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/domain/entities/daemon_info.dart';
import 'package:cockpit/domain/exceptions/daemon_error.dart';
import 'package:cockpit/domain/result.dart';
import 'package:flutter/foundation.dart';

enum DaemonsLoad { idle, loading, ready, error }

/// Estado da aba **Daemon Agents**: lista + controle dos agentes 24/7 sob o
/// supervisor. Carrega sob demanda; cada ação recarrega a lista pra refletir o
/// novo estado. `online == false` → supervisor inacessível (mostra aviso).
class DaemonsViewModel extends ChangeNotifier {
  DaemonsViewModel(this._supervisor);

  final DaemonSupervisor _supervisor;

  DaemonsLoad load = DaemonsLoad.idle;
  bool online = false;
  List<DaemonInfo> daemons = const <DaemonInfo>[];
  String? error; // falha ao listar
  String? actionError; // falha da última ação (start/stop/restart/remove/create)

  final Set<String> _busy = <String>{}; // ids com ação em andamento
  bool busyAll = false; // ação global em andamento

  bool _disposed = false;

  bool isBusy(String id) => _busy.contains(id);
  bool get anyBusy => busyAll || _busy.isNotEmpty;

  /// Checa o supervisor e lista os daemons. Chamado ao abrir a aba.
  Future<void> reload() async {
    load = DaemonsLoad.loading;
    error = null;
    _notify();

    online = await _supervisor.isOnline();
    if (!online) {
      daemons = const <DaemonInfo>[];
      load = DaemonsLoad.ready;
      _notify();
      return;
    }

    final result = await _supervisor.list();
    result.fold(
      (list) {
        daemons = list;
        load = DaemonsLoad.ready;
      },
      (e) {
        error = e.message;
        load = DaemonsLoad.error;
      },
    );
    _notify();
  }

  Future<void> start(String id) => _action(id, () => _supervisor.start(id));
  Future<void> stop(String id) => _action(id, () => _supervisor.stop(id));
  Future<void> restart(String id) => _action(id, () => _supervisor.restart(id));
  Future<void> remove(String id) => _action(id, () => _supervisor.unregister(id));

  Future<void> startAll() => _globalAction(_supervisor.startAll);
  Future<void> stopAll() => _globalAction(_supervisor.stopAll);
  Future<void> restartAll() => _globalAction(_supervisor.restartAll);

  /// Cria/registra um daemon pra [cwd]. Retorna `true` no sucesso.
  Future<bool> create(String cwd, {String? name}) async {
    actionError = null;
    _notify();
    final result = await _supervisor.create(cwd, name: name);
    final ok = result.fold((_) => true, (e) {
      actionError = e.message;
      return false;
    });
    if (ok) await reload();
    return ok;
  }

  Future<void> _action(
    String id,
    Future<Result<void, DaemonError>> Function() op,
  ) async {
    if (_busy.contains(id)) return;
    _busy.add(id);
    actionError = null;
    _notify();
    final result = await op();
    result.fold((_) {}, (e) => actionError = e.message);
    _busy.remove(id);
    _notify();
    await reload();
  }

  Future<void> _globalAction(
    Future<Result<void, DaemonError>> Function() op,
  ) async {
    if (busyAll) return;
    busyAll = true;
    actionError = null;
    _notify();
    final result = await op();
    result.fold((_) {}, (e) => actionError = e.message);
    busyAll = false;
    _notify();
    await reload();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
