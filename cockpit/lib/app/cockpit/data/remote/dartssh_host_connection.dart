import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/data/remote/mobile_ssh_key_store.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Endpoint SSH parseado de um `sshTarget` (`user@host[:port]`).
class SshEndpoint {
  const SshEndpoint(this.user, this.host, this.port);
  final String user;
  final String host;
  final int port;

  /// Parseia `user@host`, `user@host:port` ou `host` (sem user → erro tipado:
  /// no mobile não há usuário do SO pra assumir).
  static SshEndpoint parse(String target) {
    final trimmed = target.trim();
    final at = trimmed.indexOf('@');
    if (at <= 0) {
      throw const DartSshException('ssh_target_no_user');
    }
    final user = trimmed.substring(0, at);
    var rest = trimmed.substring(at + 1);
    var port = 22;
    final colon = rest.lastIndexOf(':');
    if (colon > 0) {
      final maybePort = int.tryParse(rest.substring(colon + 1));
      if (maybePort != null) {
        port = maybePort;
        rest = rest.substring(0, colon);
      }
    }
    if (rest.isEmpty) throw const DartSshException('ssh_target_no_host');
    return SshEndpoint(user, rest, port);
  }

  String get endpoint => '$host:$port';
}

/// Falha tipada do transporte dartssh2 (a frase nasce na UI; `detail` é texto
/// cru: stderr do host, fingerprint).
class DartSshException implements Exception {
  const DartSshException(this.code, [this.detail]);
  final String code;
  final String? detail;

  @override
  String toString() => 'DartSshException($code: $detail)';
}

/// Conexão SSH em Dart puro (`dartssh2`) para o **mobile** (plano 59): autentica
/// com a chave do dispositivo ([MobileSshKeyStore]) e encaminha pro socket UNIX
/// remoto do `cockpit-server` via `forwardLocalUnix` (`direct-streamlocal`).
///
/// Host-key **TOFU**: chave desconhecida é confiada e persistida na 1ª conexão;
/// chave que MUDOU é recusada (possível MITM ou servidor reinstalado). O store é
/// o `flutter_secure_storage` (Keychain/Keystore).
class DartSshHostConnection {
  DartSshHostConnection(
    this._endpoint, {
    MobileSshKeyStore? keyStore,
    FlutterSecureStorage? storage,
    String? password,
  }) : _keyStore = keyStore ?? MobileSshKeyStore(),
       _storage = storage ?? const FlutterSecureStorage(),
       _password = password; // ignore: prefer_initializing_formals

  final SshEndpoint _endpoint;
  final MobileSshKeyStore _keyStore;
  final FlutterSecureStorage _storage;

  /// Senha (auth por senha, plano 60 Wave C). `null` = auth por chave do
  /// dispositivo. Nunca logada; vem do Keychain via o connector.
  final String? _password;

  SSHClient? _client;

  static const _hostKeyPrefix = 'cockpit.ssh.hostkey.';
  static const _connectTimeout = Duration(seconds: 15);

  Future<void> get done => _client?.done ?? Future<void>.value();

  /// Abre (autentica) a conexão SSH. Idempotente enquanto viva.
  Future<void> connect() async {
    if (_client != null && !_client!.isClosed) return;
    final identities = await _keyStore.identities();

    String? rejection;
    final SSHClient client;
    try {
      final socket = await SSHSocket.connect(
        _endpoint.host,
        _endpoint.port,
        timeout: _connectTimeout,
      );
      client = SSHClient(
        socket,
        username: _endpoint.user,
        // Auth por senha: sem identidades (evita tentar a chave do device e
        // falhar antes de chegar na senha). Auth por chave: identidades do
        // Keychain, sem callback de senha.
        identities: _password != null ? const [] : identities,
        onPasswordRequest: _password != null ? () => _password : null,
        onVerifyHostKey: (type, fingerprint) async {
          final printed = utf8.decode(fingerprint);
          final key = '$_hostKeyPrefix${_endpoint.endpoint}';
          final known = await _storage.read(key: key);
          if (known == printed) return true;
          if (known != null) {
            rejection = 'ssh_host_key_changed';
            return false;
          }
          // TOFU: 1ª vez → confia e persiste.
          await _storage.write(key: key, value: printed);
          return true;
        },
      );
      // Teto no handshake/auth: o timeout do [SSHSocket.connect] cobre só o
      // connect TCP. Um host que aceita a conexão e não completa a autenticação
      // (rede meia-boca, servidor sobrecarregado) deixaria isto pendurado sem
      // limite, e a UI eternamente em "conectando" — sem falhar nem reagendar.
      await client.authenticated.timeout(
        _connectTimeout,
        onTimeout: () => throw const DartSshException('ssh_auth_timeout'),
      );
    } on DartSshException {
      rethrow;
    } catch (e) {
      throw DartSshException(rejection ?? 'ssh_connect_failed', '$e');
    }
    _client = client;
  }

