import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Estado vazio do painel detail no modo tablet — mostrado enquanto
/// nenhuma sessão foi selecionada (o app inicia assim, de propósito).
class DetailPlaceholder extends StatelessWidget {
  const DetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Opacity(
          opacity: 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.messagesSquare, color: kMuted, size: 56),
              SizedBox(height: 18),
              Text(
                'Select a session',
                style: TextStyle(
                  fontFamily: kMono,
                  color: kMuted2,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Pick a session on the left to open its chat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kMono,
                  color: kMuted,
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
