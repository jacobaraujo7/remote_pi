import 'dart:io' show Platform;

import 'package:app/config/dependencies.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Plan 23 — first-launch gate when the platform's key-sync surface
/// (iCloud Keychain on iOS, Google Backup / Block Store on Android) is
/// not available. The app cannot proceed without it because the Owner
/// Ed25519 keypair has no other persistence path.
class SyncRequiredPage extends StatefulWidget {
  const SyncRequiredPage({super.key});

  @override
  State<SyncRequiredPage> createState() => _SyncRequiredPageState();
}

class _SyncRequiredPageState extends State<SyncRequiredPage> {
  bool _checking = false;

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await injector.get<OwnerIdentityBridge>().boot();
    if (!mounted) return;
    setState(() => _checking = false);
    if (result is! SyncUnavailableResult) {
      // Bounce through /boot so the router's redirect logic re-evaluates
      // (pairs-empty → /onboarding, pairs-non-empty → /home).
      context.go('/boot');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final requirements = isIOS ? _iosRequirements : _androidRequirements;
    final why = isIOS
        ? 'Remote Pi keeps your Ed25519 owner key in iCloud Keychain so '
              'you can switch iPhones or pair your iPad without scanning '
              'a new QR.'
        : 'Remote Pi keeps your Ed25519 owner key in Google Block Store '
              'so you can restore it on a new device through Google '
              'Backup without losing your paired Pis.';

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                isIOS ? LucideIcons.cloudOff : LucideIcons.cloudUpload,
                color: kAccent,
                size: 44,
              ),
              const SizedBox(height: 20),
              const Text(
                'Sync required',
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: kText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                why,
                style: const TextStyle(
                  fontFamily: kMono,
                  fontSize: 12,
                  color: kMuted2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'To enable, on this device:',
                style: TextStyle(
                  fontFamily: kMono,
                  fontSize: 11,
                  color: kMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: requirements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _RequirementCard(
                    index: i + 1,
                    requirement: requirements[i],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _checking ? null : _recheck,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: kBorder,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ),
                child: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Check again',
                        style: TextStyle(
                          fontFamily: kMono,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Requirement {
  final String title;
  final String path;
  final String? note;
  const _Requirement({required this.title, required this.path, this.note});
}

const _androidRequirements = <_Requirement>[
  _Requirement(
    title: 'Set up a screen lock',
    path: 'Settings › Security › Screen lock',
    note: 'PIN, pattern or biometrics — required by Block Store.',
  ),
  _Requirement(
    title: 'Turn on Google Backup',
    path: 'Settings › System › Backup\n'
        '(Samsung: Settings › Accounts and backup › Backup data)',
  ),
  _Requirement(
    title: 'Sign in to a Google account',
    path: 'Settings › Passwords & accounts › Add account › Google',
  ),
];

const _iosRequirements = <_Requirement>[
  _Requirement(
    title: 'Sign in to iCloud',
    path: 'Settings › [your name]',
    note: 'If you see "Sign in to your iPhone" at the top, tap it.',
  ),
  _Requirement(
    title: 'Turn on iCloud Keychain',
    path: 'Settings › [your name] › iCloud › Passwords and Keychain',
    note: 'Toggle "Sync this iPhone" on.',
  ),
];

class _RequirementCard extends StatelessWidget {
  final int index;
  final _Requirement requirement;
  const _RequirementCard({required this.index, required this.requirement});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.all(Radius.circular(11)),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontFamily: kMono,
                fontSize: 11,
                color: kAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.title,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 13,
                    color: kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  requirement.path,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 11,
                    color: kMuted2,
                    height: 1.4,
                  ),
                ),
                if (requirement.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    requirement.note!,
                    style: const TextStyle(
                      fontFamily: kMono,
                      fontSize: 10.5,
                      color: kMuted,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
