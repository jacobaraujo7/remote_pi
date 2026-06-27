import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:flutter/foundation.dart';

/// Estado da permissão de notificações do SO para a aba **Notifications**.
/// Page-scoped: injeta o [SystemPermissions] (core) e expõe o status atual +
/// ações de re-checagem/solicitação. O toggle de liga/desliga vive no
/// `SettingsController` (persistido); aqui cuidamos só da permissão do SO.
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel(this._perms);

  final SystemPermissions _perms;

  CheckStatus _status = CheckStatus.checking;
  bool _disposed = false;

  CheckStatus get status => _status;

  /// Sonda o estado atual (chamado ao montar a aba e no foco da janela).
  Future<void> check() => _set(_perms.notificationStatus);

  /// Pede a permissão + dispara uma notificação de teste; devolve o resultado.
  Future<CheckStatus> request() async {
    await _set(_perms.requestNotifications);
    return _status;
  }

  Future<void> _set(Future<CheckStatus> Function() probe) async {
    final result = await probe();
    if (_disposed) return;
    _status = result;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
