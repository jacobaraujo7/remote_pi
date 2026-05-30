import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/app_theme.dart';
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

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(
            embedded ? LucideIcons.x : LucideIcons.chevronLeft,
            size: embedded ? 22 : 18,
            color: kText,
          ),
          tooltip: embedded ? 'Close' : 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: kBorder, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _RelaySection(),
          const Divider(color: kBorder, height: 1),
          const _DisplaySection(),
          const Divider(color: kBorder, height: 1),
          const _SectionHeader('Pairings'),
          switch (state) {
            SettingsLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(color: kAccent)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: OutlinedButton.icon(
        onPressed: () => context.push('/pair'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kAccent,
          side: const BorderSide(color: kBorder),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          minimumSize: const Size.fromHeight(0),
        ),
        icon: const Icon(LucideIcons.scanQrCode, size: 18),
        label: const Text(
          'Add new pairing',
          style: TextStyle(fontFamily: kMono, fontSize: 13),
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
    _ctrl = TextEditingController(text: vm.relayUrlOverride ?? '');
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
            style: TextStyle(fontFamily: kMono),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
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
                style: const TextStyle(
                  fontFamily: kMono,
                  fontSize: 13,
                  color: kText,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Default Relay ($kDefaultRelayUrl)',
                  hintStyle:
                      const TextStyle(fontFamily: kMono, color: kMuted, fontSize: 12),
                  helperText:
                      'http(s) only — the app converts to WebSocket '
                      'internally.',
                  helperStyle: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 10,
                    color: kMuted,
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 10,
                    color: Colors.redAccent,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: kBorder),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: kAccent),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Current: ${vm.effectiveRelayUrl}',
                style: const TextStyle(
                  fontFamily: kMono,
                  fontSize: 11,
                  color: kMuted,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontFamily: kMono, fontSize: 13),
                  ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Display'),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          activeThumbColor: kAccent,
          title: const Text(
            'Hide tool calls in chat',
            style: TextStyle(color: kText, fontSize: 14),
          ),
          subtitle: const Text(
            'Only show your messages and the assistant replies.',
            style: TextStyle(color: kMuted, fontSize: 12),
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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: kMuted,
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
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.monitorSmartphone, color: kMuted, size: 40),
          const SizedBox(height: 12),
          const Text(
            'No pairings yet',
            style: TextStyle(color: kMuted2, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap + to pair a new Mac.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/pair'),
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
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
