import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Widget do dialog contendo as instruções para ativar as notificações no macOS.
class MacosNotificationInstructionsDialog extends StatelessWidget {
  const MacosNotificationInstructionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.core.macosNotifications;
    final stepStyle = context.typo.body.copyWith(
      fontSize: 13,
      color: colors.text2,
    );
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active, color: colors.accentText, size: 20),
          const SizedBox(width: 10),
          Text(
            tr.title,
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
            Text(tr.intro, style: stepStyle),
            const SizedBox(height: 14),
            _InstructionStep(
              step: '1',
              content: Text(tr.step1, style: stepStyle),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '2',
              content: Text(tr.step2, style: stepStyle),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '3',
              content: Text(tr.step3, style: stepStyle),
            ),
            const SizedBox(height: 8),
            _InstructionStep(
              step: '4',
              content: Text(tr.step4, style: stepStyle),
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
                      tr.tip,
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
          child: Text(tr.gotIt),
        ),
      ],
    );
  }

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: context.colors.scrim,
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
