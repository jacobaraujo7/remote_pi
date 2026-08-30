import 'dart:convert';

import 'package:cockpit_core/cockpit_core.dart' show FileEntry, FileService;

/// Descobre as **roots git** de uma pasta no host remoto, com a mesma regra do
/// `GitController.deriveRoots` local (multirepo por detecção implícita):
///
/// - a pasta tem `.git` → `[path]` (single-root; monorepo é isso, N=1);
/// - senão, filhas imediatas com `.git` → multi-root;
/// - nenhuma → `[path]` (pasta comum, sem git).
///
/// Filha que é **worktree linkada de um repo-irmão** não vira root: ela já
/// aparece como fork da irmã em `git worktree list`, e promovê-la duplicaria o
/// fork no rail — o mesmo cuidado do local.
///
/// Roda inteiramente sobre `fs.list` / `fs.read`, que **todo servidor já
/// implementa**: nada de método novo no protocolo, nada de atualizar os hosts
/// que já estão instalados. Custa uma listagem da raiz mais uma por filha,
/// disparadas em paralelo.
class RemoteRootFinder {
  const RemoteRootFinder(this._files);

  final FileService _files;

  /// Teto de filhas inspecionadas. Pasta com centenas de subpastas não é
  /// workspace multirepo, e sem o teto uma pasta enorme (ex.: `$HOME`) viraria
  /// centenas de round-trips SSH no boot.
  static const int maxChildren = 60;

  /// Máximo de listagens/leituras em voo ao mesmo tempo. Todas viajam pelo
  /// **mesmo** canal SSH: disparar as 60 de uma vez não deixa nada mais rápido
  /// e, no mobile (transporte em Dart, no isolate da UI), engasga o app inteiro
  /// durante o boot.
  static const int maxConcurrency = 6;

  Future<List<String>> deriveRoots(String path) async {
    final root = _normalize(path);
    if (root.isEmpty) return const [];

    final List<FileEntry> rootEntries;
    try {
      rootEntries = await _files.list(root);
    } on Object {
      return [root]; // pasta ilegível/host offline → trata como comum
    }
    // A listagem da raiz responde as DUAS perguntas — "tem `.git`?" e "quais
    // são as filhas?" —, então é feita uma vez só.
    if (rootEntries.any((e) => e.name == '.git')) return [root];

    final children = <FileEntryLike>[
      for (final e in rootEntries)
        if (e.isDirectory && !e.name.startsWith('.'))
          (name: e.name, path: '$root/${e.name}'),
    ];
    if (children.isEmpty || children.length > maxChildren) return [root];

    final flags = await _mapLimited(children, (c) => _hasGit(c.path));
    final roots = <String>[
      for (var i = 0; i < children.length; i++)
        if (flags[i]) children[i].path,
    ];
    if (roots.isEmpty) return [root];

    final linked = await _mapLimited(
      roots,
      (r) => _isWorktreeOfSibling(r, roots),
    );
    final kept = <String>[
      for (var i = 0; i < roots.length; i++)
        if (!linked[i]) roots[i],
    ];
    if (kept.isEmpty) return [root];
    kept.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return kept;
  }

  /// `Future.wait` com teto de paralelismo, preservando a ordem de [items].
  static Future<List<R>> _mapLimited<T, R>(
    List<T> items,
    Future<R> Function(T item) task,
  ) async {
    final out = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        out[i] = await task(items[i]);
      }
    }

    final workers = items.length < maxConcurrency
        ? items.length
        : maxConcurrency;
    await Future.wait([for (var w = 0; w < workers; w++) worker()]);
    return out.cast<R>();
  }

  /// `.git` existe em [dir] — dir **ou arquivo** (worktree usa arquivo).
  Future<bool> _hasGit(String dir) async {
    try {
      final entries = await _files.list(dir);
      return entries.any((e) => e.name == '.git');
    } on Object {
      return false;
    }
  }

  /// `true` se [candidate] é worktree linkada de outra entrada de [candidates]:
  /// o `.git` é um **arquivo** com `gitdir: <path>` apontando para dentro do
  /// `.git/` de uma irmã.
  Future<bool> _isWorktreeOfSibling(
    String candidate,
    List<String> candidates,
  ) async {
    final String content;
    try {
      // `.git` de repo normal é diretório: a leitura falha e devolvemos false,
      // que é a resposta certa.
      content = utf8.decode(
        await _files.read('$candidate/.git', maxBytes: 4096),
        allowMalformed: true,
      );
    } on Object {
      return false;
    }
    final match = RegExp(
      r'^gitdir:\s*(.+)$',
      multiLine: true,
    ).firstMatch(content);
    if (match == null) return false;
    final gitdir = _normalize(match.group(1)!.trim());
    for (final sibling in candidates) {
      if (sibling == candidate) continue;
      if (gitdir.startsWith('$sibling/.git/')) return true;
    }
    return false;
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}

/// Par (nome, caminho) de uma filha — evita depender do tipo concreto de
/// entrada do `FileService` fora deste arquivo.
typedef FileEntryLike = ({String name, String path});
