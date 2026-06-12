import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Pane vazio ("Novo"): dois cards — "Novo agente" / "Novo terminal" — que
/// abrem o seletor de subpasta. Visual de card (ícone + título + descrição),
/// inspirado no launcher do Pi.
class EmptyPane extends StatelessWidget {
  const EmptyPane({
    super.key,
    required this.onNewAgent,
    required this.onNewTerminal,
  });

  final VoidCallback onNewAgent;
  final VoidCallback onNewTerminal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border2),
              ),
              child: Icon(Icons.auto_awesome, size: 20, color: colors.text3),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                _ActionCard(
                  icon: Icons.auto_awesome,
                  iconColor: colors.accentText,
                  title: 'New agent',
                  description: 'Runs a pi in the folder you choose',
                  onTap: onNewAgent,
                ),
                _ActionCard(
                  icon: Icons.terminal_outlined,
                  iconColor: colors.text2,
                  title: 'New terminal',
                  description: 'Opens a shell in the folder you choose',
                  onTap: onNewTerminal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card clicável (hover destaca o fundo e a borda).
class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 218,
          height: 142,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hover ? colors.panel3 : colors.panel2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? colors.border2 : colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 19, color: widget.iconColor),
              const Spacer(),
              Text(
                widget.title,
                style: typo.title.copyWith(fontSize: 15.5, color: colors.text),
              ),
              const SizedBox(height: 6),
              Text(
                widget.description,
                style: typo.label.copyWith(color: colors.text3, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
