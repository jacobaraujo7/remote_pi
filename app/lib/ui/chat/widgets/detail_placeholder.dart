import 'package:app/i18n/strings.g.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Estado vazio do painel detail no modo tablet — mostrado enquanto
/// nenhuma sessão foi selecionada (o app inicia assim, de propósito).
class DetailPlaceholder extends StatelessWidget {
  const DetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Opacity(
          opacity: 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.messagesSquare, color: colors.muted, size: 56),
              const SizedBox(height: 18),
              Text(
                t.chat.selectSession,
                style: TextStyle(
                  fontFamily: kMonoFamily,
                  color: colors.muted2,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.chat.selectSessionDesc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kMonoFamily,
                  color: colors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
