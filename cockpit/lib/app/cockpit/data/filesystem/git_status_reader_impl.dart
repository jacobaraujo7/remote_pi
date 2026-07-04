import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';

/// Lê o estado git rodando o binário `git`. O caminho do `git` vem do
/// [GitBinary] compartilhado (o app macOS **não herda o PATH do shell**).
class GitStatusReaderImpl implements GitStatusReader {
  GitStatusReaderImpl(this._gitBinary);

  final GitBinary _gitBinary;

  @override
  Future<GitInfo?> read(String path) async {
    try {
      final git = await _gitBinary.resolve();

      // Branch atual — também serve de teste "é repo git?" (exit != 0 → não é).
      final branchRes = await Process.run(git, [
        '-C',
        path,
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      if (branchRes.exitCode != 0) return null;
      var branch = (branchRes.stdout as String).trim();
      if (branch.isEmpty) return null;
      if (branch == 'HEAD') {
        // detached HEAD → mostra o short SHA no lugar do nome do branch.
        final shaRes = await Process.run(git, [
          '-C',
          path,
          'rev-parse',
          '--short',
          'HEAD',
        ]);
        branch = shaRes.exitCode == 0
            ? (shaRes.stdout as String).trim()
            : 'HEAD';
      }

      // Status por arquivo (`-z` = entradas separadas por NUL, paths crus sem
      // aspas/escape). `--ignored` adiciona entradas `!!` (pastas ignoradas
      // colapsadas — não recursa dentro, então é barato). Mapa path→status +
      // set de raízes ignoradas; renames consomem o path antigo.
      final statusRes = await Process.run(git, [
        '-C',
        path,
        'status',
        '--porcelain=v1',
        '-z',
        '--ignored',
      ]);
      final (files, ignored, untrackedDirs) = statusRes.exitCode == 0
          ? _parsePorcelainZ(statusRes.stdout as String)
          : (
              const <String, GitFileStatus>{},
              const <String>{},
              const <String>{},
            );

      // Ahead/behind vs upstream (sem fetch — reflete o último estado conhecido).
      // `--count A...B` com `@{upstream}...HEAD` devolve "<behind>\t<ahead>";
      // exit != 0 quando não há upstream configurado → fica 0/0.
      var ahead = 0;
      var behind = 0;
      final abRes = await Process.run(git, [
        '-C',
        path,
        'rev-list',
        '--left-right',
        '--count',
        '@{upstream}...HEAD',
      ]);
      if (abRes.exitCode == 0) {
        final parts = (abRes.stdout as String).trim().split(RegExp(r'\s+'));
        if (parts.length == 2) {
          behind = int.tryParse(parts[0]) ?? 0;
          ahead = int.tryParse(parts[1]) ?? 0;
        }
      }

      return GitInfo(
        branch: branch,
        ahead: ahead,
        behind: behind,
        files: files,
        ignored: ignored,
        untrackedDirs: untrackedDirs,
      );
    } catch (_) {
      return null; // git ausente / pasta inacessível
    }
  }

  /// Parseia o output de `git status --porcelain=v1 -z`. Cada entrada é
  /// `XY <path>` terminada por NUL; renames/copies (`R`/`C` no index) têm o
  /// path de origem como uma entrada NUL extra, que ignoramos. Devolve:
  /// (mapa path→status, raízes ignoradas, raízes de pasta untracked colapsada).
  ///
  /// `git` colapsa pastas totalmente novas/ignoradas numa única entrada com
  /// barra final (`?? dir/`, `!! dir/`); guardamos a raiz pra colorir todos os
  /// descendentes (que não são enumerados).
  static (Map<String, GitFileStatus>, Set<String>, Set<String>)
  _parsePorcelainZ(String raw) {
    final out = <String, GitFileStatus>{};
    final ignored = <String>{};
    final untrackedDirs = <String>{};
    final tokens = raw.split('\u0000');
    for (var i = 0; i < tokens.length; i++) {
      final entry = tokens[i];
      if (entry.length < 4) continue; // "XY p" mínimo; '' final do split
      final x = entry[0];
      final y = entry[1];
      var pathPart = entry.substring(3); // pula "XY "
      // Rename/copy no index → o próximo token (NUL) é o path de origem; pula.
      if (x == 'R' || x == 'C') i++;
      final isDir = pathPart.endsWith('/'); // pasta colapsada (?? ou !!)
      if (isDir) pathPart = pathPart.substring(0, pathPart.length - 1);
      if (pathPart.isEmpty) continue;
      if (x == '!' && y == '!') {
        ignored.add(pathPart); // raiz ignorada (cobre descendentes)
        continue;
      }
      if (x == '?' && y == '?' && isDir) {
        untrackedDirs.add(
          pathPart,
        ); // pasta nova colapsada → cobre descendentes
      }
      final status = _classify(x, y);
      if (status != null) out[pathPart] = status;
    }
    return (out, ignored, untrackedDirs);
  }

  /// Mapeia os dois chars de status do porcelain pro nosso enum. A mudança no
  /// working tree (`Y`) tem prioridade sobre o index (`X`) na cor exibida,
  /// exceto conflito/deleção. Retorna `null` para `!!` (ignored) e estados que
  /// não nos interessam colorir.
  static GitFileStatus? _classify(String x, String y) {
    // Untracked.
    if (x == '?' && y == '?') return GitFileStatus.untracked;
    // Ignored (só aparece com --ignored; defensivo).
    if (x == '!' && y == '!') return null;
    // Conflito: algum lado 'U', ou DD/AA (ambos add/delete).
    if (x == 'U' ||
        y == 'U' ||
        (x == 'D' && y == 'D') ||
        (x == 'A' && y == 'A')) {
      return GitFileStatus.conflict;
    }
    // Deleção (index ou working tree).
    if (x == 'D' || y == 'D') return GitFileStatus.deleted;
    // Mudança no working tree (não staged) → modificado.
    if (y == 'M' || y == 'T' || y == 'R' || y == 'C') {
      return GitFileStatus.modified;
    }
    // Mudança só no index → staged (inclui add 'A').
    if (x == 'M' || x == 'T' || x == 'R' || x == 'C' || x == 'A') {
      return GitFileStatus.staged;
    }
    return null;
  }
}
