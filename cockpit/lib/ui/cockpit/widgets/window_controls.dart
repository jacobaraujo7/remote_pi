import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Semáforo macOS funcional (fechar/minimizar/maximizar). Os símbolos aparecem
/// ao passar o mouse no cluster. Usado na topbar do shell e no header da tela
/// cheia de Configurações (que substitui a topbar no push).
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _hover = false;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          _light(const Color(0xFFFF5F57), Icons.close, windowManager.close),
          const SizedBox(width: 8),
          _light(
            const Color(0xFFFEBC2E),
            Icons.remove,
            windowManager.minimize,
          ),
          const SizedBox(width: 8),
          _light(const Color(0xFF28C840), Icons.add, _toggleMaximize),
        ],
      ),
    );
  }

  Widget _light(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 12,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: _hover
              ? Icon(icon, size: 8, color: Colors.black.withValues(alpha: 0.55))
              : null,
        ),
      ),
    );
  }
}
