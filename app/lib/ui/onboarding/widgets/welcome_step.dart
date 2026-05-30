import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Onboarding step 1 — welcome. Static, no animations (per plan 14 D2 —
/// "Welcome conservador (sem animações)").
class WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  const WelcomeStep({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(LucideIcons.terminal, color: kAccent, size: 64),
          const SizedBox(height: 32),
          const Text(
            'Remote Pi',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 24,
              color: kText,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Control your Pi agent from anywhere',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 13,
              color: kMuted,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Pair this app with the Pi running on your computer '
            '(Mac, Linux, or Windows) so you can chat with it even '
            'when you\'re away from home.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 12,
              color: kMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ),
            child: const Text(
              'Get started',
              style: TextStyle(
                fontFamily: kMono,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
