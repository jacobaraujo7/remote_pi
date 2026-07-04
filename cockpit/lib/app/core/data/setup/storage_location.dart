import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Subdiretório raiz das boxes do Hive **e** do scrollback. Em debug usa
/// `cockpit-debug` para não colidir com a build de produção (que costuma ficar
/// aberta em paralelo durante o desenvolvimento).
const String hiveSubdir = kDebugMode ? 'cockpit-debug' : 'cockpit';

/// Resolve — e deixa o usuário escolher — a pasta onde o Cockpit guarda seu
/// estado (Hive: settings/projects/layouts/window_state; e o cache de
/// scrollback dos terminais).
///
/// **Ovo-e-galinha do bootstrap**: a pasta escolhida precisa ser lida *antes* de
/// o app saber qual é. Por isso o "ponteiro" mora num lugar fixo e
/// **não-relocável** (`~/.cockpit/storage_root`) — um único caminho absoluto (a
/// raiz escolhida) ou ausente = usar o padrão do sistema.
///
/// Só o **Hive** é relocado; o scrollback é cache local (fica no
/// applicationSupport, não faz sentido sincronizar logs pesados). O reset,
/// porém, limpa os dois.
class StorageLocation {
  const StorageLocation._();

  /// Ponteiro fixo: aponta pra raiz escolhida. Fora de qualquer pasta relocável.
  static String? get _pointerPath {
    final home = remotePiHome();
    if (home == null) return null;
    return '$home/.cockpit/storage_root';
  }

  /// Raiz escolhida pelo usuário (o que ele selecionou no picker), ou `null`
  /// quando usa a localização padrão do sistema.
  static Future<String?> overrideRoot() async {
    final path = _pointerPath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = (await file.readAsString()).trim();
      return content.isEmpty ? null : content;
    } catch (_) {
      return null; // ponteiro ilegível → cai no padrão
    }
  }

  /// Define a raiz escolhida e grava o ponteiro. `null`/vazio limpa o override.
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
    await file.writeAsString(trimmed);
  }

  /// Raiz efetiva (override ou o Documents do sistema) — a pasta que o usuário
  /// "vê" como local do Cockpit. É sob ela que fica o subdiretório [hiveSubdir].
  static Future<String> effectiveRoot() async {
    final override = await overrideRoot();
    if (override != null) return override;
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// Diretório absoluto das boxes do Hive (`<raiz>/<hiveSubdir>`). É o que o
  /// `main` passa pro `Hive.init`. Garante que o diretório existe — `Hive.init`
  /// (síncrono) não cria a árvore, e uma pasta custom recém-escolhida pode ainda
  /// não ter o subdiretório.
  static Future<String> hiveDir() async {
    final dir = '${await effectiveRoot()}/$hiveSubdir';
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Diretório do cache de scrollback — **sempre local** (applicationSupport),
  /// não segue o override. Exposto pra que o reset o limpe.
  static Future<String> scrollbackDir() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}/terminal_scrollback';
  }

  /// `true` quando o usuário escolheu uma pasta custom (não o padrão).
  static Future<bool> isCustom() async => (await overrideRoot()) != null;

  /// Copia as boxes atuais do Hive para dentro de [targetRoot] (em
  /// `<targetRoot>/<hiveSubdir>`), pra que a nova pasta já nasça com os dados —
  /// evita a surpresa de "meus projetos sumiram" ao trocar de pasta. Só copia se
  /// o destino ainda **não** tiver dados (não sobrescreve um Cockpit existente
  /// naquela pasta). Retorna `true` se copiou.
  static Future<bool> migrateHiveTo(String targetRoot) async {
    final src = Directory(await hiveDir());
    final dst = Directory('$targetRoot/$hiveSubdir');
    if (!await src.exists()) return false;
    if (await dst.exists() && await _hasEntries(dst)) return false;
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = entity.path.substring(src.path.length);
      final target = '${dst.path}$rel';
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
    return true;
  }

  /// Apaga TODO o estado do Cockpit (Hive + scrollback) e limpa o override —
  /// volta pro padrão de fábrica. A UI força reinício logo em seguida (as boxes
  /// seguem abertas em memória até o processo morrer).
  static Future<void> resetAll() async {
    for (final dir in [
      Directory(await hiveDir()),
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
