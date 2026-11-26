import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Ponto de encontro local entre o `cockpit-server` e quem fala com ele na
/// MESMA máquina (o sidecar da GUI, a ponta local do túnel SSH).
///
/// - **POSIX**: socket UNIX no caminho pedido. É o transporte histórico.
/// - **Windows**: `dart:io` não tem socket UNIX (`InternetAddressType.unix` só
///   existe em Linux/macOS/Android), então o servidor escuta em **TCP
///   loopback** numa porta efêmera e deixa no caminho pedido um **arquivo de
///   rendezvous** com a porta e um token. Sem isso o servidor morria no bind e
///   todo terminal do Windows caía no PTY in-process — de graça, depois de
///   esperar o backoff inteiro do conector.
///
/// O arquivo faz o papel que o inode do socket fazia: é por ele que um cliente
/// **descobre** um servidor já de pé e o adota em vez de subir um segundo.
///
/// O token existe porque uma porta de loopback aceita conexão de QUALQUER
/// processo da máquina, enquanto o socket UNIX já nascia protegido pelas
/// permissões do `~/.cockpit`. Ele viaja no `Hello` (campo `tok`) e o servidor
/// recusa o handshake sem ele. Mesma solução do status-server do app
/// (`TerminalStatusServerImpl`), que enfrentou este mesmo limite do `dart:io`.
///
/// O transporte também pode ser escolhido explicitamente, sem depender da
/// plataforma: é o `--tcp` do `cockpit-server`, usado por hosts cujo SSH não
/// faz forward de socket UNIX (Tailscale SSH).
enum LocalEndpointTransport { unixSocket, tcp }

class LocalEndpoint {
  /// Transporte default desta plataforma.
  static LocalEndpointTransport get platformTransport => Platform.isWindows
      ? LocalEndpointTransport.tcp
      : LocalEndpointTransport.unixSocket;

