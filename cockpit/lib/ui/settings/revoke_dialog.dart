import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/revoke_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Dialog de progresso do revoke: carregando enquanto sobe o `pi --mode rpc` e
/// roda `/remote-pi revoke`, depois sucesso/erro com botão "Ok". Consome o
/// [RevokeController] provido pelo `showDialog`.
class RevokeDialog extends StatelessWidget {
  const RevokeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RevokeController>();
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: switch (ctrl.stage) {
            RevokeStage.running => _running(context, ctrl),
            RevokeStage.done => _result(
              context,
              icon: Icons.check_circle_outline,
              color: colors.online,
              message: 'Aparelho removido.',
            ),
            RevokeStage.failed => _result(
              context,
              icon: Icons.error_outline,
              color: colors.error,
              message: ctrl.error ?? 'Falha ao revogar o aparelho.',
            ),
          },
        ),
      ),
    );
  }

  Widget _running(BuildContext context, RevokeController ctrl) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.accent),
        ),
        const SizedBox(height: 18),
        Text(
          ctrl.deviceName == null
              ? 'Revogando…'
              : 'Revogando ${ctrl.deviceName}…',
          textAlign: TextAlign.center,
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        const SizedBox(height: 6),
        Text(
          'Conectando ao relay e removendo o acesso.',
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
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ok'),
          ),
        ),
      ],
    );
  }
}
