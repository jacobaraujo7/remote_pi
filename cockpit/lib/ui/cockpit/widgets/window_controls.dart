import 'dart:io';

import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Controles de janela **à esquerda** (convenção macOS): semáforo
/// fechar/minimizar/maximizar. Em plataformas não-macOS não renderiza nada —
/// no Windows os controles vão à direita via [WindowControlsTrailing].
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
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

/// Controles de janela **à direita** (convenção Windows/Linux): botões quadrados
/// minimizar/maximizar/fechar, com hover de fundo (fechar fica vermelho). No
/// macOS não renderiza nada (lá o semáforo fica à esquerda via [WindowControls]).
/// Posicione no fim da topbar.
class WindowControlsTrailing extends StatelessWidget {
  const WindowControlsTrailing({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onTap: windowManager.minimize,
        ),
        _WinButton(
          icon: Icons.crop_square,
          tooltip: 'Maximize',
          onTap: _toggleMaximize,
        ),
        _WinButton(
          icon: Icons.close,
          tooltip: 'Close',
          onTap: windowManager.close,
          danger: true,
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color? bg = _hover
        ? (widget.danger ? const Color(0xFFE81123) : colors.panel3)
        : null;
    final Color fg = _hover && widget.danger ? Colors.white : colors.text2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 46,
            color: bg ?? Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
