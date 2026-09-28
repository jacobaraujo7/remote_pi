import 'dart:io' show FileSystemEntity, FileSystemEntityType;

import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/core/domain/exceptions/file_operation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:flutter/foundation.dart';

/// Mutação de arquivos pela árvore (criar, renomear, mover, deletar) e o
/// clipboard interno (copiar/recortar/colar), extraídos do `CockpitViewModel`.
///
/// Mesmo contrato do [GitController]: estado próprio, sem conhecer panes nem
/// sessões — o VM dono injeta os efeitos que dependem de aba (reabrir arquivo,
/// reapontar viewers de um rename, fechar abas de um path deletado).
class FileOpsController extends ChangeNotifier {
  FileOpsController(this._mutator);

  final FileSystemMutator _mutator;

  // ---- contexto injetado pelo VM dono (mesma vida page-scoped) -------------

  /// Abre o arquivo recém-criado numa aba.
  Future<void> Function(String path)? openFile;

  /// Reaponta as abas de viewer afetadas por um rename/move (`from` → `to`).
  Future<void> Function(String from, String to)? retargetSessions;

  /// Fecha as abas de viewer de tudo em/sob um caminho que vai ser deletado.
  void Function(String path)? closeSessionsUnder;

  /// A árvore de arquivos mudou de forma estrutural (o VM bumpa a revisão).
  VoidCallback? onTreeChanged;

  void _bumpTree() => onTreeChanged?.call();

  // ---- criar / renomear / mover / deletar -----------------------------------

  /// Cria um arquivo vazio chamado [name] dentro de [dirPath] e o abre no pane
  /// (quando [open]). Valida o nome (não-vazio, sem `/`).
  Future<Result<void, FileOperationError>> createFileIn(
    String dirPath,
    String name, {
    bool open = true,
  }) async {
    final invalid = validateName(name);
    if (invalid != null) return Failure(invalid);
    final path = joinPath(dirPath, name.trim());
    final r = await _mutator.createFile(path);
    if (r.isSuccess) {
      _bumpTree();
      if (open) await openFile?.call(path);
    }
    return r;
  }

  /// Cria uma pasta [name] dentro de [dirPath]. Refaz a árvore no sucesso.
  Future<Result<void, FileOperationError>> createDirIn(
    String dirPath,
    String name,
  ) async {
    final invalid = validateName(name);
    if (invalid != null) return Failure(invalid);
    final r = await _mutator.createDirectory(joinPath(dirPath, name.trim()));
    if (r.isSuccess) _bumpTree();
    return r;
  }

  /// Renomeia [path] para [newName] (mesma pasta). As abas abertas do arquivo
  /// (ou de descendentes, se for pasta) **seguem** o novo caminho.
  Future<Result<void, FileOperationError>> renamePath(
    String path,
    String newName,
  ) async {
    final invalid = validateName(newName);
    if (invalid != null) return Failure(invalid);
    return _moveTo(path, joinPath(dirnameOf(path), newName.trim()));
  }

  /// Move [path] pra **dentro** de [targetDir] (drag-and-drop na árvore),
  /// mantendo o nome. As abas abertas seguem o novo caminho, como no rename.
  Future<Result<void, FileOperationError>> movePath(
    String path,
    String targetDir,
  ) async {
    final name = basenameOf(path);
    if (name.isEmpty) {
      return const Failure(
        FileOperationError(FileOperationErrorKind.invalidPath),
      );
    }
    if (dirnameOf(path) == targetDir) return const Success(null); // já está lá
    if (isUnderPath(targetDir, path)) {
      return const Failure(
        FileOperationError(FileOperationErrorKind.cannotMoveIntoItself),
      );
    }
    return _moveTo(path, joinPath(targetDir, name));
  }

  /// Move de fato + reaponta as abas + refaz a árvore. Forma comum do rename,
  /// do move e do paste-recortado.
  Future<Result<void, FileOperationError>> _moveTo(
    String from,
    String to,
  ) async {
    final r = await _mutator.rename(from, to);
    if (r.isSuccess) {
      await retargetSessions?.call(from, to);
      _bumpTree();
    }
    return r;
  }

  /// Manda [path] pra lixeira. **Fecha antes** as abas do arquivo (ou de tudo
  /// dentro da pasta), sem prompt de salvar — a deleção sobrepõe.
  Future<Result<void, FileOperationError>> deletePath(String path) async {
    closeSessionsUnder?.call(path);
    final r = await _mutator.moveToTrash(path);
    if (r.isSuccess) _bumpTree();
    return r;
  }

  // ---- drop nativo (Finder/Explorer → árvore) --------------------------------

