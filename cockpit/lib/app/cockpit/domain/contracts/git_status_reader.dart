import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';

/// Lê o estado git de uma pasta. Contrato no domínio; a impl (roda `git`) mora
/// em `data/`.
abstract class GitStatusReader {
  /// [GitInfo] do repo em [path], ou `null` se a pasta **não** é repositório git
  /// (ou o git não está disponível).
  ///
  /// [withLineStats] also runs `git diff --numstat HEAD` to fill
  /// [GitInfo.insertions]/[GitInfo.deletions]; off by default because only the
  /// terminal status line shows them, and the poll runs every few seconds.
  Future<GitInfo?> read(String path, {bool withLineStats = false});
}
