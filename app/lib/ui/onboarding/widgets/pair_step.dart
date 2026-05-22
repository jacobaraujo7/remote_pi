import 'package:app/ui/app_theme.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

/// Onboarding step 3 — embeds the existing pairing flow. Watches the
/// already-registered `PairingViewModel` (Provider) and notifies the
/// onboarding flow when `pair_ok` lands.
class PairStep extends StatefulWidget {
  final VoidCallback onPaired;
  final VoidCallback onBack;
  const PairStep({super.key, required this.onPaired, required this.onBack});

  @override
  State<PairStep> createState() => _PairStepState();
}

class _PairStepState extends State<PairStep> {
  final _scanner = MobileScannerController();
  bool _scannerActive = true;
  PairingState? _lastObserved;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture, PairingViewModel vm) {
    if (!_scannerActive) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      _scannerActive = false;
      // ignore: unawaited_futures
      _scanner.stop();
      vm.onQrScanned(raw);
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PairingViewModel>();
    final state = vm.state;

    // Detect transition into PairingPaired and notify parent. Done once.
    if (state is PairingPaired && _lastObserved is! PairingPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPaired();
      });
    }
    _lastObserved = state;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Connect to your device',
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 16,
              color: kText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'On your computer (Mac, Linux, or Windows), open Pi and run:',
            style: TextStyle(fontFamily: kMono, fontSize: 11, color: kMuted),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kBg,
              border: Border.all(color: kBorder),
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: const Text(
              '/remote-pi pair',
              style: TextStyle(
                fontFamily: kMono,
                fontSize: 13,
                color: kAccent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scan the QR code that appears:',
            style: TextStyle(fontFamily: kMono, fontSize: 11, color: kMuted),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: _buildScannerBody(state, vm),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: widget.onBack,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildScannerBody(PairingState state, PairingViewModel vm) {
    if (state is PairingScanning) {
      return Stack(
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (capture) => _onDetect(capture, vm),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: kAccent, width: 2),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ],
      );
    }
    if (state is PairingConnecting) {
      return _StatusOverlay(
        icon: Icons.sync_rounded,
        message: 'Pairing…',
      );
    }
    if (state is PairingError) {
      return _StatusOverlay(
        icon: Icons.error_outline_rounded,
        message: state.message,
        actionLabel: state.canRetry ? 'Try again' : null,
        onAction: state.canRetry
            ? () {
                _scannerActive = true;
                _scanner.start();
                vm.retry();
              }
            : null,
      );
    }
    if (state is PairingPaired) {
      return _StatusOverlay(
        icon: Icons.check_circle_outline_rounded,
        message: 'Paired!',
      );
    }
    return const SizedBox.shrink();
  }
}

class _StatusOverlay extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _StatusOverlay({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kAccent, size: 40),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontFamily: kMono, fontSize: 12, color: kText),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontFamily: kMono, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
