import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/ui/revoke_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog de progresso do revoke: carregando enquanto sobe o `pi --mode rpc` e
/// roda `/remote-pi revoke`, depois sucesso/erro com botão "Ok". Recebe o
/// [RevokeController] por construtor (quem abre descarta ao fechar).
class RevokeDialog extends StatelessWidget {
  const RevokeDialog({super.key, required this.controller});

  final RevokeController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _dialog(context),
  );

  Widget _dialog(BuildContext context) {
    final ctrl = controller;
    final colors = context.colors;
    final tr = context.t.settings.revokeDialog;

    return AlertDialog(
      padding: const EdgeInsets.all(24),
      content: ConstrainedBox(
        // 🟢 RESPONSIVIDADE AQUI:
        // minWidth: garante que em telas maiores o card não fique muito esmagado.
        // maxWidth: impede que o dialog estique excessivamente em monitores ultra-wide.
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Conteúdo de acordo com o estado atual
            switch (ctrl.stage) {
              RevokeStage.running => _running(context, ctrl),
              RevokeStage.done => _result(
                context,
                icon: Icons.check_circle_outline,
                color: colors.online,
                message: tr.deviceRemoved,
              ),
              RevokeStage.failed => _result(
                context,
                icon: Icons.error_outline,
                color: colors.error,
                message: ctrl.error ?? tr.failedToRevoke,
              ),
            },

            // Ação no rodapé
            if (ctrl.stage != RevokeStage.running) ...[
              const SizedBox(height: 20),
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr.ok),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _running(BuildContext context, RevokeController ctrl) {
    final colors = context.colors;
    final tr = context.t.settings.revokeDialog;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(size: 34),
        const SizedBox(height: 18),
        Text(
          ctrl.deviceName == null
              ? tr.revoking
              : tr.revokingDevice(name: ctrl.deviceName!),
          textAlign: TextAlign.center,
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr.connectingMessage,
          textAlign: TextAlign.center,
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      ],
    );
  }

  Widget _result(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String message,
  }) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text2,
          ),
        ),
      ],
    );
  }
}
