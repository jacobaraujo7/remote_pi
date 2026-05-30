import 'package:app/pairing/storage.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One row in the paired-peers list (Settings).
///
/// - Swipe end-to-start → [onRevokeRequested]. Caller confirms + deletes.
/// - Pencil icon → [onEditNickname].
/// - Title is `peer.nickname` when set, otherwise `peer.sessionName`. When
///   a nickname is present, the original session name appears beneath it
///   in muted style.
///
/// Settings does NOT switch the active peer anymore — Home does that via
/// [Preferences.selectedPeerEpk]. This widget is pure config.
class PeerListItem extends StatelessWidget {
  final PeerRecord peer;
  final Future<bool> Function() onRevokeRequested;
  final VoidCallback onEditNickname;

  const PeerListItem({
    super.key,
    required this.peer,
    required this.onRevokeRequested,
    required this.onEditNickname,
  });

  /// Platform hint for the secondary line (Mac / Linux / Windows / Pi
  /// OS). Pi-extension hasn't surfaced this yet; once it does
  /// (PairOk extension or a new field on PeerRecord), wire here and
  /// the slot lights up. Until then returns null and the row stays
  /// title-only.
  static String? _platformLabel(PeerRecord peer) {
    // ignore: dead_code
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final nickname = peer.nickname;
    final hasNickname = nickname != null && nickname.isNotEmpty;

    return Dismissible(
      key: ValueKey('peer-${peer.remoteEpk}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red.shade900,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trash2, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Revoke',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => onRevokeRequested(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
        decoration: const BoxDecoration(
          color: kBg,
          border: Border(bottom: BorderSide(color: kBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasNickname ? nickname : peer.sessionName,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasNickname) ...[
                    const SizedBox(height: 2),
                    Text(
                      peer.sessionName,
                      style: const TextStyle(
                        color: kMuted2,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Plan-17 follow-up — relay URL removed from the
                  // tile (it's the same for every peer post-plan-14
                  // global-relay refactor, so it added no signal).
                  // If/when the protocol surfaces platform (Mac /
                  // Linux / Windows / Pi OS), render it here; until
                  // then this slot stays empty.
                  if (_platformLabel(peer) != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _platformLabel(peer)!,
                      style: const TextStyle(
                        fontFamily: kMono,
                        fontSize: 11,
                        color: kMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit nickname',
              icon: const Icon(LucideIcons.pencil, size: 18),
              color: kMuted2,
              onPressed: onEditNickname,
            ),
          ],
        ),
      ),
    );
  }
}
