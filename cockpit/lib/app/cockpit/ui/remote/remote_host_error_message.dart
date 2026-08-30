import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Traduz um [RemoteHostException] para a frase mostrada ao usuário (plano 58,
/// Wave 2). A mensagem nasce AQUI: `data/` produz só o tipo + `detail` cru;
/// stderr do ssh nunca é traduzido, entra interpolado. Mesmo padrão dos
/// tradutores de erro do `core/ui/`.
/// [host] é o nome/endereço mostrado na frase. Era um `'@'` hardcoded, o que
/// produzia "Não foi possível alcançar @ via SSH" — a mensagem nunca dizia de
/// QUAL host falava.
String remoteHostErrorMessage(
  BuildContext context,
  RemoteHostException error, {
  String host = '',
}) {
  final tr = context.t.cockpit.remoteHost;
  final base = switch (error.kind) {
    RemoteHostErrorKind.sshUnreachable => tr.errSshUnreachable(host: host),
    RemoteHostErrorKind.serverInstallFailed => tr.errInstallFailed(host: host),
    RemoteHostErrorKind.versionMismatch => tr.errVersionMismatch,
    RemoteHostErrorKind.protocol => tr.errInstallFailed(host: host),
    RemoteHostErrorKind.hostKeyUnknown => tr.errHostKeyUnknown(host: host),
    RemoteHostErrorKind.hostKeyChanged => tr.errHostKeyChanged(host: host),
    RemoteHostErrorKind.hostBundleMissing => tr.errHostBundleMissing(
      host: host,
    ),
    RemoteHostErrorKind.hostUnknownOs => tr.errHostUnknownOs(host: host),
  };
  // Chave trocada tem stderr gigante do ssh (o bloco "REMOTE HOST
  // IDENTIFICATION HAS CHANGED", com arte ASCII) — a frase traduzida já diz o
  // que fazer, e colar aquilo dentro dela só piora a leitura.
  if (error.kind == RemoteHostErrorKind.hostKeyChanged) return base;
  final detail = error.detail?.trim();
  if (detail == null || detail.isEmpty) return base;
  return '$base ${tr.errDetail(detail: detail)}';
}

/// Rótulo curto da fase de conexão (loading progressivo por etapa).
String remoteHostPhaseLabel(BuildContext context, RemoteHostPhase phase) {
  final tr = context.t.cockpit.remoteHost;
  return switch (phase) {
    RemoteHostPhase.idle || RemoteHostPhase.openingTunnel => tr.openingTunnel,
    RemoteHostPhase.installingServer => tr.installingServer,
    RemoteHostPhase.connecting => tr.loadingWorkspace,
    RemoteHostPhase.connected => tr.loadingWorkspace,
    RemoteHostPhase.reconnecting => tr.reconnecting(host: ''),
    RemoteHostPhase.failed => tr.offline(host: ''),
  };
}