  /// Traz [sources] (caminhos absolutos soltos pelo SO) pra dentro de
  /// [targetDir]. Origem já dentro de [workspaceRoot] é MOVIDA (é o mesmo
  /// gesto do arrasto interno); origem de fora é COPIADA (arquivo ou pasta,
  /// recursivo), com sufixo ` copy` quando o nome já existe. Para na primeira
  /// falha e a devolve; o que já entrou fica.
  Future<Result<void, FileOperationError>> importInto(
    List<String> sources,
    String targetDir, {
    required String workspaceRoot,
  }) async {
    var changed = false;
    try {
      for (final raw in sources) {
        final from = normalizePath(raw).replaceAll(RegExp(r'/+$'), '');
        final name = basenameOf(from);
        if (name.isEmpty) {
          return const Failure(
            FileOperationError(FileOperationErrorKind.invalidPath),
          );
        }
        // Soltar uma pasta dentro dela mesma (ou de uma descendente) não tem
        // resultado possível.
        if (targetDir == from || isUnderPath(targetDir, from)) {
          return const Failure(
            FileOperationError(FileOperationErrorKind.cannotMoveIntoItself),
          );
        }
        final internal =
            workspaceRoot.isNotEmpty && isUnderPath(from, workspaceRoot);
        if (internal) {
          // Já está no destino: nada a fazer.
          if (dirnameOf(from) == targetDir) continue;
          final r = await _mutator.rename(from, joinPath(targetDir, name));
          if (r case Failure()) return r;
          await retargetSessions?.call(from, joinPath(targetDir, name));
          changed = true;
          continue;
        }
        final to = await _uniqueDest(targetDir, name);
        final r = await _mutator.copy(from, to);
        if (r case Failure()) return r;
        changed = true;
      }
      return const Success(null);
    } finally {
      if (changed) _bumpTree();
    }
  }

  // ---- clipboard da árvore (copiar / recortar / colar) ----------------------

  /// Caminho no clipboard interno da árvore (`null` = vazio).
  String? _clipboardPath;

  /// `true` = recortar (move no paste), `false` = copiar (duplica no paste).
  bool _clipboardCut = false;

  /// Há algo pronto pra colar? Habilita o item "Paste" no menu.
  bool get canPaste => _clipboardPath != null;

  /// Marca [path] pra **copiar** (o paste duplica).
  void copyToClipboard(String path) {
    _clipboardPath = path;
    _clipboardCut = false;
    notifyListeners();
  }

  /// Marca [path] pra **recortar** (o paste move e limpa o clipboard).
  void cutToClipboard(String path) {
    _clipboardPath = path;
    _clipboardCut = true;
    notifyListeners();
  }

  /// Cola o item do clipboard **dentro** de [targetDir]. Copia ou move conforme
  /// o modo. Se o nome colidir no destino, gera um sufixo (`nome copy`,
  /// `nome copy 2`, ...). Recorte limpa o clipboard no sucesso; cópia mantém
  /// (permite colar várias vezes).
  Future<Result<void, FileOperationError>> pasteInto(String targetDir) async {
    final from = _clipboardPath;
    if (from == null) {
      return const Failure(
        FileOperationError(FileOperationErrorKind.clipboardEmpty),
      );
    }
    final name = basenameOf(from);
    if (name.isEmpty) {
      return const Failure(
        FileOperationError(FileOperationErrorKind.invalidPath),
      );
    }
    if (_clipboardCut && isUnderPath(targetDir, from)) {
      return const Failure(
        FileOperationError(FileOperationErrorKind.cannotMoveIntoItself),
      );
    }
    final to = await _uniqueDest(targetDir, name);
    if (_clipboardCut) {
      final r = await _moveTo(from, to);
      if (r.isSuccess) _clipboardPath = null;
      return r;
    }
    final r = await _mutator.copy(from, to);
    if (r.isSuccess) _bumpTree();
    return r;
  }

  /// Caminho livre em [dir] pra [name]: devolve `dir/name` se não existir, senão
  /// insere ` copy`, ` copy 2`, ... antes da extensão até achar um livre.
  Future<String> _uniqueDest(String dir, String name) async {
    var candidate = joinPath(dir, name);
    if (!await _pathExists(candidate)) return candidate;
    final dot = name.lastIndexOf('.');
    final hasExt = dot > 0;
    final stem = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var i = 1; ; i++) {
      final suffix = i == 1 ? ' copy' : ' copy $i';
      candidate = joinPath(dir, '$stem$suffix$ext');
      if (!await _pathExists(candidate)) return candidate;
    }
  }

  Future<bool> _pathExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// `null` se válido; senão o erro tipado. Nesta fase: sem aninhar (`/`).
  /// Público porque o "salvar scratch como…" do VM valida o mesmo nome.
  FileOperationError? validateName(String name) {
    final n = name.trim();
    if (n.isEmpty) {
      return const FileOperationError(FileOperationErrorKind.emptyName);
    }
    if (n.contains('/')) {
      return const FileOperationError(FileOperationErrorKind.nameHasSlash);
    }
    if (n == '.' || n == '..') {
      return const FileOperationError(FileOperationErrorKind.invalidName);
    }
    return null;
  }
}
