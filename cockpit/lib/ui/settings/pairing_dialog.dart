import 'dart:async';

import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/pairing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Dialog de pareamento: mostra os passos + QR Code do `/remote-pi pair`. Fecha
/// sozinho (retornando `true`) quando um aparelho parear — quem abriu recarrega
/// a lista. Consome o [PairingController] provido pelo `showDialog`.
class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

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
    _ctrl = context.read<PairingController>();
    _ctrl.addListener(_onChange);
  }

  void _onChange() {
    // Pareou → fecha o dialog sinalizando sucesso (o painel recarrega a lista).
    if (_ctrl.isPaired && mounted) Navigator.of(context).pop(true);
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
    final ctrl = context.watch<PairingController>();
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Parear aparelho',
                      style: context.typo.title.copyWith(
                        fontSize: 16,
                        color: colors.text,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.of(context).pop(false),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(Icons.close, size: 17, color: colors.text3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              switch (ctrl.stage) {
                PairStage.failed => _failed(context, ctrl),
                PairStage.showingCode => _code(context, ctrl),
                // paired é transitório (fecha sozinho) → mostra o "conectando".
                PairStage.connecting || PairStage.paired => _connecting(context),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _connecting(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Conectando ao relay…',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _code(BuildContext context, PairingController ctrl) {
    final colors = context.colors;
    final uri = ctrl.code!.uri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _step(context, 1, 'Abra o app Remote Pi no celular.'),
        _step(context, 2, 'Toque em adicionar / parear aparelho.'),
        _step(context, 3, 'Aponte a câmera para o QR abaixo.'),
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
                    'Não foi possível gerar o QR.',
                    textAlign: TextAlign.center,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _CopyButton(
          copied: _copied,
          onTap: () => _copy(uri),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.autorenew, size: 12, color: colors.text4),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'O código se renova sozinho. Mantenha esta janela aberta.',
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
        children: [
          Icon(Icons.error_outline, size: 30, color: colors.error),
          const SizedBox(height: 12),
          Text(
            ctrl.error ?? 'Falha no pareamento.',
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
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.text2,
                    side: BorderSide(color: colors.border2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Fechar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => ctrl.retry(),
                  child: const Text('Tentar de novo'),
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
    return Material(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                copied ? Icons.check : Icons.copy_outlined,
                size: 14,
                color: colors.accentText,
              ),
              const SizedBox(width: 8),
              Text(
                copied ? 'Copiado!' : 'Copiar dados',
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
