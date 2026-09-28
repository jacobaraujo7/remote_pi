import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Aba do pane central com o detalhe de UM caso da Telemetry (plano 66).
/// Leve e descartável: não persiste no layout (a base é a fonte de verdade;
/// reabrir pelo painel é um clique).
class TelemetryCaseSession extends PaneItem {
  TelemetryCaseSession({
    required this.id,
    required this.projectId,
    required this.fingerprint,
    required String title,
    required this.workingDirectory,
  }) : _title = title; // ignore: prefer_initializing_formals

  @override
  final String id;
  @override
  final String projectId;

  /// Fingerprint completo (a aba de caso é por fingerprint, não por run).
  final String fingerprint;

  String _title;

  @override
  String get title => _title;

  set title(String v) {
    if (v == _title) return;
    _title = v;
    notifyListeners();
  }

  @override
  final String workingDirectory;
}
