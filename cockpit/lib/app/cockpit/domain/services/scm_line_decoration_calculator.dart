import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';

/// Calcula [ScmLineDecorations] comparando o texto do baseline `HEAD` com o
/// buffer atual, em memória — sem I/O nem processo Git.
///
/// Em cada bloco misto, pares posicionais viram modificações; sobras atuais
/// viram adições; sobras do baseline viram **uma** fronteira de remoção.
class ScmLineDecorationCalculator {
  const ScmLineDecorationCalculator();

  ScmLineDecorations calculate({
    required String baseline,
    required String current,
  }) {
    if (baseline == current) return ScmLineDecorations.empty;

    final a = _splitLines(baseline);
    final b = _splitLines(current);
    final ops = _diffOps(a, b);

    final added = <int>{};
    final modified = <int>{};
    final removals = <int>{};

    var j = 0;
    var opIndex = 0;

    while (opIndex < ops.length) {
      final op = ops[opIndex];
      if (op == _Op.equal) {
        j++;
        opIndex++;
        continue;
      }

      var deleteCount = 0;
      var insertCount = 0;
      while (opIndex < ops.length) {
        final kind = ops[opIndex];
        if (kind == _Op.equal) break;
        if (kind == _Op.delete) {
          deleteCount++;
        } else {
          insertCount++;
        }
        opIndex++;
      }

      final pairs = deleteCount < insertCount ? deleteCount : insertCount;
      for (var p = 0; p < pairs; p++) {
        modified.add(j + p + 1);
      }
      for (var p = pairs; p < insertCount; p++) {
        added.add(j + p + 1);
      }
      if (deleteCount > pairs) {
        // Fronteira após as linhas atuais do bloco (ou antes da próxima
        // sobrevivente quando o bloco é só remoção).
        final boundary = j + insertCount;
        removals.add(boundary);
      }

      j += insertCount;
    }

    if (added.isEmpty && modified.isEmpty && removals.isEmpty) {
      return ScmLineDecorations.empty;
    }
    return ScmLineDecorations(
      addedLines: added,
      modifiedLines: modified,
      removalBoundaries: removals,
    );
  }

  /// Mesma regra do editor: `split('\n')` — `"a\n"` vira `["a", ""]`.
  static List<String> _splitLines(String text) => text.split('\n');

  /// Myers O(ND) simplificado → lista de ops alinhadas às sequências.
  static List<_Op> _diffOps(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 && m == 0) return const <_Op>[];
    if (n == 0) return List<_Op>.filled(m, _Op.insert);
    if (m == 0) return List<_Op>.filled(n, _Op.delete);

    final max = n + m;
    final offset = max;
    final v = List<int>.filled(2 * max + 1, 0);
    final trace = <List<int>>[];

    for (var d = 0; d <= max; d++) {
      final vSnapshot = List<int>.from(v);
      for (var k = -d; k <= d; k += 2) {
        late int x;
        if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
          x = v[offset + k + 1];
        } else {
          x = v[offset + k - 1] + 1;
        }
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[offset + k] = x;
        if (x >= n && y >= m) {
          trace.add(vSnapshot);
          return _backtrack(trace, v, a, b, d, offset);
        }
      }
      trace.add(vSnapshot);
    }
    // Fallback (não deveria ocorrer): tratar tudo como substituição.
    return <_Op>[
      ...List<_Op>.filled(n, _Op.delete),
      ...List<_Op>.filled(m, _Op.insert),
    ];
  }

  static List<_Op> _backtrack(
    List<List<int>> trace,
    List<int> finalV,
    List<String> a,
    List<String> b,
    int dFinal,
    int offset,
  ) {
    final ops = <_Op>[];
    var x = a.length;
    var y = b.length;
    // Inclui o V final no trace lógico.
    final all = [...trace, List<int>.from(finalV)];

    for (var d = dFinal; d > 0; d--) {
      final v = all[d];
      final k = x - y;
      late int prevK;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = v[offset + prevK];
      final prevY = prevX - prevK;

      while (x > prevX && y > prevY) {
        ops.add(_Op.equal);
        x--;
        y--;
      }
      if (x == prevX) {
        ops.add(_Op.insert);
        y--;
      } else {
        ops.add(_Op.delete);
        x--;
      }
      x = prevX;
      y = prevY;
    }
    while (x > 0 && y > 0) {
      ops.add(_Op.equal);
      x--;
      y--;
    }
    while (x > 0) {
      ops.add(_Op.delete);
      x--;
    }
    while (y > 0) {
      ops.add(_Op.insert);
      y--;
    }
    return ops.reversed.toList(growable: false);
  }
}

enum _Op { equal, insert, delete }
