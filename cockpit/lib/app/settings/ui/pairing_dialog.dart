import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/ui/pairing_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog de pareamento: mostra os passos + QR Code do `/remote-pi pair`. Fecha
/// sozinho (retornando `true`) quando um aparelho parear — quem abriu recarrega
/// a lista. Recebe o [PairingController] por construtor (quem abre é dono do
/// ciclo de vida → descarta ao fechar).
class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key, required this.controller});

  final PairingController controller;

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  late final PairingController _ctrl;
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller;
    _ctrl.addListener(_onChange);
  }

  void _onChange() {
    // Pareou → fecha o dialog sinalizando sucesso (o painel recarrega a lista).
    if (_ctrl.isPaired && mounted) {
      Navigator.of(context).pop(true);
      return;
    }
    // Reage às mudanças de estágio (showingCode → connecting → failed).
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String data) async {
    await Clipboard.setData(ClipboardData(text: data));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final colors = context.colors;

    return AlertDialog(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.t.settings.pairingDialog.title,
                style: context.typo.title.copyWith(
                  fontSize: 16,
                  color: colors.text,
                ),
              ),
            ),
            IconButton.ghost(
              icon: Icon(Icons.close, size: 17, color: colors.text3),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: switch (ctrl.stage) {
          PairStage.failed => _failed(context, ctrl),
          PairStage.showingCode => _code(context, ctrl),
          // paired é transitório (fecha sozinho) → mostra o "conectando".
          PairStage.connecting || PairStage.paired => _connecting(context),
        },
      ),
    );
  }

  Widget _connecting(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(size: 34),
            const SizedBox(height: 18),
            Text(
              context.t.settings.pairingDialog.connectingToRelay,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _code(BuildContext context, PairingController ctrl) {
    final colors = context.colors;
    final uri = ctrl.code!.uri;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _step(context, 1, context.t.settings.pairingDialog.step1),
        _step(context, 2, context.t.settings.pairingDialog.step2),
        _step(context, 3, context.t.settings.pairingDialog.step3),
        const SizedBox(height: 18),
        Center(
          child: Container(
            // Branco fixo: o QR precisa de contraste pra ser lido — não é tema.
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: uri,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              errorStateBuilder: (ctx, err) => SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: Text(
                    context.t.settings.pairingDialog.qrGenerationFailed,
                    textAlign: TextAlign.center,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _CopyButton(copied: _copied, onTap: () => _copy(uri)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.autorenew, size: 12, color: colors.text4),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.t.settings.pairingDialog.autoRefreshHint,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _failed(BuildContext context, PairingController ctrl) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 30, color: colors.error),
          const SizedBox(height: 12),
          Text(
            ctrl.error ?? context.t.settings.pairingDialog.pairingFailed,
            textAlign: TextAlign.center,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlineButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.t.common.close),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  onPressed: () => ctrl.retry(),
                  child: Text(context.t.settings.pairingDialog.tryAgain),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, int n, String text) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$n',
              style: context.typo.label.copyWith(
                color: colors.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onTap});
  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SecondaryButton(
      onPressed: onTap,
      leading: Icon(
        copied ? Icons.check : Icons.copy_outlined,
        size: 14,
        color: colors.accentText,
      ),
      child: Text(
        copied
            ? context.t.settings.pairingDialog.copied
            : context.t.settings.pairingDialog.copyData,
        style: context.typo.body.copyWith(
          fontSize: 13,
          color: colors.accentText,
        ),
      ),
    );
  }
}
