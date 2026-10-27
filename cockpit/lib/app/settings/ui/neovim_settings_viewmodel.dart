import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:flutter/foundation.dart';

class NeovimSettingsViewModel extends ChangeNotifier {
  NeovimSettingsViewModel(this._gateway);

  final NeovimGateway _gateway;

  bool _disposed = false;
  bool _checking = false;
  bool get checking => _checking;

  String? _executable;
  String? get executable => _executable;
  bool get available => _executable != null;

  Future<void> check({bool refresh = false}) async {
    if (_disposed || _checking) return;
    _checking = true;
    notifyListeners();
    try {
      final executable = await _gateway.executable(refresh: refresh);
      if (!_disposed) _executable = executable;
    } catch (_) {
      if (!_disposed) rethrow;
    } finally {
      _checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
