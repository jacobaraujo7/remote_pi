// Modelo da árvore de splits do multiplexador (binária).
//
// Um LeafPane é um container com abas (cada aba = um agente). Um SplitPane
// divide o espaço entre dois nós, lado a lado (SplitDir.vertical) ou empilhados
// (SplitDir.horizontal). Fechar uma pane faz o irmão expandir (ver removeLeaf).
// Imutável: as operações devolvem uma árvore nova.

enum SplitDir { vertical, horizontal }

sealed class PaneNode {
  const PaneNode(this.id);
  final String id;
}

/// Folha: container de abas. [tabs] são ids de sessões de agente; [active] é a
/// aba selecionada.
final class LeafPane extends PaneNode {
  const LeafPane({required String id, required this.tabs, required this.active})
    : super(id);

  final List<String> tabs;
  final String active;

  LeafPane copyWith({List<String>? tabs, String? active}) =>
      LeafPane(id: id, tabs: tabs ?? this.tabs, active: active ?? this.active);
}

/// Split: divide [a] e [b] na proporção [frac] (0..1) na direção [dir].
final class SplitPane extends PaneNode {
  const SplitPane({
    required String id,
    required this.dir,
    required this.a,
    required this.b,
    required this.frac,
  }) : super(id);

  final SplitDir dir;
  final PaneNode a;
  final PaneNode b;
  final double frac;

  SplitPane copyWith({PaneNode? a, PaneNode? b, double? frac}) => SplitPane(
    id: id,
    dir: dir,
    a: a ?? this.a,
    b: b ?? this.b,
    frac: frac ?? this.frac,
  );
}

// ---- serialização (persistência do layout) ----------------------------------

/// Serializa a árvore pra um mapa JSON-friendly (só primitivos/listas/mapas).
Map<String, dynamic> paneNodeToJson(PaneNode node) {
  return switch (node) {
    LeafPane() => <String, dynamic>{
      'k': 'leaf',
      'id': node.id,
      'tabs': node.tabs,
      'active': node.active,
    },
    SplitPane() => <String, dynamic>{
      'k': 'split',
      'id': node.id,
      'dir': node.dir.name,
      'frac': node.frac,
      'a': paneNodeToJson(node.a),
      'b': paneNodeToJson(node.b),
    },
  };
}

/// Reconstrói a árvore a partir do mapa de [paneNodeToJson].
PaneNode paneNodeFromJson(Map<String, dynamic> json) {
  if (json['k'] == 'split') {
    return SplitPane(
      id: json['id'] as String,
      dir: SplitDir.values.byName(json['dir'] as String),
      frac: (json['frac'] as num).toDouble(),
      a: paneNodeFromJson((json['a'] as Map).cast<String, dynamic>()),
      b: paneNodeFromJson((json['b'] as Map).cast<String, dynamic>()),
    );
  }
  return LeafPane(
    id: json['id'] as String,
    tabs: (json['tabs'] as List).cast<String>(),
    active: json['active'] as String,
  );
}

// ---- helpers puros (espelham os do design) ----------------------------------

List<LeafPane> leaves(PaneNode node, [List<LeafPane>? acc]) {
  final out = acc ?? <LeafPane>[];
  switch (node) {
    case LeafPane():
      out.add(node);
    case SplitPane(:final a, :final b):
      leaves(a, out);
      leaves(b, out);
  }
  return out;
}

LeafPane? findLeaf(PaneNode node, String id) {
  for (final leaf in leaves(node)) {
    if (leaf.id == id) return leaf;
  }
  return null;
}

PaneNode setFrac(PaneNode node, String splitId, double frac) {
  return switch (node) {
    LeafPane() => node,
    SplitPane() =>
      node.id == splitId
          ? node.copyWith(frac: frac)
          : node.copyWith(
              a: setFrac(node.a, splitId, frac),
              b: setFrac(node.b, splitId, frac),
            ),
  };
}

PaneNode updateLeaf(
  PaneNode node,
  String id,
  LeafPane Function(LeafPane) update,
) {
  return switch (node) {
    LeafPane() => node.id == id ? update(node) : node,
    SplitPane() => node.copyWith(
      a: updateLeaf(node.a, id, update),
      b: updateLeaf(node.b, id, update),
    ),
  };
}

