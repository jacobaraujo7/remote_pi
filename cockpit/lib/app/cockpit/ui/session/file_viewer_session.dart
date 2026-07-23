import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Uma aba de viewer read-only de arquivo (texto/markdown/imagem). O conteúdo
/// ([view]) já vem classificado/lido pela VM (binário/vídeo nem chega aqui).
class FileViewerSession extends PaneItem {
  FileViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.view,
    this.isPreview = false,
    this.scratch = false,
    this.scratchTitle,
  });

  /// `true` = buffer **untitled** (VSCode-style): não há arquivo no disco até
  /// o primeiro save. O `path` é sintético; [title] usa [scratchTitle]. Vira
  /// `false` no save (a VM faz o retarget pro path real).
  bool scratch;

  /// Título exibido enquanto [scratch] (ex.: `Untitled-1.dbq`).
  String? scratchTitle;

  @override
  final String id;
  @override
  final String projectId;

  /// Caminho absoluto. **Mutável** via [retarget] — segue o arquivo quando ele é
  /// renomeado/movido no disco (a VM re-lê o conteúdo e re-arma o watcher).
  String path;

  // Título e cwd derivam do path → seguem o rename automaticamente.
  @override
  String get title => scratch
      ? (scratchTitle ?? 'Untitled')
      : path.split('/').where((p) => p.isNotEmpty).last;
  @override
  String get workingDirectory =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : path;

  /// Aponta a aba para [newPath] (rename/move). A VM cuida de re-ler o conteúdo
  /// e re-observar o disco; aqui só trocamos o caminho e avisamos a UI.
  void retarget(String newPath) {
    if (newPath == path) return;
    path = newPath;
    notifyListeners();
  }

  /// Conteúdo atual. **Mutável**: a VM reatribui ao detectar mudança no disco
  /// (file watcher — plan/42 follow-up), e o `notifyListeners` reconstrói a aba.
  FileView view;

  /// `true` quando o editor tem alterações não gravadas. Dirige o indicador da
  /// aba (bolinha no lugar do X) e o dialog de "fechar sem salvar". O `FileViewer`
  /// atualiza via [setDirty]; a aba escuta esta sessão (ChangeNotifier).
  bool dirty = false;

  void setDirty(bool value) {
    if (value == dirty) return;
    dirty = value;
    if (value && isPreview) {
      isPreview = false;
    }
    notifyListeners();
  }

  /// Grava o buffer atual do editor em disco. Registrado pelo `FileViewer`
  /// enquanto montado (e limpo ao desmontar); `null` quando não há editor ativo.
  /// Usado pelo "Salvar e fechar". Retorna `true` no sucesso.
  Future<bool> Function()? saveDraft;

  /// `true` se esta é uma aba de preview (VSCode-style). Preview é sobrescrito
  /// ao clicar em outro arquivo; duplo-clique transforma em aba normal.
  bool isPreview;

  /// Transforma esta aba de preview em aba normal.
  void pin() {
    if (!isPreview) return;
    isPreview = false;
    notifyListeners();
  }

  /// Linha (base 1) a revelar no viewer — rolar até ela e destacá-la. `null`
  /// quando não há pedido pendente. Setado por [reveal] (resultado de busca).
  int? revealLine;

  /// Sobe a cada [reveal] — permite re-revelar a **mesma** linha (o viewer
  /// compara o tick pra disparar de novo mesmo sem mudança de [revealLine]).
  int revealTick = 0;

  /// Pede ao viewer pra revelar [line] (base 1): rola até ela e a destaca.
  void reveal(int line) {
    revealLine = line;
    revealTick++;
    notifyListeners();
  }
}
