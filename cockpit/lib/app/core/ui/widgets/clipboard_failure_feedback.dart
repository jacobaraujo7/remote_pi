import 'dart:async';

import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../themes/themes.dart';

/// One feedback surface per window, including writes without a widget context.
class ClipboardFailureFeedback extends StatefulWidget {
  const ClipboardFailureFeedback({
    super.key,
    required this.child,
    this.service,
  });
  final Widget child;
  final TextClipboardService? service;

  @override
  State<ClipboardFailureFeedback> createState() =>
      _ClipboardFailureFeedbackState();
}

class _ClipboardFailureFeedbackState extends State<ClipboardFailureFeedback> {
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subscription = (widget.service ?? TextClipboardService.instance).failures
        .listen((_) {
          if (!mounted) return;
          setState(() => _failed = true);
          _timer?.cancel();
          _timer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _failed = false);
          });
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_failed)
        Positioned(
          right: 16,
          bottom: 16,
          child: IgnorePointer(
            child: Semantics(
              liveRegion: true,
              child: SurfaceCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    context.t.core.clipboard.writeFailed,
                    style: context.typo.label,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