/// Divide a folha [id] em [dir], colocando [newLeaf] ao lado dela. Por padrão o
/// novo pane fica **depois** (direita/baixo); [before] = true o põe **antes**
/// (esquerda/cima). [splitId] permite um id único (evita colisão ao dividir a
/// mesma folha mais de uma vez); se omitido, deriva de `id`+`dir`.
PaneNode splitLeaf(
  PaneNode node,
  String id,
  SplitDir dir,
  LeafPane newLeaf, {
  String? splitId,
  bool before = false,
}) {
  return switch (node) {
    LeafPane() =>
      node.id == id
          ? SplitPane(
              id: splitId ?? 'sp_${id}_$dir',
              dir: dir,
              a: before ? newLeaf : node,
              b: before ? node : newLeaf,
              frac: 0.5,
            )
          : node,
    SplitPane() => node.copyWith(
      a: splitLeaf(node.a, id, dir, newLeaf, splitId: splitId, before: before),
      b: splitLeaf(node.b, id, dir, newLeaf, splitId: splitId, before: before),
    ),
  };
}

/// Reordena [tabId] dentro de [tabs] pro slot [index] (0..len), devolvendo a
/// nova ordem. [index] é a posição-alvo na lista **antes** da remoção (semântica
/// de "soltar no slot i"); o ajuste pós-remoção é feito aqui. Se [tabId] não está
/// na lista, devolve a lista inalterada.
List<String> reorderTabs(List<String> tabs, String tabId, int index) {
  final out = [...tabs];
  final from = out.indexOf(tabId);
  if (from < 0) return out;
  out.removeAt(from);
  var to = index;
  if (to > from) to -= 1; // o item saiu antes do alvo → desloca uma posição
  to = to.clamp(0, out.length);
  out.insert(to, tabId);
  return out;
}

// ---- navegação direcional entre panes (atalhos ⌘⌥ + setas) ------------------

/// Direção do movimento de foco entre panes.
enum PaneMove { left, right, up, down }

/// Id do leaf **vizinho** a partir de [fromLeafId] na direção [move], ou `null`
/// se não há pane naquela direção. Deriva da árvore de splits (sem geometria em
/// pixels): sobe até o ancestral do eixo certo em que o leaf de origem está no
/// lado "de partida", cruza pro irmão e desce escolhendo o leaf mais próximo da
/// borda compartilhada. Setas ←→ andam em splits verticais (lado a lado); ↑↓ em
/// splits horizontais (empilhados).
String? neighborLeaf(PaneNode root, String fromLeafId, PaneMove move) {
  final path = _pathTo(root, fromLeafId);
  if (path == null) return null;
  final axis = (move == PaneMove.left || move == PaneMove.right)
      ? SplitDir.vertical
      : SplitDir.horizontal;
  // Direita/baixo = ir do lado `a` pro `b`; esquerda/cima = de `b` pro `a`.
  final towardB = move == PaneMove.right || move == PaneMove.down;
  // Do leaf pra cima: o primeiro ancestral no eixo certo cujo lado bate é a
  // fronteira com o vizinho. Ancestrais de eixo/lado errados = já estamos na
  // borda em relação a eles → continua subindo.
  for (final step in path.reversed) {
    if (step.split.dir != axis) continue;
    if (towardB && step.tookA) return _descendNearest(step.split.b, axis, true);
    if (!towardB && !step.tookA) {
      return _descendNearest(step.split.a, axis, false);
    }
  }
  return null;
}

/// Caminho da raiz até o leaf [id]: cada passo é o [SplitPane] atravessado e se
/// descemos pelo lado `a` ([tookA] = true) ou `b`. `null` se o leaf não existe.
List<({SplitPane split, bool tookA})>? _pathTo(PaneNode node, String id) {
  switch (node) {
    case LeafPane():
      return node.id == id ? const [] : null;
    case SplitPane(:final a, :final b):
      final viaA = _pathTo(a, id);
      if (viaA != null) return [(split: node, tookA: true), ...viaA];
      final viaB = _pathTo(b, id);
      if (viaB != null) return [(split: node, tookA: false), ...viaB];
      return null;
  }
}

/// Desce numa subárvore até um leaf, colando na borda compartilhada: no [axis]
/// do movimento escolhe o lado perto da fronteira ([preferA] = pega `a`); no
/// eixo cruzado pega `a` (determinístico — sem geometria pra desempatar).
String _descendNearest(PaneNode node, SplitDir axis, bool preferA) {
  var n = node;
  while (n is SplitPane) {
    n = n.dir == axis ? (preferA ? n.a : n.b) : n.a;
  }
  return (n as LeafPane).id;
}

/// Remove a folha [id]; se ela for filha de um split, o irmão toma o lugar.
PaneNode removeLeaf(PaneNode node, String id) {
  switch (node) {
    case LeafPane():
      return node;
    case SplitPane(:final a, :final b):
      if (a is LeafPane && a.id == id) return b;
      if (b is LeafPane && b.id == id) return a;
      return node.copyWith(a: removeLeaf(a, id), b: removeLeaf(b, id));
  }
}
