import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:flutter/foundation.dart';

/// Etapa do dialog de revoke (dirige o que ele mostra).
enum RevokeStage { running, done, failed }

/// Estado do dialog de revoke. Sobe um `pi --mode rpc` efêmero (via a
/// [RevokeGateway]) e manda `/remote-pi revoke <shortId>`. One-shot: roda no
/// [run] e reporta done/failed.
class RevokeController extends ChangeNotifier {
  RevokeController(this._gateway);

  final RevokeGateway _gateway;

  RevokeStage stage = RevokeStage.running;
  String? error;
  String? deviceName;

  bool _disposed = false;

  Future<void> run(PairedDevice device) async {
    deviceName = device.label.isEmpty ? device.shortId : device.label;
    stage = RevokeStage.running;
    error = null;
    _notify();

    final result = await _gateway.revoke(device.shortId);
    result.fold((_) => stage = RevokeStage.done, (e) {
      error = e.message;
      stage = RevokeStage.failed;
    });
    _notify();
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
