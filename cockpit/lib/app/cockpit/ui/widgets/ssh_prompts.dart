import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Confirmação TOFU de host key nova (plano 54, decisão G).
///
/// Aceitar cego seria MITM silencioso num túnel cuja razão de existir é
/// segurança — então a primeira conexão a um bastion sempre para aqui. Chave
/// **alterada** não passa por este dialog: é recusada no túnel, sem opção de
/// aceitar inline.
Future<HostKeyVerdict> showSshHostKeyDialog(
  BuildContext context, {
  required String endpoint,
  required String fingerprint,
}) async {
  final colors = context.colors;
  final typo = context.typo;
  final tr = context.t.cockpit.sshPrompts;
  final verdict = await showDialog<HostKeyVerdict>(
    context: context,
    builder: (context) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.gpp_maybe_outlined, size: 18, color: colors.text2),
              const SizedBox(width: 8),
              Text(
                tr.unknownSshHostTitle,
                style: typo.title.copyWith(fontSize: 15, color: colors.text),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.neverConnected(endpoint: endpoint),
                style: typo.label.copyWith(fontSize: 12, color: colors.text2),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  fingerprint,
                  style: typo.mono.copyWith(fontSize: 12, color: colors.text),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr.trustHint,
                style: typo.label.copyWith(fontSize: 11, color: colors.text3),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub',
                style: typo.mono.copyWith(fontSize: 11, color: colors.text3),
              ),
            ],
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(context).pop(HostKeyVerdict.reject),
              child: Text(context.t.common.cancel),
            ),
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(HostKeyVerdict.trust),
              child: Text(tr.trust),
            ),
          ],
        ),
      ),
    ),
  );
  // Fechar clicando fora = não confiar. O default nunca é o permissivo.
  return verdict ?? HostKeyVerdict.reject;
}

/// Pede a passphrase da chave quando ela não está no cofre. Vale pela sessão
/// (o serviço cacheia em memória) — é o equivalente do `ssh-add` pra quem não
/// quer guardar o segredo.
Future<String?> showSshPassphraseDialog(
  BuildContext context, {
  required String connectionName,
  required String keyPath,
}) async {
  final colors = context.colors;
  final typo = context.typo;
  final tr = context.t.cockpit.sshPrompts;
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AlertDialog(
            title: Text(
              tr.sshKeyPassphraseTitle,
              style: typo.title.copyWith(fontSize: 15, color: colors.text),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.unlockMessage(
                    keyPath: keyPath,
                    connectionName: connectionName,
                  ),
                  style: typo.label.copyWith(fontSize: 12, color: colors.text2),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (v) => Navigator.of(context).pop(v),
                  style: typo.mono.copyWith(fontSize: 12.5, color: colors.text),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr.keptInMemoryHint,
                  style: typo.label.copyWith(
                    fontSize: 10.5,
                    color: colors.text4,
                  ),
                ),
              ],
            ),
            actions: [
              GhostButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t.common.cancel),
              ),
              PrimaryButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(tr.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
