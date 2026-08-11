import 'package:flutter/widgets.dart';

/// Variante de [ListenableBuilder] que deixa de ouvir enquanto a apresentação
/// está fora de cena, sem desmontar a subárvore nem perder seu estado de view.
///
/// Os workspaces e tabs do Cockpit ficam montados em `IndexedStack`. Isso
/// preserva scroll, seleção e rascunho, mas um listener comum também reconstruía
/// Markdown de agentes invisíveis a cada token. Ao reativar, um rebuild lê o
/// estado mais recente acumulado no modelo.
class ActiveListenableBuilder extends StatefulWidget {
  const ActiveListenableBuilder({
    super.key,
    required this.listenable,
    required this.active,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final bool active;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<ActiveListenableBuilder> createState() =>
      _ActiveListenableBuilderState();
}

class _ActiveListenableBuilderState extends State<ActiveListenableBuilder> {
  @override
  void initState() {
    super.initState();
    if (widget.active) widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ActiveListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active &&
        (!widget.active || oldWidget.listenable != widget.listenable)) {
      oldWidget.listenable.removeListener(_changed);
    }
    if (widget.active &&
        (!oldWidget.active || oldWidget.listenable != widget.listenable)) {
      widget.listenable.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted && widget.active) setState(() {});
  }

  @override
  void dispose() {
    if (widget.active) widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
