import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:app/ui/settings/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  /// Plan/tablet — `true` when presented as a modal bottom sheet (tablet)
  /// rather than a pushed full-screen route (phone). Swaps the back arrow
  /// for a close (X), since the sheet is dismissed, not popped to a parent.
  final bool embedded;

  const SettingsPage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final state = vm.state;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(
            embedded ? LucideIcons.x : LucideIcons.chevronLeft,
            size: embedded ? 22 : 18,
            color: colors.text,
          ),
          tooltip: embedded ? 'Close' : 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: colors.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _RelaySection(),
          Divider(color: colors.border, height: 1),
          const _DisplaySection(),
          Divider(color: colors.border, height: 1),
          const _SectionHeader('Pairings'),
          switch (state) {
            SettingsLoading() => Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: colors.accent),
              ),
            ),
            SettingsNoPeer() => const _EmptyState(),
            SettingsList(:final peers) => _PeerList(
              peers: peers,
              onRevoke: vm.revoke,
              onSetNickname: vm.setNickname,
            ),
          },
          // Plan-17 follow-up — entry point to pair an additional Pi.
          // The flow itself lives at /pair and survives whatever
          // peers/rooms already exist (PairingViewModel handles the
          // add path the same way as the first pair).
          const _AddPairingButton(),
        ],
      ),
    );
  }
}

class _AddPairingButton extends StatelessWidget {
  const _AddPairingButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: OutlinedButton.icon(
        onPressed: () => context.push('/pair'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accent,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          minimumSize: const Size.fromHeight(0),
        ),
        icon: const Icon(LucideIcons.scanQrCode, size: 18),
        label: Text(
          'Add new pairing',
          style: const TextStyle(fontFamily: kMonoFamily, fontSize: 13),
        ),
      ),
    );
  }
}

class _RelaySection extends StatefulWidget {
  const _RelaySection();
  @override
  State<_RelaySection> createState() => _RelaySectionState();
}

class _RelaySectionState extends State<_RelaySection> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final vm = context.read<SettingsViewModel>();
    _ctrl = TextEditingController(text: vm.relayUrlOverride);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vm = context.read<SettingsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final err = await vm.saveRelayUrl(_ctrl.text);
    if (!mounted) return;
    setState(() => _error = err);
    if (err == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Relay updated',
            style: TextStyle(fontFamily: kMonoFamily),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Relay'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                style: context.typo.mono.copyWith(
                  fontSize: 13,
                  color: colors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'https://my-relay.example.com',
                  hintStyle: context.typo.mono.copyWith(
                    color: colors.muted,
                    fontSize: 12,
                  ),
                  helperText: 'Current: ${vm.effectiveRelayUrl}',
                  helperStyle: context.typo.mono.copyWith(
                    fontSize: 10,
                    color: colors.muted,
                  ),
                  errorText: _error,
                  errorStyle: context.typo.mono.copyWith(
                    fontSize: 10,
                    color: colors.error,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                      ),
                      child: Text(
                        'Save',
                        style: const TextStyle(
                          fontFamily: kMonoFamily,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        _ctrl.text = kDefaultRelayUrl;
                        _save();
                      },
                      child: Text(
                        'Use default Relay',
                        style: const TextStyle(
                          fontFamily: kMonoFamily,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisplaySection extends StatelessWidget {
  const _DisplaySection();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<Preferences>();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Display'),
        // Theme mode — System follows the OS; Light / Dark pin it.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theme',
                style: context.typo.sansBody.copyWith(color: colors.text),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {prefs.themeMode},
                  onSelectionChanged: (s) => prefs.setThemeMode(s.first),
                ),
              ),
            ],
          ),
        ),
        // Text size — the app hardcodes its font sizes and Flutter can't read
        // iOS's per-app Text Size, so without this the only way to enlarge chat
        // text is the OS-wide accessibility setting (issue #114).
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Text size',
                style: context.typo.sansBody.copyWith(color: colors.text),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppFontScale>(
                  showSelectedIcon: false,
                  segments: [
                    for (final scale in AppFontScale.values)
                      ButtonSegment(value: scale, label: Text(scale.label)),
                  ],
                  selected: {prefs.fontScale},
                  onSelectionChanged: (s) => prefs.setFontScale(s.first),
                ),
              ),
            ],
          ),
        ),
        const _NotificationToggle(),

        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          activeThumbColor: colors.accent,
          title: Text(
            'Hide tool calls in chat',
            style: context.typo.sansBody.copyWith(color: colors.text),
          ),
          subtitle: Text(
            'Only show your messages and the assistant replies.',
            style: context.typo.sansBody.copyWith(
              color: colors.muted,
              fontSize: 12,
            ),
          ),
          value: prefs.hideToolCalls,
          onChanged: (v) => prefs.setHideToolCalls(v),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.muted,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.monitorSmartphone, color: colors.muted, size: 40),
          const SizedBox(height: 12),
          Text(
            'No pairings yet',
            style: TextStyle(color: colors.muted2, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to pair a new Mac.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/pair'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
            ),
            icon: const Icon(LucideIcons.scanQrCode, size: 18),
            label: const Text('Scan QR'),
          ),
        ],
      ),
    );
  }
}

class _PeerList extends StatelessWidget {
  final List<PeerRecord> peers;
  final Future<void> Function(String epk) onRevoke;
  final Future<void> Function(String epk, String? nickname) onSetNickname;

  const _PeerList({
    required this.peers,
    required this.onRevoke,
    required this.onSetNickname,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final peer in peers)
          PeerListItem(
            peer: peer,
            onEditNickname: () => _editNickname(context, peer),
            onRevokeRequested: () async {
              final confirmed = await showRevokeConfirmDialog(
                context,
                peer: peer,
              );
              if (!confirmed) return false;
              await onRevoke(peer.remoteEpk);
              return true;
            },
          ),
      ],
    );
  }

  Future<void> _editNickname(BuildContext context, PeerRecord peer) async {
    final result = await showNicknameEditor(
      context,
      defaultName: peer.sessionName,
      currentNickname: peer.nickname ?? '',
    );
    if (result == null) return; // canceled
    await onSetNickname(peer.remoteEpk, result.isEmpty ? null : result);
  }
}

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<Preferences>();
    final vm = context.read<SettingsViewModel>();
    final colors = context.colors;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      activeThumbColor: colors.accent,
      title: Text(
        'Enable notifications',
        style: context.typo.sansBody.copyWith(color: colors.text),
      ),
      subtitle: Builder(
        builder: (context) {
          if (!prefs.notificationsEnabled) {
            return Text(
              'Alert me when an agent finishes a turn in a session I\'m not watching.',
              style: context.typo.sansBody.copyWith(
                color: colors.muted,
                fontSize: 12,
              ),
            );
          }
          return FutureBuilder<bool?>(
            future: vm.hasNotificationPermission,
            builder: (context, snap) {
              final blocked = snap.data == false;
              return Text(
                blocked
                    ? 'Notifications are blocked at the system level. Open your device settings to grant permission.'
                    : 'Alert me when an agent finishes a turn in a session I\'m not watching.',
                style: context.typo.sansBody.copyWith(
                  color: blocked ? colors.error : colors.muted,
                  fontSize: 12,
                ),
              );
            },
          );
        },
      ),
      value: prefs.notificationsEnabled,
      onChanged: (v) => prefs.setNotificationsEnabled(v),
    );
  }
}
