import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:flutter/material.dart';

/// Onboarding step 2 — relay choice. Two vertical cards (per plan 14
/// D2): community (recommended, pre-selected) vs custom (URL field
/// with inline validation).
class RelayStep extends StatelessWidget {
  final OnboardingInProgress state;
  final ValueChanged<RelayChoice> onChoice;
  final ValueChanged<String> onCustomUrl;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const RelayStep({
    super.key,
    required this.state,
    required this.onChoice,
    required this.onCustomUrl,
    required this.onBack,
    required this.onNext,
  });

  bool get _canContinue {
    if (state.relayChoice == RelayChoice.community) return true;
    return isValidRelayUrl(state.customRelayUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Choose the relay server',
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 16,
              color: kText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The relay forwards messages between the app and the Pi.',
            style: TextStyle(fontFamily: kMono, fontSize: 11, color: kMuted),
          ),
          const SizedBox(height: 24),
          _RelayCard(
            title: 'Community relay',
            badge: 'recommended',
            description: kDefaultRelayUrl,
            selected: state.relayChoice == RelayChoice.community,
            onTap: () => onChoice(RelayChoice.community),
          ),
          const SizedBox(height: 12),
          _CustomRelayCard(
            selected: state.relayChoice == RelayChoice.custom,
            customUrl: state.customRelayUrl,
            error: state.customRelayError,
            onTap: () => onChoice(RelayChoice.custom),
            onUrlChanged: onCustomUrl,
          ),
          const Spacer(),
          Row(
            children: [
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kMuted,
                  side: const BorderSide(color: kBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontFamily: kMono, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canContinue ? onNext : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: kBorder,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: kMono,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RelayCard extends StatelessWidget {
  final String title;
  final String? badge;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  const _RelayCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kBg,
          border: Border.all(
            color: selected ? kAccent : kBorder,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: selected ? kAccent : kMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 13,
                      color: kText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.15),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(4)),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontFamily: kMono,
                        fontSize: 9,
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                description,
                style: const TextStyle(
                  fontFamily: kMono,
                  fontSize: 11,
                  color: kMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomRelayCard extends StatelessWidget {
  final bool selected;
  final String customUrl;
  final String? error;
  final VoidCallback onTap;
  final ValueChanged<String> onUrlChanged;
  const _CustomRelayCard({
    required this.selected,
    required this.customUrl,
    required this.error,
    required this.onTap,
    required this.onUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kBg,
          border: Border.all(
            color: selected ? kAccent : kBorder,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: selected ? kAccent : kMuted,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Use my own server',
                  style: TextStyle(
                    fontFamily: kMono,
                    fontSize: 13,
                    color: kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: TextField(
                  controller: TextEditingController(text: customUrl)
                    ..selection = TextSelection.fromPosition(
                      TextPosition(offset: customUrl.length),
                    ),
                  onChanged: onUrlChanged,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 12,
                    color: kText,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'wss://my-relay.example.com',
                    hintStyle:
                        const TextStyle(fontFamily: kMono, color: kMuted),
                    errorText: error,
                    errorStyle: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 10,
                      color: Colors.redAccent,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kAccent),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
