import 'dart:async';

import 'package:app/ui/app_theme.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/pairing/widgets/nickname_sheet.dart';
import 'package:app/ui/pairing/widgets/paste_qr_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// PairingPage — QR scanner + pair_request in one screen
// ---------------------------------------------------------------------------

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _scanner = MobileScannerController();
  bool _scannerActive = true;
  // Guards against [_runPostPairFlow] firing twice — `PairingPaired`
  // is rebroadcast on every `applyNickname` emit, and we only want to
  // open the sheet once per pairing.
  bool _postPairStarted = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scannerActive) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    _submitRaw(raw);
  }

  /// Common path for any QR payload — same whether it came from the
  /// camera (`_onDetect`) or the manual paste sheet. Disarms the
  /// scanner so we don't double-fire if the camera also catches it.
  void _submitRaw(String raw) {
    if (!_scannerActive) return;
    setState(() => _scannerActive = false);
    _scanner.stop();
    context.read<PairingViewModel>().onQrScanned(raw);
  }

  Future<void> _openPasteSheet() async {
    await showPasteQrSheet(context, onSubmit: _submitRaw);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PairingViewModel>();
    final state = vm.state;

    if (state is PairingPaired && !_postPairStarted) {
      _postPairStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_runPostPairFlow(state.hostnameHint));
      });
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, title: const Text('Pair device')),
      body: _buildBody(state, vm),
    );
  }

  /// Plan/27 Wave A — opens the post-pair nickname sheet, persists
  /// whatever the user picked, then navigates home. Modal is
  /// dismissible; either Save, Skip or drag-down all produce a usable
  /// label so the mesh blob carries a real string for other devices.
  Future<void> _runPostPairFlow(String? hostnameHint) async {
    final vm = context.read<PairingViewModel>();
    final nickname = await showNicknameSheet(
      context,
      defaultName: hostnameHint,
    );
    if (!mounted) return;
    await vm.applyNickname(nickname);
    if (!mounted) return;
    context.go('/home');
  }

  Widget _buildBody(PairingState state, PairingViewModel vm) {
    return switch (state) {
      PairingIdle() ||
      PairingScanning() ||
      PairingConnecting() => _buildScannerBody(state),
      PairingPaired() => const Center(
        child: CircularProgressIndicator(color: kAccent),
      ),
      PairingError(:final message, :final canRetry) => _ErrorView(
        message: message,
        canRetry: canRetry,
        onRetry: () {
          vm.retry();
          setState(() => _scannerActive = true);
          _scanner.start();
        },
      ),
    };
  }

  Widget _buildScannerBody(PairingState state) {
    final isConnecting = state is PairingConnecting;
    final sessionName = isConnecting ? state.sessionName : null;

    return Stack(
      children: [
        if (!isConnecting)
          MobileScanner(controller: _scanner, onDetect: _onDetect),
        Center(
          child: Container(
            width: 268,
            height: 268,
            decoration: BoxDecoration(
              color: isConnecting ? Colors.black54 : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder),
            ),
            child: isConnecting
                ? const Center(child: CircularProgressIndicator(color: kAccent))
                : _CornerBrackets(),
          ),
        ),
        if (!isConnecting) ..._cornerBrackets(),
        Positioned(
          bottom: isConnecting ? 48 : 110,
          left: 0,
          right: 0,
          child: Text(
            isConnecting
                ? 'Connecting to $sessionName…'
                : 'Point camera at the QR shown in your Mac terminal',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        if (!isConnecting)
          Positioned(
            bottom: 32,
            left: 32,
            right: 32,
            child: OutlinedButton.icon(
              onPressed: _openPasteSheet,
              icon: const Icon(LucideIcons.clipboardPaste,
                  size: 16, color: kAccent),
              label: const Text(
                "Can't scan? Paste code instead",
                style: TextStyle(
                  color: kAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.black54,
                side: const BorderSide(color: kAccent, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _cornerBrackets() {
    return [
      Align(alignment: const Alignment(-0.7, -0.4), child: _Bracket(rotate: 0)),
      Align(alignment: const Alignment(0.7, -0.4), child: _Bracket(rotate: 90)),
      Align(alignment: const Alignment(0.7, 0.4), child: _Bracket(rotate: 180)),
      Align(
        alignment: const Alignment(-0.7, 0.4),
        child: _Bracket(rotate: 270),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------

class _CornerBrackets extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Bracket extends StatelessWidget {
  final double rotate;
  const _Bracket({required this.rotate});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.14159 / 180,
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(painter: _BracketPainter(color: kAccent)),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(18, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, 18), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.circleAlert,
              color: Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted2, fontSize: 14),
            ),
            if (canRetry) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
