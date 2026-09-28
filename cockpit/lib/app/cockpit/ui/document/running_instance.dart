import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as p;

/// Instância única no Windows/Linux (plano 2.0, k17).
///
/// No macOS o LaunchServices entrega o duplo clique do Finder ao app já aberto
/// (`AppDelegate.openFiles`). No Windows e no Linux o sistema **sobe um
/// processo novo** com o caminho do arquivo como argumento. Este helper faz o
/// papel do LaunchServices: o processo novo procura um Cockpit vivo pelo
/// socket da CLI interna, manda os caminhos pra ele (`open-document`) e sai;
/// se não há ninguém, ele mesmo vira o app e abre os arquivos após o boot.
///
/// Fala o mesmo wire da CLI `cockpit` (`type:"cmd"`, uma linha JSON em cada
/// direção). POSIX: socket Unix `~/.cockpit/status[-debug].sock`. Windows: TCP
/// no loopback, porta + token gravados pelo app em
/// `~/.cockpit/status[-debug].json` (ver [statusEndpointFile]).
class RunningInstance {
  RunningInstance._();

  static String get _suffix => kDebugMode ? '-debug' : '';

  static String? get _cockpitDir {
    final home = remotePiHome();
    if (home == null) return null;
    return p.join(home, '.cockpit');
  }

  /// Windows: onde o app anuncia `{port, tok}` do servidor de status. Sem UDS
  /// não há caminho bem conhecido pra "bater na porta", e a porta é efêmera.
  static String? get statusEndpointFile {
    final dir = _cockpitDir;
    if (dir == null) return null;
    return p.join(dir, 'status$_suffix.json');
  }

  static String? get _socketPath {
    final dir = _cockpitDir;
    if (dir == null) return null;
    return p.join(dir, 'status$_suffix.sock');
  }

  /// Env pra spawnar a CLI interna `cockpit` a partir da janela solta: PATH com
  /// o binário app-managed na frente e, no POSIX, o socket deste flavor (a CLI
  /// já cai no caminho bem conhecido, mas o env evita falar com o app errado
  /// quando release e debug estão abertos). No Windows a CLI lê
  /// [statusEndpointFile] sozinha. Sem `COCKPIT_PANE_ID`: a janela não é uma
  /// aba, e a CLI resolve o workspace pelo que o humano tem selecionado.
  static Map<String, String> get cliEnvironment {
    final env = <String, String>{};
    final bin = cockpitCliDir();
    if (bin != null) {
      final existing = Platform.environment['PATH'] ?? '';
      final sep = Platform.isWindows ? ';' : ':';
      env['PATH'] = existing.isEmpty ? bin : '$bin$sep$existing';
    }
    final sock = _socketPath;
    if (!Platform.isWindows && sock != null) env['COCKPIT_STATUS_SOCK'] = sock;
    return env;
  }

  /// Caminhos de arquivo entre os argumentos de linha de comando (o que o
  /// Explorer/xdg-open passam ao "abrir com"). Só existentes e absolutizados
  /// contra o cwd; flags e o protocolo `multi_window` ficam de fora.
  static List<String> filePathsFromArguments(List<String> args) {
    if (args.isNotEmpty && args.first == 'multi_window') return const [];
    final out = <String>[];
    for (final raw in args) {
      if (raw.isEmpty || raw.startsWith('-')) continue;
      final path = p.normalize(p.absolute(raw));
      if (FileSystemEntity.isFileSync(path) ||
          FileSystemEntity.isDirectorySync(path)) {
        out.add(path);
      }
    }
    return out;
  }

  /// Tenta entregar [paths] a um Cockpit já aberto. `true` = entregue (o
  /// chamador deve encerrar este processo). `false` = ninguém em casa (ou o
  /// app vivo é antigo e não conhece o comando): siga o boot normal.
  static Future<bool> forwardOpen(List<String> paths) async {
    if (paths.isEmpty) return false;
    return _send('open-document', {'paths': paths});
  }

  /// Pede ao app vivo que **aplique** um layout `.ckp`. Quem chama é o botão
  /// Apply da janela de documento (card do viewer de layout): a janela solta
  /// mostra o layout, mas quem tem workspaces, abas e panes é a janela
  /// principal. O app resolve o destino, pede a confirmação e se traz para a
  /// frente. `false` = ninguém atendeu (app fechado).
  static Future<bool> forwardApplyLayout(String path) =>
      _send('apply-layout', {'path': path});

  /// Uma linha JSON no socket da CLI interna, a mesma que o `cockpit` fala.
  static Future<bool> _send(String cmd, Map<String, Object?> args) async {
    Socket socket;
    String? token;
    try {
      if (Platform.isWindows) {
        final file = statusEndpointFile;
        if (file == null || !File(file).existsSync()) return false;
        final decoded = jsonDecode(File(file).readAsStringSync());
        if (decoded is! Map) return false;
        final port = decoded['port'];
        if (port is! int) return false;
        token = decoded['tok']?.toString();
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 2),
        );
      } else {
        final path = _socketPath;
        if (path == null || !File(path).existsSync()) return false;
        socket = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 2),
        );
      }
    } on Object {
      // Socket órfão (app fechou sem limpar) ou arquivo de porta velho: o
      // connect recusa e este processo assume o papel de app.
      return false;
    }
    try {
      final req = <String, Object?>{
        'type': 'cmd',
        'cmd': cmd,
        'tok': ?token,
        'args': args,
      };
      socket.add(utf8.encode('${jsonEncode(req)}\n'));
      await socket.flush();
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      final resp = jsonDecode(line);
      return resp is Map && resp['ok'] == true;
    } on Object {
      return false;
    } finally {
      socket.destroy();
    }
  }
}
