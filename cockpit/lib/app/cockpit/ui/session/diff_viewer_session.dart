import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Uma aba de **diff** read-only (split, estilo VSCode): mostra o arquivo em
/// [path] comparado com o HEAD do git. Sem ações — só visual. O conteúdo
/// ([diff]) já vem parseado pela VM.
class DiffViewerSession extends PaneItem {
  DiffViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.diff,
    this.isPreview = false,
  });

  @override
  final String id;
  @override
  final String projectId;

  /// Caminho absoluto do arquivo comparado. **Mutável** pra reutilizar a aba de
  /// preview (a VM re-lê o diff e reatribui).
  String path;

  /// O diff parseado — **mutável** (preview reuse).
  FileDiff diff;

  @override
  String get title {
    final name = path.split('/').where((p) => p.isNotEmpty).last;
    return '$name (diff)';
  }

  @override
  String get workingDirectory =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : path;

  /// `true` se é aba de preview (sobrescrita ao abrir outro diff; duplo-clique
  /// fixa).
  bool isPreview;

  void pin() {
    if (!isPreview) return;
    isPreview = false;
    notifyListeners();
  }
}
