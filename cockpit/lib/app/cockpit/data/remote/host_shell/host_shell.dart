/// Dialeto de shell do HOST remoto (plano 61).
///
/// O bootstrap remoto (instalar/subir/derrubar o `cockpit-server`, descobrir
/// onde ele escuta) precisa das MESMAS operações em qualquer host — o que muda
/// é como cada uma se escreve. Até o plano 61 o [RemoteHostConnector] montava
/// comando POSIX cru inline em ~10 lugares, e por isso um host Windows era
/// simplesmente recusado.
///
/// O corte aqui é **por dialeto, não por `if`**: um contrato, duas
/// implementações. O ganho é que o contrato FORÇA as duas famílias a cobrirem a
/// mesma superfície — uma operação nova não nasce só-POSIX sem quebrar a
/// compilação da outra, que é exatamente como o bootstrap chegou onde chegou.
library;

import 'dart:convert';

/// Como alcançar o `cockpit-server` de um host.
///
/// O servidor já nasce diferente nas duas famílias (ver `LocalEndpoint`, no
/// `cockpit_protocol`): no POSIX é um socket UNIX num caminho conhecido; no
/// Windows é uma porta TCP de loopback efêmera + token, anunciados num arquivo
/// de rendezvous. O túnel SSH precisa saber qual dos dois para montar o `-L`.
sealed class RemoteEndpoint {
  const RemoteEndpoint();

  /// Token do handshake, quando o transporte exige (só o TCP). Uma porta de
  /// loopback aceita conexão de qualquer processo da máquina, enquanto o socket
  /// UNIX já nasce protegido pelas permissões do `~/.cockpit`.
  String? get token;
}

/// Ponta remota é um socket UNIX — `ssh -L <local>:<caminho>`.
class UnixSocketEndpoint extends RemoteEndpoint {
  const UnixSocketEndpoint(this.path);
  final String path;

  @override
  String? get token => null;
}

/// Ponta remota é TCP de loopback — `ssh -L <local>:127.0.0.1:<porta>`.
class TcpEndpoint extends RemoteEndpoint {
  const TcpEndpoint({required this.port, this.token});
  final int port;

  @override
  final String? token;
}

/// Família de sistema do host. Decide o dialeto, não a distro.
enum HostOsFamily { posix, windows }

/// O que se sabe do host depois do probe inicial.
class HostProbe {
  const HostProbe({
    required this.family,
    required this.os,
    required this.arch,
    required this.home,
  });

  final HostOsFamily family;

  /// `darwin` | `linux` | `windows` — o mesmo vocabulário que o cliente usa
  /// para nomear a própria plataforma, porque os dois são comparados na hora de
  /// decidir se há binário compatível para enviar.
  final String os;

  /// `x64` | `arm64`.
  final String arch;

  /// Home do usuário no host, já resolvida (`$HOME` / `%USERPROFILE%`).
  final String home;
}

/// Bundle do cliente usado como fonte da instalação remota.
///
/// Só o dialeto POSIX o consome: no Windows a instalação é cópia local no
/// próprio host (decisão D2 do plano 61), sem transferir bytes pelo SSH.
class ClientBundle {
  const ClientBundle({required this.root, required this.serverBinary});

  /// Raiz do bundle: `<root>/bin/cockpit-server` + `<root>/lib/*`.
  final String root;
  final String serverBinary;
}

/// Executor de comandos no host. É sempre o mesmo canal SSH do resto do
/// conector — o dialeto decide o texto do comando, não como ele viaja.
typedef HostExec =
    Future<(int code, String stdout, String stderr)> Function(
      String command, {
      List<int>? stdinBytes,
    });

/// Operações que o bootstrap remoto precisa, uma por dialeto.
abstract class HostShell {
  const HostShell({required this.probe, required this.exec});

  final HostProbe probe;

  /// Canal de execução no host — sempre o mesmo SSH do resto do conector.
  final HostExec exec;

  /// Caminho do servidor no host, no dialeto local (com `.exe` no Windows).
  String get serverBinaryPath;

  /// Caminho do log de arranque.
  String get bootLogPath;

  /// `true` quando este dialeto instala SEM bundle do cliente — o Windows
  /// copia o do Cockpit instalado no próprio host (D2), então um cliente macOS
  /// consegue instalar num host Windows mesmo sem ter um `.exe` para enviar.
  bool get installsFromHostBundle;

  /// Onde o servidor escuta, ou `null` se não há servidor de pé.
  ///
  /// No POSIX o caminho é determinístico e o "não há ninguém" é descoberto pelo
  /// próprio túnel — devolver o endpoint sem gastar um SSH extra preserva a
  /// latência de abertura que existia antes do plano 61.
  Future<RemoteEndpoint?> readEndpoint();

