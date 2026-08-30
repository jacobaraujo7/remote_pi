import 'dart:convert';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';
import 'package:cockpit/app/cockpit/data/remote/host_shell/posix_host_shell.dart'
    show HostShellException;

/// Dialeto Windows (plano 61).
///
/// Todo comando sai como `powershell -NoProfile -EncodedCommand` (D1) — ver
/// [windowsPowerShellCommand] para o porquê.
class WindowsHostShell extends HostShell {
  WindowsHostShell({required super.probe, required super.exec});

  /// Raiz no host. Montada com `$env:USERPROFILE` DENTRO do script, e não
  /// interpolada daqui, para não depender de como o cliente escapa barras.
  static const _root = r'$env:USERPROFILE\.cockpit';

  @override
  String get serverBinaryPath =>
      r'$env:USERPROFILE\.cockpit\server\bin\cockpit-server.exe';

  @override
  String get bootLogPath => r'$env:USERPROFILE\.cockpit\server-boot.log';

  /// Arquivo de rendezvous: no Windows o `LocalEndpoint` não cria socket, grava
  /// um JSON `{v, port, token}` neste caminho. É por ele que se descobre um
  /// servidor já de pé.
  static const _endpointFile = r'$env:USERPROFILE\.cockpit\cockpit-server.sock';

  /// Bundle do Cockpit instalado no host — a fonte da instalação (D2).
  static const _hostBundle =
      r'$env:LOCALAPPDATA\Programs\Remote Pi Cockpit\cockpit-server-bundle';

  @override
  bool get installsFromHostBundle => true;

  Future<(int, String, String)> _ps(String script) =>
      exec(windowsPowerShellCommand(script));