  /// Encaminha pro socket UNIX remoto (`direct-streamlocal@openssh.com`) e
  /// devolve o canal duplex.
  Future<SSHForwardChannel> forwardUnix(String remoteSocketPath) async {
    final client = _client;
    if (client == null) throw const DartSshException('ssh_not_connected');
    return client
        .forwardLocalUnix(remoteSocketPath)
        .timeout(
          _connectTimeout,
          onTimeout: () => throw const DartSshException('ssh_forward_timeout'),
        );
  }

  /// Encaminha pra uma porta de LOOPBACK remota (`direct-tcpip`) e devolve o
  /// canal duplex.
  ///
  /// É o caminho de host Windows (plano 61): lá o `cockpit-server` não cria
  /// socket UNIX — `dart:io` não tem AF_UNIX no Windows —, escuta em TCP de
  /// loopback e anuncia porta+token num arquivo de rendezvous. O
  /// `forwardLocalUnix` não serve para esse caso.
  Future<SSHForwardChannel> forwardTcp(int port) async {
    final client = _client;
    if (client == null) throw const DartSshException('ssh_not_connected');
    return client
        .forwardLocal('127.0.0.1', port)
        .timeout(
          _connectTimeout,
          onTimeout: () => throw const DartSshException('ssh_forward_timeout'),
        );
  }

  /// Executa um comando no host devolvendo **exit code, stdout e stderr
  /// separados** — o que o dialeto de host (`HostShell`) precisa para decidir
  /// se o comando funcionou.
  ///
  /// Existe porque o `run` do `dartssh2` **mescla stderr no stdout** (o default
  /// é `stderr: true`) e não expõe exit code. Num host Windows isso era veneno:
  /// `uname -sm && printf %s "\$HOME"` falha, o `cmd.exe` responde em DUAS
  /// linhas na stderr ("'uname' não é reconhecido…"), e o probe via `run` lia
  /// aquilo como stdout de duas linhas — exatamente o formato de um POSIX que
  /// respondeu. O host Windows era classificado como POSIX, o forward ia pro
  /// `direct-streamlocal` de um socket que não existe, e o erro chegava como
  /// `SSHChannelOpenError(2: open failed)`.
  Future<(int, String, String)> runDetailed(String command) async {
    final client = _client;
    if (client == null) throw const DartSshException('ssh_not_connected');
    final result = await client
        .runWithResult(command)
        .timeout(
          _connectTimeout,
          onTimeout: () => throw const DartSshException('ssh_exec_timeout'),
        );
    // Tolerante pelo mesmo motivo do SshTunnel.capture: host Windows responde
    // na codepage local, e um byte inválido aqui virava FormatException no
    // lugar do erro real.
    return (
      result.exitCode ?? 0,
      utf8.decode(result.stdout, allowMalformed: true),
      utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  /// Executa um comando no host e devolve o stdout (trim). Usado só pra
  /// resolver caminhos (ex.: `$HOME`) — o mobile não faz bootstrap (decisão D).
  Future<String> run(String command) async {
    final client = _client;
    if (client == null) throw const DartSshException('ssh_not_connected');
    // Mesmo motivo do handshake: um exec que não volta pendurava a abertura
    // inteira (este `run` resolve a `$HOME` remota antes do forward).
    final out = await client
        .run(command)
        .timeout(
          _connectTimeout,
          onTimeout: () => throw const DartSshException('ssh_exec_timeout'),
        );
    // Tolerante pelo mesmo motivo do SshTunnel.capture: host Windows responde
    // na codepage local, e um byte inválido aqui virava FormatException no
    // lugar do erro real.
    return utf8.decode(out, allowMalformed: true).trim();
  }

  Future<void> close() async {
    _client?.close();
    _client = null;
  }
}
