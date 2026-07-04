import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';

/// Lê o diff de um arquivo contra o HEAD do repo. Só leitura — alimenta o
/// `DiffViewer`. A impl (roda `git diff HEAD`) mora em `data/`.
abstract class GitDiffReader {
  /// Diff de [absPath] (caminho absoluto) contra o HEAD do repo em [repoPath].
  /// Trata novo (tudo adicionado), deletado (tudo removido), binário e sem
  /// mudança. Nunca lança — em erro devolve [FileDiffKind.unchanged].
  Future<FileDiff> read(String repoPath, String absPath);
}
