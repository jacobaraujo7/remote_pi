import 'dart:async';
import 'package:cockpit/app/core/ui/widgets/bootstrapper.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Plano 46 — inicializa o media_kit (libmpv) antes de qualquer Player.
  MediaKit.ensureInitialized();

  runApp(const CockpitBootstrapper());
}

/// Ouve redimensionamentos e persiste o tamanho da janela com debounce.
class WindowStateKeeper extends StatefulWidget {
  const WindowStateKeeper({super.key, required this.box, required this.child});
  final Box<dynamic> box;
  final Widget child;

  @override
  State<WindowStateKeeper> createState() => WindowStateKeeperState();
}

class WindowStateKeeperState extends State<WindowStateKeeper>
    with WindowListener {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() => _persistBounds();

  @override
  void onWindowMove() => _persistBounds();

  /// Persiste tamanho + posição (bounds completos) com debounce. Um único
  /// caminho para resize e move — ambos alteram os bounds que restauramos no
  /// próximo boot.
  void _persistBounds() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final bounds = await windowManager.getBounds();
      await widget.box.putAll({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
