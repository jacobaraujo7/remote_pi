import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Aba da **tabela Redis** (plano 52): browse/edição das chaves de uma conexão
/// registrada. Sem arquivo — o "documento" é a conexão (decisão A); o estado
/// de view (página, pattern) vive no side-car do `DatabaseViewModel`, que
/// sobrevive ao re-mount quando a tab muda de pane.
class RedisBrowserSession extends PaneItem {
  RedisBrowserSession({
    required this.id,
    required this.projectId,
    required this.connName,
    required this.workingDirectory,
  });

  @override
  final String id;
  @override
  final String projectId;

  /// Nome da conexão Redis no registro do workspace.
  final String connName;

  @override
  final String workingDirectory;

  @override
  String get title => connName;

  /// Pattern semeado de fora (CLI `cockpit redis browse --pattern`, plano 53
  /// decisão E): cai no campo de busca visível — o widget montado escuta a
  /// sessão e aplica; no mount, o initState consome o valor pendente.
  String? seedPattern;

  void requestPattern(String pattern) {
    seedPattern = pattern;
    notifyListeners();
  }

  /// Consome o seed pendente (uma vez).
  String? takeSeedPattern() {
    final p = seedPattern;
    seedPattern = null;
    return p;
  }
}