  /// Poll de [readEndpoint] após iniciar o servidor. `null` = desistiu.
  Future<RemoteEndpoint?> awaitEndpoint();

  /// `true` se o binário do servidor já está instalado no host.
  Future<bool> serverInstalled();

  /// SHA-256 do binário do servidor no host, ou `null` se indisponível.
  /// Na dúvida devolve `null`: não se mexe num servidor que está funcionando.
  Future<String?> serverSha256();

  /// Derruba o servidor em execução (troca de binário desatualizado).
  Future<void> killServer();

  /// Instala a partir do bundle do CLIENTE (POSIX). Lança em falha.
  Future<void> installFromClient(ClientBundle bundle);

  /// Instala a partir do Cockpit já instalado no HOST (Windows, D2).
  /// `false` = não há bundle no host, o chamador traduz para erro tipado.
  Future<bool> installFromHost();

  /// Sobe o servidor, destacado da sessão SSH.
  Future<void> startServer({required int idleSeconds});

  /// Últimos bytes do log de arranque — a evidência quando o servidor não sobe.
  Future<String> tailBootLog({int bytes = 2000});
}

/// Descobre o dialeto do host com **um** comando.
///
/// Tenta POSIX primeiro (`uname -sm` + `$HOME`); esse mesmo comando já traz
/// tudo que o antigo `printf %s "$HOME"` do `SshTunnel.open` buscava, então o
/// caminho POSIX não paga round-trip novo. Só quando ele falha é que vale
/// perguntar em PowerShell — num host POSIX essa segunda pergunta nunca ocorre.
Future<HostProbe?> probeHost(HostExec exec) async {
  final (code, out, _) = await exec(r'uname -sm && printf %s "$HOME"');
  if (code == 0) {
    final lines = out.trim().split('\n');
    if (lines.length >= 2) {
      final parts = lines.first.trim().split(RegExp(r'\s+'));
      final os = parts.isEmpty ? '' : parts.first.toLowerCase();
      final machine = parts.length > 1 ? parts[1].toLowerCase() : '';
      return HostProbe(
        family: HostOsFamily.posix,
        os: os,
        arch: machine.contains('arm') || machine == 'aarch64' ? 'arm64' : 'x64',
        home: lines.sublist(1).join('\n').trim(),
      );
    }
  }
  return _probeWindows(exec);
}

Future<HostProbe?> _probeWindows(HostExec exec) async {
  final (code, out, _) = await exec(
    windowsPowerShellCommand(r'''
$arch = $env:PROCESSOR_ARCHITECTURE
[pscustomobject]@{
  arch = $(if ($arch -eq 'ARM64') { 'arm64' } else { 'x64' })
  home = $env:USERPROFILE
} | ConvertTo-Json -Compress
'''),
  );
  if (code != 0) return null;
  try {
    final decoded = jsonDecode(out.trim());
    if (decoded is! Map) return null;
    final home = decoded['home'];
    if (home is! String || home.isEmpty) return null;
    return HostProbe(
      family: HostOsFamily.windows,
      os: 'windows',
      arch: decoded['arch'] == 'arm64' ? 'arm64' : 'x64',
      home: home,
    );
  } on FormatException {
    return null;
  }
}

/// Embrulha [script] em `powershell -NoProfile -EncodedCommand <base64>`
/// (decisão D1 do plano 61).
///
/// Por que EncodedCommand e não comando em texto:
/// - **Não exige configurar o host.** O shell default do OpenSSH no Windows é o
///   `cmd.exe`; assim funciona numa instalação recém-feita, sem mexer no
///   `DefaultShell` do registro.
/// - **Elimina o inferno de aspas** em três níveis (nosso argv → ssh → cmd →
///   PowerShell), que é onde caminho com espaço (`C:\Users\John Smith`) quebra.
/// - **Saída em UTF-8 previsível** pelo preâmbulo de `OutputEncoding`: mata na
///   ORIGEM a classe de bug em que o `cmd` responde na codepage local
///   (CP850/CP1252) e o cliente estoura `FormatException: Missing extension
///   byte` — antes só tolerávamos os bytes inválidos na chegada.
String windowsPowerShellCommand(String script) {
  const preamble = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new()\n';
  return 'powershell -NoProfile -EncodedCommand '
      '${_encodeUtf16Le(preamble + script)}';
}

/// `-EncodedCommand` exige base64 de **UTF-16LE**, não de UTF-8.
String _encodeUtf16Le(String script) {
  final units = script.codeUnits;
  final bytes = List<int>.filled(units.length * 2, 0);
  for (var i = 0; i < units.length; i++) {
    bytes[i * 2] = units[i] & 0xFF;
    bytes[i * 2 + 1] = (units[i] >> 8) & 0xFF;
  }
  return base64.encode(bytes);
}
