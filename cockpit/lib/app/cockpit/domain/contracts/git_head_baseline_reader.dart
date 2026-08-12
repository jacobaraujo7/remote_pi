import 'package:cockpit/app/cockpit/domain/entities/git_head_baseline.dart';

/// Obtém o baseline textual de um path no snapshot `HEAD`.
///
/// Nunca usa working tree nem index como conteúdo de comparação. Falhas e
/// paths inelegíveis devolvem `null` — sem lançar.
abstract class GitHeadBaselineReader {
  /// Identidade estável de `HEAD` no [repoPath], ou `null` se falhar.
  Future<String?> resolveHeadIdentity(String repoPath);

  /// Blob textual de [absPath] em `HEAD`, ou `null` se o path não estiver no
  /// snapshot rastreado, for binário, ou a leitura falhar.
  Future<GitHeadBaseline?> readTrackedText(String repoPath, String absPath);
}