  @override
  Future<RemoteEndpoint?> readEndpoint() async {
    final (code, out, _) = await _ps('''
\$f = "$_endpointFile"
if (Test-Path \$f) { Get-Content -Raw \$f } else { '' }
''');
    if (code != 0) return null;
    final raw = out.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final port = decoded['port'];
      if (port is! int) return null;
      return TcpEndpoint(port: port, token: decoded['token'] as String?);
    } on FormatException {
      // Arquivo pela metade (servidor escrevendo agora) — o poll tenta de novo.
      return null;
    }
  }

  /// O rendezvous é escrito DEPOIS do bind, então encontrá-lo já significa
  /// "porta aceitando conexão". Ainda assim confirmamos a porta: um arquivo
  /// sobrevivente de um ciclo anterior apontaria pra porta morta.
  @override
  Future<RemoteEndpoint?> awaitEndpoint() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 200 + attempt * 100));
      final endpoint = await readEndpoint();
      if (endpoint is! TcpEndpoint) continue;
      if (await _portAlive(endpoint.port)) return endpoint;
    }
    return null;
  }

  Future<bool> _portAlive(int port) async {
    final (code, out, _) = await _ps('''
try {
  \$c = New-Object Net.Sockets.TcpClient
  \$c.Connect('127.0.0.1', $port)
  \$c.Close()
  'up'
} catch { 'down' }
''');
    return code == 0 && out.trim().endsWith('up');
  }

  @override
  Future<bool> serverInstalled() async {
    final (code, out, _) = await _ps(
      'if (Test-Path "$serverBinaryPath") { \'yes\' } else { \'no\' }',
    );
    return code == 0 && out.trim().endsWith('yes');
  }

  @override
  Future<String?> serverSha256() async {
    final (code, out, _) = await _ps('''
if (Test-Path "$serverBinaryPath") {
  (Get-FileHash -Algorithm SHA256 -LiteralPath "$serverBinaryPath").Hash
}
''');
    if (code != 0) return null;
    final token = out.trim();
    return token.length == 64 ? token.toLowerCase() : null;
  }

  /// Mata pelo caminho do executável, não pelo nome: a GUI do host roda o SEU
  /// próprio sidecar `cockpit-server.exe`, e derrubar o processo errado
  /// mataria os terminais locais de quem está sentado na máquina.
  @override
  Future<void> killServer() async {
    await _ps('''
Get-CimInstance Win32_Process -Filter "Name='cockpit-server.exe'" |
  Where-Object { \$_.ExecutablePath -eq "$serverBinaryPath" } |
  ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }
''');
  }

  /// Nunca usado: no Windows a instalação é [installFromHost] (D2). Manter o
  /// método é o contrato falando — se um dia o upload voltar (host sem Cockpit
  /// instalado), é aqui que ele entra.
  @override
  Future<void> installFromClient(ClientBundle bundle) async {
    throw const HostShellException(
      'windows host installs from its own bundle, not from the client',
    );
  }

  /// Copia o `cockpit-server-bundle` do Cockpit instalado no host para
  /// `~/.cockpit/server` — cópia LOCAL, nenhum byte de binário pelo SSH (D2).
  @override
  Future<bool> installFromHost() async {
    final (code, out, err) = await _ps('''
\$bundle = "$_hostBundle"
if (-not (Test-Path "\$bundle\\bin\\cockpit-server.exe")) { 'missing'; exit 0 }
\$root = "$_root\\server"
New-Item -ItemType Directory -Force -Path "\$root\\bin","\$root\\lib" | Out-Null
Copy-Item "\$bundle\\bin\\*" "\$root\\bin" -Force -Recurse
if (Test-Path "\$bundle\\lib") { Copy-Item "\$bundle\\lib\\*" "\$root\\lib" -Force -Recurse }
'ok'
''');
    if (code != 0) throw HostShellException(err);
    final result = out.trim();
    if (result.endsWith('missing')) return false;
    if (!result.endsWith('ok')) throw HostShellException(out);
    return true;
  }

  /// Sobe o servidor **fora do Job Object da sessão SSH**.
  ///
  /// O spike de 2026-08-26 refutou o `Start-Process`: a sessão do `sshd` no
  /// Windows roda dentro de um Job Object com kill-on-close, e todo filho morre
  /// junto quando a sessão termina — não existe `nohup` por ali. Escapa quem
  /// não nasce como filho: o `Win32_Process.Create` faz o `WmiPrvSE` criar o
  /// processo, fora do job.
  ///
  /// Três detalhes que caem disso:
  /// - O WMI **não** redireciona stdout/stderr, daí o `cmd … > log 2>&1`: sem
  ///   ele o `server-boot.log` ficaria vazio e um servidor que não sobe não
  ///   deixaria rastro (mesma razão do redirect no dialeto POSIX).
  /// - O `cmd` precisa do **`/s`**. Sem ele, quando o texto após o `/c` começa
  ///   com aspas — e começa, porque o caminho do exe pode ter espaço —, o
  ///   `cmd` remove a PRIMEIRA e a ÚLTIMA aspas da linha inteira: a última é a
  ///   do caminho do log, e o redirect ia junto. O sintoma era cruel: o
  ///   servidor até subia, mas o log nunca nascia, então quando ele NÃO subia
  ///   não havia o que ler. Com `/s` + a linha toda entre aspas, o `cmd` tira
  ///   só o par externo e o resto vale literal.
  /// - `COCKPIT_PTY_DYLIB` não é herdado por esse caminho; não faz falta,
  ///   porque o `cockpit_pty.dll` é copiado AO LADO do exe e esse é o segundo
  ///   candidato do `openPtyDylib`.
  @override
  Future<void> startServer({required int idleSeconds}) async {
    final (code, out, err) = await _ps('''
\$exe  = "$serverBinaryPath"
\$sock = "$_endpointFile"
\$log  = "$bootLogPath"
\$inner = '"' + \$exe + '" --socket "' + \$sock + '" --exit-on-idle $idleSeconds --idle-keeps-sessions > "' + \$log + '" 2>&1'
\$cmd = 'cmd.exe /s /c "' + \$inner + '"'
\$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = \$cmd }
if (\$r.ReturnValue -ne 0) { throw "Win32_Process.Create returned \$(\$r.ReturnValue)" }
'started'
''');
    if (code != 0) throw HostShellException(err.isEmpty ? out : err);
  }

  @override
  Future<String> tailBootLog({int bytes = 2000}) async {
    final (_, out, _) = await _ps('''
\$f = "$bootLogPath"
if (Test-Path \$f) {
  \$s = Get-Content -Raw \$f
  if (\$s.Length -gt $bytes) { \$s.Substring(\$s.Length - $bytes) } else { \$s }
}
''');
    return out;
  }
}
