import 'package:flutter/widgets.dart';

/// Estado global da janela usado apenas para suspender trabalho visual e de
/// reconciliação. Não governa processos, PTYs nem streams RPC.
class WindowActivityController extends ChangeNotifier {
  bool _focused = true;
  bool _minimized = false;

  bool get isActive => _focused && !_minimized;

  // A focused window is restored even when the native restore event is missed.
  void focus() => _update(focused: true, minimized: false);

  void blur() => _update(focused: false);

  void minimize() => _update(minimized: true);

  void restore() => _update(minimized: false);

  void synchronize(WindowActivitySnapshot snapshot) =>
      _update(focused: snapshot.focused, minimized: snapshot.minimized);

  void _update({bool? focused, bool? minimized}) {
    final wasActive = isActive;
    if (focused != null) _focused = focused;
    if (minimized != null) _minimized = minimized;
    if (wasActive != isActive) notifyListeners();
  }
}

class WindowActivitySnapshot {
  const WindowActivitySnapshot({
    required this.focused,
    required this.minimized,
  });

  final bool focused;
  final bool minimized;
}

/// Junta o snapshot nativo inicial aos eventos da janela sem permitir que uma
/// leitura assíncrona antiga sobrescreva blur/minimize recebido nesse intervalo.
class WindowActivitySynchronizer {
  WindowActivitySynchronizer({
    required this.activity,
    required this.readSnapshot,
  });

  final WindowActivityController activity;
  final Future<WindowActivitySnapshot> Function() readSnapshot;
  int _eventVersion = 0;

  Future<void> synchronize() async {
    final version = _eventVersion;
    try {
      final snapshot = await readSnapshot();
      if (version == _eventVersion) activity.synchronize(snapshot);
    } on Object {
      // Falha ao consultar o plugin não invalida eventos já observados.
    }
  }

  void focus() {
    _eventVersion++;
    activity.focus();
  }

  void blur() {
    _eventVersion++;
    activity.blur();
  }

  void minimize() {
    _eventVersion++;
    activity.minimize();
  }

  void restore() {
    _eventVersion++;
    activity.restore();
  }
}

/// Torna a mesma instância disponível para widgets sem acoplar o core a uma
/// feature ou exigir que testes pequenos montem o grafo completo de DI.
class WindowActivityScope extends InheritedNotifier<WindowActivityController> {
  const WindowActivityScope({
    super.key,
    required WindowActivityController controller,
    required super.child,
  }) : super(notifier: controller);

  static WindowActivityController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WindowActivityScope>()
      ?.notifier;
}

/// Fronteira visual do app: [TickerMode] pausa apenas animações/tickers. O
/// subtree permanece montado, portanto subscriptions de PTY/RPC seguem ativas.
class WindowActivityBoundary extends StatelessWidget {
  const WindowActivityBoundary({
    super.key,
    required this.activity,
    required this.child,
  });

  final WindowActivityController activity;
  final Widget child;

  @override
  Widget build(BuildContext context) => WindowActivityScope(
    controller: activity,
    child: ListenableBuilder(
      listenable: activity,
      child: child,
      builder: (context, child) =>
          TickerMode(enabled: activity.isActive, child: child!),
    ),
  );
}
