import 'package:cockpit/app/cockpit/domain/contracts/git_head_baseline_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_head_baseline.dart';

/// Cache de baseline por `(gitRoot, path, headIdentity)`.
///
/// Entradas de uma revisão antiga não são reutilizadas: a chave inclui a
/// identidade de `HEAD`. [invalidateRepo] limpa tudo de uma root (retarget /
/// troca de contexto).
class ScmBaselineCache {
  ScmBaselineCache(this._reader);

  final GitHeadBaselineReader _reader;

  final Map<String, GitHeadBaseline> _entries = <String, GitHeadBaseline>{};
  final Map<String, String?> _headByRepo = <String, String?>{};

  /// Resolve identidade de `HEAD` (com cache curto por root).
  Future<String?> headIdentity(String repoPath) async {
    if (_headByRepo.containsKey(repoPath)) return _headByRepo[repoPath];
    final id = await _reader.resolveHeadIdentity(repoPath);
    _headByRepo[repoPath] = id;
    return id;
  }

  /// Baseline textual cacheado, ou `null` se inelegível/falha.
  Future<GitHeadBaseline?> baselineFor(String repoPath, String absPath) async {
    final head = await headIdentity(repoPath);
    if (head == null) return null;

    final key = _key(repoPath, absPath, head);
    final cached = _entries[key];
    if (cached != null) return cached;

    final fresh = await _reader.readTrackedText(repoPath, absPath);
    if (fresh == null) return null;
    // Só cacheia se a identidade ainda bate (HEAD pode ter mudado durante I/O).
    if (fresh.headIdentity != head) return fresh;
    _entries[key] = fresh;
    return fresh;
  }

  /// Descarta cache de [repoPath] (ex.: revisão Git mudou).
  void invalidateRepo(String repoPath) {
    _headByRepo.remove(repoPath);
    _entries.removeWhere((key, _) => key.startsWith('$repoPath\u0000'));
  }

  /// Invalida todas as roots (ex.: refresh global).
  void invalidateAll() {
    _headByRepo.clear();
    _entries.clear();
  }

  static String _key(String repoPath, String absPath, String head) =>
      '$repoPath\u0000$absPath\u0000$head';
}
