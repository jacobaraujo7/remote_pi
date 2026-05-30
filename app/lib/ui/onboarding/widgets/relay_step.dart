import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Empty custom URL is allowed — onboarding treats it as "use default
/// community relay" (saves null in Preferences, falls back to
/// [kDefaultRelayUrl] via [resolveRelayUrl]).

/// Onboarding step 2 — relay choice. Two vertical cards: self-hosted
/// (recommended for the privacy story) vs community (convenience).
/// The custom card carries a URL field with inline validation; leaving
/// it empty falls back to the default community relay.
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
    // Empty custom URL is allowed (treated as default community relay).
    if (state.customRelayUrl.isEmpty) return true;
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
            'Choose a relay',
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 16,
              color: kText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Where the app and your PC meet.',
            style: TextStyle(fontFamily: kMono, fontSize: 11, color: kMuted),
          ),
          const SizedBox(height: 24),
          _CustomRelayCard(
            badge: 'recommended',
            description: 'Self-hosted. Best privacy.',
            selected: state.relayChoice == RelayChoice.custom,
            customUrl: state.customRelayUrl,
            error: state.customRelayError,
            onTap: () => onChoice(RelayChoice.custom),
            onUrlChanged: onCustomUrl,
          ),
          const SizedBox(height: 12),
          _RelayCard(
            title: 'Community relay',
            description: 'Hosted by us. Quick to start.',
            footer: kDefaultRelayUrl,
            selected: state.relayChoice == RelayChoice.community,
            onTap: () => onChoice(RelayChoice.community),
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
  final String description;
  final String? footer;
  final bool selected;
  final VoidCallback onTap;
  const _RelayCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.footer,
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
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
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
                  height: 1.4,
                ),
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  footer!,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 10,
                    color: kMuted,
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

class _CustomRelayCard extends StatelessWidget {
  final bool selected;
  final String customUrl;
  final String? error;
  final String? badge;
  final String? description;
  final VoidCallback onTap;
  final ValueChanged<String> onUrlChanged;
  const _CustomRelayCard({
    required this.selected,
    required this.customUrl,
    required this.error,
    required this.onTap,
    required this.onUrlChanged,
    this.badge,
    this.description,
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
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 16,
                  color: selected ? kAccent : kMuted,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Use my own server',
                    style: TextStyle(
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
            if (description != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  description!,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 11,
                    color: kMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
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
                    hintText: 'https://my-relay.com',
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

