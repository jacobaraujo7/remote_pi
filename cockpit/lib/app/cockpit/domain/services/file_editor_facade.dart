import 'package:cockpit/app/core/domain/entities/app_settings.dart';

/// Contexto completo de uma abertura, independente da superfície que vai
/// hospedar o editor (pane hoje, janela no futuro).
class FileOpenRequest {
  const FileOpenRequest({
    required this.path,
    required this.projectId,
    required this.paneId,
    required this.isRemote,
    this.isPreview = true,
    this.revealLine,
    this.asSource = false,
    this.isNotebook = false,
    this.focusPane = false,
  });

  final String path;
  final String projectId;
  final String paneId;
  final bool isRemote;
  final bool isPreview;
  final int? revealLine;
  final bool asSource;
  final bool isNotebook;
  final bool focusPane;
}

enum FileOpenOutcome { opened, notHandled }

class FileOpenResult {
  const FileOpenResult(this.engine, this.outcome);

  final FileEditorEngine engine;
  final FileOpenOutcome outcome;
}

typedef FileEngineOpener =
    Future<FileOpenOutcome> Function(FileOpenRequest request);

/// Registro extensível dos motores disponíveis nesta superfície.
class FileEditorRegistry {
  FileEditorRegistry(Map<FileEditorEngine, FileEngineOpener> engines)
    : _engines = Map.unmodifiable(engines);

  final Map<FileEditorEngine, FileEngineOpener> _engines;

  Future<FileOpenOutcome> open(
    FileEditorEngine engine,
    FileOpenRequest request,
  ) =>
      _engines[engine]?.call(request) ??
      Future<FileOpenOutcome>.value(FileOpenOutcome.notHandled);
}

/// Orquestra classificação, escolha do motor e fallback. Não conhece árvore,
/// tabs ou sessões: essas mutações pertencem ao host registrado.
class FileEditorFacade {
  FileEditorFacade(this._registry);

  final FileEditorRegistry _registry;
  FileEditorEngine engine = FileEditorEngine.cockpit;

  static const Set<String> _cockpitExtensions = {
    // Experiências especializadas.
    'http', 'dbq', 'kanban',
    // Mídia e SVG.
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg',
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv',
    'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'opus',
  };

  FileEditorEngine engineFor(FileOpenRequest request) {
    if (request.isRemote || request.isNotebook) {
      return FileEditorEngine.cockpit;
    }
    if (!request.asSource &&
        _cockpitExtensions.contains(_extension(request.path))) {
      return FileEditorEngine.cockpit;
    }
    return engine;
  }

  Future<FileOpenResult> open(FileOpenRequest request) async {
    final selected = engineFor(request);
    final outcome = await _registry.open(selected, request);
    if (outcome == FileOpenOutcome.opened ||
        selected == FileEditorEngine.cockpit) {
      return FileOpenResult(selected, outcome);
    }
    return FileOpenResult(
      FileEditorEngine.cockpit,
      await _registry.open(FileEditorEngine.cockpit, request),
    );
  }

  static String _extension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}
