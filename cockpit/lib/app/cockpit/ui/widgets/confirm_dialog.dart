import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Cor do barrier (escurece o fundo) — o `showDialog` do shadcn usa barrier
/// transparente por padrão; aqui damos o leve dim que o modal pedia.

/// Dialog informativo genérico (tema do cockpit) — só botão "OK".
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? okLabel,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(okLabel ?? context.t.common.gotIt),
          ),
        ],
      );
    },
  );
}

/// Escolha do usuário ao fechar uma aba com alterações não salvas.
enum CloseDirtyChoice { cancel, dontSave, save }

/// Dialog ao fechar um arquivo editado e não salvo: descartar, cancelar ou
/// salvar e fechar. `null` (dispensar fora) é tratado como [CloseDirtyChoice.cancel].
Future<CloseDirtyChoice> showCloseDirtyDialog(
  BuildContext context, {
  required String fileName,
}) async {
  final result = await showDialog<CloseDirtyChoice>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final colors = context.colors;
      final tr = context.t.cockpit.confirmDialog;
      return AlertDialog(
        title: Text(
          tr.unsavedChangesTitle,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            tr.unsavedChangesMessage(fileName: fileName),
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          DestructiveButton(
            onPressed: () =>
                Navigator.of(context).pop(CloseDirtyChoice.dontSave),
            child: Text(tr.dontSave),
          ),
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(CloseDirtyChoice.cancel),
            child: Text(context.t.common.cancel),
          ),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(CloseDirtyChoice.save),
            child: Text(tr.saveAndClose),
          ),
        ],
      );
    },
  );
  return result ?? CloseDirtyChoice.cancel;
}

/// Dialog de confirmação genérico (tema do cockpit). Devolve `true` se confirmar.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final colors = context.colors;
      final confirm = confirmLabel ?? context.t.common.confirm;
      final cancel = cancelLabel ?? context.t.common.cancel;
      return AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancel),
          ),
          if (danger)
            DestructiveButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            )
          else
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            ),
        ],
      );
    },
  );
  return result ?? false;
}
