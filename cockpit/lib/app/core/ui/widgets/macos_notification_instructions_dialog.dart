import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const Color _barrier = Color(0x99000000);

/// Widget do dialog contendo as instruções para ativar as notificações no macOS.
class MacosNotificationInstructionsDialog extends StatelessWidget {
  const MacosNotificationInstructionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active, color: colors.accentText, size: 20),
          const SizedBox(width: 10),
          Text(
            'Enable Notifications on macOS',
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications are currently disabled in your system settings. Follow the steps below to enable them:',
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
            const SizedBox(height: 14),
            _InstructionStep(
              step: '1',
              content: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Open '),
                    TextSpan(
                      text: 'System Settings',
                      style: context.typo.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    const TextSpan(text: ' on your Mac.'),
                  ],
                ),
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '2',
              content: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Navigate to the '),
                    TextSpan(
                      text: 'Notifications',
                      style: context.typo.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    const TextSpan(text: ' section in the left sidebar.'),
                  ],
                ),
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '3',
              content: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Find and select the '),
                    TextSpan(
                      text: 'Cockpit',
                      style: context.typo.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    const TextSpan(text: ' application from the list.'),
                  ],
                ),
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '4',
              content: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Toggle the '),
                    TextSpan(
                      text: 'Allow Notifications',
                      style: context.typo.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                    const TextSpan(text: ' switch on.'),
                  ],
                ),
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.panel3,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: colors.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: If the app does not appear in the list, close and reopen it to trigger its registration in the system.',
                      style: context.typo.label.copyWith(
                        color: colors.text3,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: _barrier,
      builder: (context) => const MacosNotificationInstructionsDialog(),
    );
  }
}

/// Widget privado para renderizar cada linha de instrução com o número do passo.
class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.step, required this.content});

  final String step;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentText.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: context.typo.label.copyWith(
              color: colors.accentText,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: content),
      ],
    );
  }
}