  /// Escuta em [path] e devolve o listener (+ token, no transporte TCP).
  ///
  /// [transport] sem valor usa [platformTransport]. O servidor remoto passa
  /// TCP explicitamente quando o host não consegue encaminhar socket UNIX.
  static Future<LocalListener> bind(
    String path, {
    LocalEndpointTransport? transport,
  }) async {
    final mode = transport ?? platformTransport;
    final file = File(path);
    await file.parent.create(recursive: true);
    // Resquício do ciclo anterior: no POSIX o bind falha se o inode existe; no
    // Windows um arquivo velho apontaria pra uma porta morta.
    if (file.existsSync()) file.deleteSync();

    if (mode == LocalEndpointTransport.unixSocket) {
      final listener = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      return LocalListener._(
        listener,
        path,
        null,
        transport: mode,
        boundAt: _modifiedAt(path),
      );
    }

    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final token = _randomToken();
    // Escrita do arquivo é o ÚLTIMO passo: quem o encontra sabe que a porta
    // já aceita conexão (o conector adota servidor existente sem retry).
    // O token é um segredo: o temporário nasce vazio, recebe 0600 e SÓ ENTÃO
    // o JSON é escrito. O rename atômico publica o anúncio já completo — sem
    // janela de arquivo vazio e sem token legível por outra conta local (o
    // socket UNIX não tinha esse problema).
    final temp = File(
      '$path.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.create();
      await _restrictToOwner(temp.path);
      await temp.writeAsString(
        jsonEncode({'v': 1, 'port': listener.port, 'token': token}),
        flush: true,
      );
      await temp.rename(path);
    } on Object {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // melhor esforço: o erro original é o que importa.
      }
      rethrow;
    }
    return LocalListener._(
      listener,
      path,
      token,
      transport: mode,
      boundAt: _modifiedAt(path),
    );
  }

  static DateTime? _modifiedAt(String path) {
    try {
      return File(path).statSync().modified;
    } on FileSystemException {
      return null;
    }
  }

  /// Conecta ao servidor que escuta em [path]. Lança se não há ninguém lá
  /// (arquivo ausente/ilegível, porta recusando) — o chamador trata como
  /// "servidor não existe".
  static Future<LocalSocket> connect(
    String path, {
    LocalEndpointTransport? transport,
  }) async {
    final mode = transport ?? platformTransport;
    if (mode == LocalEndpointTransport.unixSocket) {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      return LocalSocket(socket, null);
    }
    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('invalid cockpit endpoint file');
    }
    final port = decoded['port'];
    if (port is! int) {
      throw const FormatException('cockpit endpoint file without port');
    }
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    return LocalSocket(socket, decoded['token'] as String?);
  }

  /// Existe um endpoint anunciado em [path]? Só a presença — quem confirma que
  /// alguém atende é o [connect].
  static bool announcedAt(String path) => File(path).existsSync();

  /// O arquivo de rendezvous é um segredo (porta + token): só o dono pode ler.
  ///
  /// `dart:io` não expõe o modo POSIX na criação, então o arquivo é criado
  /// vazio, restringido e só depois recebe o JSON. Falhar aqui é fail-closed:
  /// sem 0600 não há token em disco.
  static Future<void> _restrictToOwner(String path) async {
    if (Platform.isWindows) return;
    for (final command in const ['/bin/chmod', 'chmod']) {
      try {
        final result = await Process.run(command, ['600', path]);
        if (result.exitCode == 0) return;
      } on ProcessException {
        // Tenta o próximo caminho; se nenhum existir, cai no throw abaixo.
      }
    }
    throw FileSystemException(
      'could not restrict rendezvous permissions to 0600',
      path,
    );
  }

  static String _randomToken() {
    final rng = Random.secure();
    return List<int>.generate(
      16,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Listener aberto por [LocalEndpoint.bind].
class LocalListener {
  LocalListener._(
    this.listener,
    this.path,
    this.token, {
    required this.transport,
    this.boundAt,
  });

  /// Quando o anúncio foi criado — a impressão digital do POSIX (um bind novo
  /// por cima cria inode novo, com mtime novo).
  final DateTime? boundAt;

  /// O caminho anunciado ainda é NOSSO?
  ///
  /// Um segundo Cockpit subindo binda o mesmo caminho por cima e o servidor
  /// antigo fica órfão: ninguém mais o encontra, mas ele continua vivo
  /// segurando PTYs inalcançáveis. Isto é o que permite ele perceber e sair.
  ///
  /// No Windows a checagem é exata (o arquivo de rendezvous guarda o NOSSO
  /// token); no POSIX é o mtime do inode do socket, que muda a cada bind.
  bool stillOwned() {
    final file = File(path);
    if (!file.existsSync()) return false;
    final expected = token;
    if (expected != null) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        return decoded is Map && decoded['token'] == expected;
      } on Object {
        return false;
      }
    }
    final at = boundAt;
    if (at == null) return true; // sem impressão digital: não acusa nada.
    try {
      return file.statSync().modified == at;
    } on FileSystemException {
      return false;
    }
  }

  final ServerSocket listener;

  /// Caminho anunciado (socket UNIX no POSIX; arquivo de rendezvous no Windows).
  final String path;

  /// Transporte efetivamente usado pelo listener.
  final LocalEndpointTransport transport;

  /// Token exigido no `Hello`, ou `null` quando o transporte é socket UNIX.
  final String? token;

  Future<void> close() async {
    await listener.close();
    // No POSIX o arquivo é o próprio socket e o SO não o remove sozinho; no
    // Windows o arquivo apontaria pra uma porta morta. Nos dois casos, sai.
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Sem permissão / já removido: não é motivo pra falhar o shutdown.
    }
  }
}

/// Socket conectado por [LocalEndpoint.connect], com o token a mandar no
/// `Hello` (null no POSIX).
class LocalSocket {
  const LocalSocket(this.socket, this.token);

  final Socket socket;
  final String? token;
}
