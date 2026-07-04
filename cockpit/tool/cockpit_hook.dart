// Helper instalado nos hooks do Claude Code (~/.claude/settings.json) pelo
// `ClaudeHookInstaller` do Cockpit. O Claude o invoca a cada evento de ciclo de
// vida, passando um JSON pelo stdin. Traduzimos o evento num status de turno
// (working / waiting / idle) e mandamos pro Cockpit por um **socket Unix**.
//
// Por que socket e não OSC na PTY: o Claude roda os hooks SEM terminal
// controlador (escrever em /dev/tty falha com ENXIO). Então o app injeta no env
// da PTY o `COCKPIT_PANE_ID` (roteamento) e o `COCKPIT_STATUS_SOCK` (caminho do
// socket); o hook herda os dois e reporta o status por ali. Sessões `claude`
// fora do Cockpit não têm essas envs → o hook é no-op (gate natural).
//
// Compilar: dart compile exe tool/cockpit_hook.dart -o <dest>/cockpit-hook
// NÃO escreve no stdout (participa do protocolo de hook). Nunca falha barulhento.

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  try {
    final env = Platform.environment;
    final paneId = env['COCKPIT_PANE_ID'];
    if (paneId == null || paneId.isEmpty) {
      return; // não é uma sessão hospedada pelo Cockpit
    }
    // Transporte: socket Unix no POSIX; TCP loopback (+token) no Windows, que
    // não tem UDS no Dart. O servidor injeta a env certa por plataforma.
    final sock = env['COCKPIT_STATUS_SOCK'];
    final port = int.tryParse(env['COCKPIT_STATUS_PORT'] ?? '');
    if ((sock == null || sock.isEmpty) && port == null) return;

    final raw = await stdin.transform(utf8.decoder).join();
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;

    final event = (decoded['hook_event_name'] ?? '').toString();
    final status = _statusFor(event, decoded);
    if (status == null) return; // evento que não nos interessa

    final payload = jsonEncode(<String, dynamic>{
      'paneId': paneId,
      'st': status,
      // Evento cru — o app usa pra distinguir INÍCIO de turno (UserPromptSubmit)
      // de atividade mid-turn (Pre/PostToolUse) e descartar um 'working' tardio
      // que chega fora de ordem depois do 'idle' (Stop), evitando o spinner
      // eterno. Cada hook é um processo separado abrindo seu próprio socket, sem
      // ordem garantida entre eles.
      'ev': event,
      'sid': (decoded['session_id'] ?? '').toString(),
      'tx': (decoded['transcript_path'] ?? '').toString(),
      // Token só importa no TCP (loopback é acessível por qualquer processo
      // local); no UDS a permissão do socket já protege.
      if (env['COCKPIT_STATUS_TOKEN'] != null)
        'tok': env['COCKPIT_STATUS_TOKEN'],
    });

    final socket = sock != null && sock.isNotEmpty
        ? await Socket.connect(
            InternetAddress(sock, type: InternetAddressType.unix),
            0,
          )
        : await Socket.connect(InternetAddress.loopbackIPv4, port!);
    socket.add(utf8.encode('$payload\n'));
    await socket.flush();
    await socket.close();
    socket.destroy();
  } catch (_) {
    // Silencioso de propósito: não atrapalhar o turno do claude.
  }
}

/// Mapeia o evento de hook do Claude Code num status de turno, ou `null` se o
/// evento não deve mover o indicador.
String? _statusFor(String event, Map<dynamic, dynamic> json) {
  switch (event) {
    case 'UserPromptSubmit':
    case 'PreToolUse':
    case 'PostToolUse':
      return 'working';
    case 'Notification':
      // Notification cobre "precisa de aprovação" e "ocioso esperando input".
      final hint = '${json['notification_type'] ?? ''} ${json['message'] ?? ''}'
          .toLowerCase();
      return hint.contains('idle') ? 'idle' : 'waiting';
    case 'Stop':
    case 'SessionStart':
    case 'SessionEnd':
      return 'idle';
    default:
      return null;
  }
}
