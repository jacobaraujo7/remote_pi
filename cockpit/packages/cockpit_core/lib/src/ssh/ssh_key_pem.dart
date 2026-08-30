import 'dart:io';

import 'ssh_tunnel.dart';
import 'package:dartssh2/dartssh2.dart';

/// Impl do contrato de classificação usado pelo `DbQueryService` — casca fina
/// sobre [SshKeyPem] pra manter `domain/` sem conhecimento de PEM e de disco.
class SshKeyPemInspector implements SshKeyInspector {
  const SshKeyPemInspector();

  @override
  Future<bool> needsPassphrase(String keyPath) =>
      SshKeyPem.isEncryptedFile(keyPath);

  @override
  Future<String?> defaultKeyPath() async {
    // Ordem de preferência do OpenSSH moderno. Devolve o path com `~` porque
    // é a forma portável guardada no databases.json.
    for (final candidate in const ['~/.ssh/id_ed25519', '~/.ssh/id_rsa']) {
      if (await File(SshKeyPem.expand(candidate)).exists()) return candidate;
    }
    return null;
  }
}

/// Leitura e classificação de chave privada SSH — o suficiente pro dialog
/// decidir se **mostra o campo de passphrase** (plano 54, passo 4) e pro túnel
/// decidir se precisa de segredo antes de tentar conectar.
class SshKeyPem {
  const SshKeyPem._();

  /// Expande `~` (o path é guardado com o til literal, que é o portável entre
  /// máquinas do time). Sem HOME resolvível, devolve o path como veio.
  static String expand(String path) {
    if (!path.startsWith('~')) return path;
    final home = _home();
    if (home == null) return path;
    return path == '~' ? home : '$home${path.substring(1)}';
  }

  /// HOME do usuário por plataforma.
  ///
  /// Resolvido aqui, e não pelo utilitário do app, porque este motor roda
  /// também no `cockpit-server` — e ali "a home" é a do HOST, que é justamente
  /// onde a chave do bastion tem que estar: quem abre o túnel é a máquina que
  /// abre a conexão com o banco.
  static String? _home() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final profile = env['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) return profile;
      final drive = env['HOMEDRIVE'];
      final path = env['HOMEPATH'];
      final joined = '${drive ?? ''}${path ?? ''}';
      return joined.isEmpty ? null : joined;
    }
    final home = env['HOME'];
    return (home != null && home.isNotEmpty) ? home : null;
  }

  /// Lê o PEM do disco. Arquivo ausente/ilegível vira
  /// [SshTunnelException] `ssh_key_missing` — erro acionável, não stack trace.
  static Future<String> read(String keyPath) async {
    final file = File(expand(keyPath));
    if (!await file.exists()) {
      throw SshTunnelException(
        'ssh_key_missing',
        'SSH key not found: ${expand(keyPath)}',
      );
    }
    try {
      return await file.readAsString();
    } on FileSystemException catch (e) {
      throw SshTunnelException(
        'ssh_key_missing',
        'Cannot read SSH key ${expand(keyPath)}: ${e.osError?.message ?? e.message}',
      );
    }
  }

  /// `true` se a chave exige passphrase (PEM clássico com `ENCRYPTED`, ou
  /// `openssh-key-v1` com cipher ≠ `none`). É o que decide se o campo aparece
  /// no dialog: chave limpa = conexão **sem segredo nenhum**, que funciona na
  /// GUI e na CLI sem tocar no cofre.
  ///
  /// PEM ilegível/não-chave devolve `false` — quem vai reclamar com mensagem
  /// decente é o parse no [SshKeyPem.parse], não o dialog.
  static bool isEncrypted(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } on Object {
      return false;
    }
  }

  /// Mesma pergunta, a partir do path (o que o dialog tem em mãos).
  /// Arquivo inexistente = `false` (o erro real aparece no Test/connect).
  static Future<bool> isEncryptedFile(String keyPath) async {
    try {
      return isEncrypted(await read(keyPath));
    } on SshTunnelException {
      return false;
    }
  }

  /// Decodifica o PEM em identidades. Passphrase errada/ausente numa chave
  /// encriptada vira `ssh_credential_required` — o mesmo kind que a GUI
  /// converte em prompt e a CLI em erro honesto.
  static List<SSHKeyPair> parse(String pem, String? passphrase) {
    final encrypted = isEncrypted(pem);
    if (encrypted && (passphrase == null || passphrase.isEmpty)) {
      throw const SshTunnelException(
        'ssh_credential_required',
        'This SSH key is passphrase-protected and no passphrase is available.',
      );
    }
    try {
      return SSHKeyPair.fromPem(pem, passphrase);
    } on Object catch (e) {
      // O dartssh2 não tipa "passphrase errada" — se a chave é encriptada e o
      // parse falhou com passphrase em mãos, essa é de longe a causa provável.
      if (encrypted) {
        throw const SshTunnelException(
          'ssh_credential_required',
          'Could not decrypt the SSH key — wrong passphrase?',
        );
      }
      throw SshTunnelException(
        'ssh_key_missing',
        'Invalid SSH private key: $e',
      );
    }
  }
}
