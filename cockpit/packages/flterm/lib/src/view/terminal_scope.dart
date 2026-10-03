import 'package:flutter/widgets.dart';

import '../rendering/atlas_pool.dart';

/// Returns the shared terminal atlas pool nearest to [context], if any.
AtlasPool? terminalScopeAtlasPoolOf(BuildContext context) {
  return context
      .dependOnInheritedWidgetOfExactType<_TerminalScopeInherited>()
      ?.atlasPool;
}

/// Shares terminal resources across descendant [TerminalView] widgets.
///
/// Wrapping multiple terminals in the same scope lets compatible renderers
/// reuse compatible glyph atlases. Terminals outside a scope create an
/// isolated local scope automatically.
class TerminalScope extends StatefulWidget {
  final Widget child;

  const TerminalScope({super.key, required this.child});

  @override
  State<TerminalScope> createState() => _TerminalScopeState();
}

final class _TerminalScopeState extends State<TerminalScope> {
  final _atlasPool = AtlasPool();

  @override
  Widget build(BuildContext context) {
    return _TerminalScopeInherited(atlasPool: _atlasPool, child: widget.child);
  }

  @override
  void dispose() {
    _atlasPool.dispose();
    super.dispose();
  }
}

final class _TerminalScopeInherited extends InheritedWidget {
  final AtlasPool atlasPool;

  const _TerminalScopeInherited({
    required this.atlasPool,
    required super.child,
  });

  @override
  bool updateShouldNotify(_TerminalScopeInherited oldWidget) {
    return !identical(atlasPool, oldWidget.atlasPool);
  }
}
