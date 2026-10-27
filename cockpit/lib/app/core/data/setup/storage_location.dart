import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Subdiretório raiz do estado do Cockpit (JSONs de estado, .hive legados de
/// backup e o cache de scrollback). Em debug usa `cockpit-debug` para não
/// colidir com a build de produção (que costuma ficar aberta em paralelo
/// durante o desenvolvimento).
const String storageSubdir = kDebugMode ? 'cockpit-debug' : 'cockpit';

/// Resolve — e deixa o usuário escolher — a pasta onde o Cockpit guarda seu
/// estado (JSONs em `state/`: settings/projects/layouts/realms/window_state;
/// e o cache de scrollback dos terminais).
///
/// **Ovo-e-galinha do bootstrap**: a pasta escolhida precisa ser lida *antes* de
/// o app saber qual é. Por isso o "ponteiro" mora num lugar fixo e
/// **não-relocável** (`~/.cockpit/storage_root`) — um único caminho absoluto (a
/// raiz escolhida) ou ausente = usar o padrão do sistema.
///
/// **Paths sempre via `package:path`** (`p.join`/`p.normalize`): no Windows os
/// diretórios do sistema vêm com `\`, e interpolar `/` na mão gerava paths
/// mistos que quebravam criação/resolução de diretório (bug de campo).
///
/// Só o **estado** é relocado; o scrollback é cache local (fica no
/// applicationSupport, não faz sentido sincronizar logs pesados). O reset,
/// porém, limpa os dois.
class StorageLocation {
  const StorageLocation._();

  /// Dedicated root for disposable parallel runs. The launcher sets this only
  /// for the isolated process; normal installations keep their existing paths.
  static String? get _isolatedRoot {
    final raw = Platform.environment['COCKPIT_ISOLATED_ROOT']?.trim();
    if (raw == null || raw.isEmpty || !p.isAbsolute(raw)) return null;
    return p.normalize(raw);
  }

  /// Monta `<root>/<storageSubdir>` normalizado, com contexto injetável de
  /// `package:path` — puro, pra testar a montagem com separadores Windows
  /// mesmo rodando em macOS/Linux.
  @visibleForTesting
  static String dataDirUnder(String root, [p.Context? ctx]) {
    final c = ctx ?? p.context;
    return c.normalize(c.join(root.trim(), storageSubdir));
  }

  /// Normaliza o conteúdo do ponteiro `storage_root` — pode ter sido gravado
  /// por versão antiga com separador diferente do que a plataforma usa.
  @visibleForTesting
  static String normalizeRoot(String raw, [p.Context? ctx]) =>
      (ctx ?? p.context).normalize(raw.trim());

  /// Ponteiro fixo: aponta pra raiz escolhida. Fora de qualquer pasta relocável.
  static String? get _pointerPath {
    final home = remotePiHome();
    if (home == null) return null;
    return p.join(home, '.cockpit', 'storage_root');
  }

  /// Raiz escolhida pelo usuário (o que ele selecionou no picker), ou `null`
  /// quando usa a localização padrão do sistema. O conteúdo é normalizado na
  /// leitura — pode ter sido gravado por versão antiga com separador diferente.
  static Future<String?> overrideRoot() async {
    if (_isolatedRoot case final root?) return root;
    final path = _pointerPath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = (await file.readAsString()).trim();
      return content.isEmpty ? null : normalizeRoot(content);
    } catch (_) {
      return null; // ponteiro ilegível → cai no padrão
    }
  }

  /// Define a raiz escolhida e grava o ponteiro (normalizado pra plataforma).
  /// `null`/vazio limpa o override.
  static Future<void> setOverrideRoot(String? root) async {
    final path = _pointerPath;
    if (path == null) return;
    final file = File(path);
    await file.parent.create(recursive: true);
    final trimmed = root?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(normalizeRoot(trimmed));
  }

  /// Raiz efetiva (override ou o padrão da plataforma) — a pasta que o usuário
  /// "vê" como local do Cockpit. É sob ela que fica o subdiretório
  /// [storageSubdir].
  ///
  /// **Windows**: o padrão é `getApplicationSupportDirectory()` (AppData), e
  /// **não** Documents. Em Windows 10/11 com Known Folder Move, a pasta
  /// Documents é sincronizada pelo OneDrive — que segura handles/locks nos
  /// arquivos e causava corrupção e crashes reportados. macOS e Linux mantêm
  /// Documents (comportamento que sempre funcionou — não mexer).
  static Future<String> effectiveRoot() async {
    final override = await overrideRoot();
    if (override != null) return override;
    if (Platform.isWindows) {
      final support = await getApplicationSupportDirectory();
      return support.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// Diretório de dados do app (`<raiz>/<storageSubdir>`). Era onde as boxes do
  /// Hive moravam; hoje abriga a subpasta [stateDir] de JSONs (e os `.hive`
  /// legados, mantidos como backup pós-migração). Garante que existe.
  static Future<String> dataDir() async {
    final dir = dataDirUnder(await effectiveRoot());
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Diretório dos JSONs de estado (`<dataDir>/state`) — é o que o bootstrap
  /// passa pros [JsonStateStore]s. Garante que existe.
  static Future<String> stateDir() async {
    final dir = p.join(await dataDir(), 'state');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Diretórios candidatos a conter boxes Hive **legadas** (pré-migração
  /// Hive→JSON), em ordem de precedência: raiz custom (override) → AppData
  /// (default novo do Windows) → Documents (legado Windows e default atual de
  /// macOS/Linux). O migrador usa o primeiro que tiver boxes.
  static Future<List<String>> legacyHiveDirCandidates() async {
    if (_isolatedRoot case final root?) return [dataDirUnder(root)];
    final dirs = <String>[];
    final override = await overrideRoot();
    if (override != null) dirs.add(dataDirUnder(override));
    final support = await getApplicationSupportDirectory();
    dirs.add(dataDirUnder(support.path));
    final docs = await getApplicationDocumentsDirectory();
    dirs.add(dataDirUnder(docs.path));
    // Dedup preservando ordem (override pode coincidir com um default);
    // normaliza antes de comparar pra não duplicar por separador diferente.
    return {for (final d in dirs) p.normalize(d)}.toList();
  }

  /// Diretório do cache de scrollback — **sempre local** (applicationSupport),
  /// não segue o override. Exposto pra que o reset o limpe.
  static Future<String> scrollbackDir() async {
    if (_isolatedRoot case final root?) {
      return p.join(root, 'terminal_scrollback');
    }
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'terminal_scrollback');
  }

  /// `true` quando o usuário escolheu uma pasta custom (não o padrão).
  static Future<bool> isCustom() async => (await overrideRoot()) != null;

  /// Copia o estado atual para dentro de [targetRoot] (em
  /// `<targetRoot>/<storageSubdir>`), pra que a nova pasta já nasça com os
  /// dados — evita a surpresa de "meus projetos sumiram" ao trocar de pasta.
  /// Só copia se o destino ainda **não** tiver dados (não sobrescreve um
  /// Cockpit existente naquela pasta). Retorna `true` se copiou.
  static Future<bool> migrateStateTo(String targetRoot) async {
    final src = Directory(await dataDir());
    final dst = Directory(dataDirUnder(targetRoot));
    if (!await src.exists()) return false;
    if (await dst.exists() && await _hasEntries(dst)) return false;
    await _copyTree(src, dst, skipLockFiles: true);
    return true;
  }

  /// Cópia recursiva de [src] pra [dst] (cria [dst]). Com [skipLockFiles],
  /// pula `*.lock` — locks efêmeros do Hive legado, inúteis no destino.
  /// O caminho relativo é calculado com `p.relative` (não substring), imune a
  /// separadores mistos.
  static Future<void> _copyTree(
    Directory src,
    Directory dst, {
    bool skipLockFiles = false,
  }) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: src.path);
      final target = p.join(dst.path, rel);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        if (skipLockFiles && p.extension(entity.path) == '.lock') continue;
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }

  /// Apaga TODO o estado do Cockpit (JSONs + .hive legados + scrollback) e
  /// limpa o override — volta pro padrão de fábrica. A UI força reinício logo
  /// em seguida (os stores seguem em memória até o processo morrer).
  static Future<void> resetAll() async {
    for (final dir in [
      Directory(await dataDir()),
      Directory(await scrollbackDir()),
    ]) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        /* best-effort: arquivo travado some no próximo boot */
      }
    }
    await setOverrideRoot(null);
  }

  static Future<bool> _hasEntries(Directory dir) async {
    await for (final _ in dir.list(followLinks: false)) {
      return true;
    }
    return false;
  }
}
