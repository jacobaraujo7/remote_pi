import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UTF-8 que não estoura em byte inválido.
///
/// O default de `Process.run` é o `systemEncoding` — UTF-8 **estrito** no
/// macOS/Linux —, e o `result.stdout as String` decodifica na hora. Uma linha
/// com byte fora do UTF-8 (banner de servidor, mensagem do `ssh-keygen`/
/// `ssh-keyscan` numa locale não-UTF8) virava `FormatException`. Aqui isso não
/// aparecia como erro: os dois `catch` abaixo engolem tudo e devolvem
/// `unknown`/lista vazia, então o efeito era o app achar que um host CONHECIDO
/// é novo, ou não conseguir mostrar fingerprint nenhum no diálogo de TOFU.
/// Mesma tolerância do `SshTunnel`.
const _lenientUtf8 = Utf8Codec(allowMalformed: true);

/// Situação da host key de um destino no `~/.ssh/known_hosts` do usuário.
enum SshHostKeyStatus {
  /// Já confiada: o `ssh` verifica sozinho e nada precisa ser perguntado.
  known,

  /// Nunca vista. Primeira conexão (TOFU) — pergunte ao humano.
  unknown,

  /// Existe entrada para o destino, mas o `ssh` recusou a chave apresentada:
  /// a identidade do servidor MUDOU. Nunca se aceita isso inline.
  changed,
}

/// Leitura e escrita do `known_hosts` do usuário, para o caminho desktop (que
/// usa o `ssh` do sistema).
///
/// Por que isto existe: o app roda o ssh com `BatchMode=yes`, que impede o
/// prompt "are you sure you want to continue connecting?". Sem uma política de
/// host key, todo host **novo** com auth por chave falhava com
/// `Host key verification failed` e não havia caminho nenhum pela GUI — só
/// abrir um terminal e conectar na mão uma vez.
///
/// A alternativa preguiçosa seria `StrictHostKeyChecking=accept-new`, que
/// confia em qualquer chave nova em silêncio. Preferimos o mesmo TOFU do resto
/// do app: mostrar o fingerprint e deixar o humano decidir (ver
/// `showSshHostKeyDialog`). Chave **alterada** não tem aceite inline em
/// caminho algum.
class SshKnownHosts {
  const SshKnownHosts();

  /// Formato do `known_hosts` para destino com porta não-padrão: `[host]:port`.
  static String targetOf(String host, int port) =>
      port == 22 ? host : '[$host]:$port';

  /// O destino já está no `known_hosts`?
  ///
  /// `ssh-keygen -F` sai 0 com as linhas encontradas; 1 quando não há nenhuma.
  /// Ele também entende os hashes de host (`HashKnownHosts`), que uma busca
  /// textual nossa não veria.
  Future<SshHostKeyStatus> lookup(String host, int port) async {
    try {
      final result = await Process.run(
        'ssh-keygen',
        ['-F', targetOf(host, port)],
        stdoutEncoding: _lenientUtf8,
        stderrEncoding: _lenientUtf8,
      ).timeout(_timeout);
      final found =
          result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty;
      return found ? SshHostKeyStatus.known : SshHostKeyStatus.unknown;
    } on Object {
      // Sem `ssh-keygen` no PATH (raro; vem junto do ssh) → trate como
      // desconhecido e deixe o fluxo normal falhar com o erro do ssh.
      return SshHostKeyStatus.unknown;
    }
  }

  /// Chaves que o host apresenta AGORA, no formato do `known_hosts` (uma por
  /// linha, comentários removidos), ou vazio se ninguém respondeu.
  Future<List<String>> scan(String host, int port) async {
    try {
      final result = await Process.run(
        'ssh-keyscan',
        [
          '-T',
          '5',
          if (port != 22) ...['-p', '$port'],
          host,
        ],
        stdoutEncoding: _lenientUtf8,
        stderrEncoding: _lenientUtf8,
      ).timeout(_timeout);
      if (result.exitCode != 0) return const [];
      return (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
    } on Object {
      return const [];
    }
  }

  /// Fingerprint legível das [keys] (o que o humano compara com o servidor).
  /// Devolve a primeira linha do `ssh-keygen -lf -`, tipicamente a ed25519.
  Future<String?> fingerprintOf(List<String> keys) async {
    if (keys.isEmpty) return null;
    try {
      final process = await Process.start('ssh-keygen', ['-lf', '-']);
      process.stdin.write('${keys.join('\n')}\n');
      await process.stdin.close();
      final out = await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(_timeout);
      unawaited(process.stderr.drain<void>());
      final lines = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      return lines.isEmpty ? null : lines.first;
    } on Object {
      return null;
    }
  }

  /// Grava [keys] no `known_hosts` do usuário. Só é chamado depois de o humano
  /// confirmar o fingerprint.
  Future<void> trust(List<String> keys) async {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty || keys.isEmpty) return;
    final dir = Directory('$home/.ssh');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/known_hosts');
    final needsNewline =
        file.existsSync() &&
        file.lengthSync() > 0 &&
        !(await file.readAsString()).endsWith('\n');
    await file.writeAsString(
      '${needsNewline ? '\n' : ''}${keys.join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static const _timeout = Duration(seconds: 10);
}
