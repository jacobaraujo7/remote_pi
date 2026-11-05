import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:path/path.dart' as p;

enum DiffViewMode { sideBySide, inline, modifiedContent }

/// Uma aba de **diff** read-only: mostra o arquivo em
/// [path] comparado com o HEAD do git. Sem ações — só visual. O conteúdo
/// ([diff]) já vem parseado pela VM.
class DiffViewerSession extends PaneItem {
  DiffViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.diff,
    this.commitHash,
    this.repoRoot,
    this.previousRelativePath,
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

  /// `null` para mudancas no working tree; hash para um diff historico.
  String? commitHash;

  /// Raiz da worktree do diff historico - necessaria para restaura-lo fielmente.
  String? repoRoot;

  /// Caminho anterior de um rename/copy, relativo a [repoRoot].
  String? previousRelativePath;

  // `package:path`, não corte no `/`: no Windows o path pode vir com `\`.
  @override
  String get title => '${p.basename(path)} (diff)';

  @override
  String get workingDirectory => p.dirname(path);

  /// `true` se é aba de preview (sobrescrita ao abrir outro diff; duplo-clique
  /// fixa).
  bool isPreview;

  DiffViewMode viewMode = DiffViewMode.sideBySide;
  String? modifiedContent;
  String? modifiedContentError;
  bool loadingModifiedContent = false;

  void setViewMode(DiffViewMode mode) {
    if (viewMode == mode) return;
    viewMode = mode;
    notifyListeners();
  }

  void replaceDiff(FileDiff nextDiff, String nextPath) {
    path = nextPath;
    diff = nextDiff;
    modifiedContent = null;
    modifiedContentError = null;
    loadingModifiedContent = false;
    notifyListeners();
  }

  void startModifiedContentLoad() {
    loadingModifiedContent = true;
    modifiedContentError = null;
    notifyListeners();
  }

  void completeModifiedContentLoad(FileDiff expectedDiff, String content) {
    if (!identical(diff, expectedDiff)) return;
    modifiedContent = content;
    loadingModifiedContent = false;
    notifyListeners();
  }

  void failModifiedContentLoad(FileDiff expectedDiff, Object error) {
    if (!identical(diff, expectedDiff)) return;
    modifiedContentError = error.toString();
    loadingModifiedContent = false;
    notifyListeners();
  }

  void pin() {
    if (!isPreview) return;
    isPreview = false;
    notifyListeners();
  }
}
