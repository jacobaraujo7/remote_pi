import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/remote/host_shell/host_shell.dart';

/// Dialeto POSIX (macOS/Linux) — o bootstrap que existia antes do plano 61,
/// extraído do `RemoteHostConnector` sem mudança de comportamento.
class PosixHostShell extends HostShell {
  PosixHostShell({required super.probe, required super.exec});

  static const _serverDir = r'$HOME/.cockpit/server';
  static const _manifestPath = '$_serverDir/bundle.manifest';
  static const _installLock = r'$HOME/.cockpit/server.install.lock';

  // Diretórios nunca podem ser promovidos para o live com `mv source live`:
  // se `live` surgir entre o teste e o mv, POSIX manda `source` para dentro
  // dele. `rename(2)` troca/falha no caminho exato e, portanto, não aninha.
  static const _noNestRename = r'''
no_nest_rename() {
  if mv --version 2>/dev/null | grep -q 'GNU coreutils'; then
    mv -T -- "$1" "$2"
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" "$2" <<'PY'
import os
import sys

try:
    os.rename(sys.argv[1], sys.argv[2])
except OSError as error:
    print('cockpit-server rename failed: %s' % error, file=sys.stderr)
    raise SystemExit(1)
PY
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e 'rename($ARGV[0], $ARGV[1]) or die "cockpit-server rename failed: $!\n"' "$1" "$2"
    return $?
  fi
  echo "cockpit-server needs GNU mv -T, python3, or perl for a safe directory rename" >&2
  return 69
}
''';

  @override
  String get serverBinaryPath => '$_serverDir/bin/cockpit-server';

  @override
  String get bootLogPath => r'$HOME/.cockpit/server-boot.log';

  /// Caminho do socket, com o `$HOME` deixado para o shell do host expandir.
  static const _socketPath = r'$HOME/.cockpit/cockpit-server.sock';

  @override
  bool get installsFromHostBundle => false;

  /// Determinístico a partir da home já resolvida no probe — sem SSH extra.
  ///
  /// "Não há servidor" NÃO é decidido aqui: quem descobre é o túnel, que falha
  /// ao conectar e leva ao bootstrap. É assim desde o plano 58, e manter
  /// preserva a latência de abertura do caminho POSIX.
  @override
  Future<RemoteEndpoint?> readEndpoint() async =>
      UnixSocketEndpoint('${probe.home}/.cockpit/cockpit-server.sock');

  @override
  Future<RemoteEndpoint?> awaitEndpoint() async {
    // O socket UNIX aparece quando o servidor faz bind. `test -S` é o sinal
    // exato: arquivo comum com o mesmo nome não serviria.
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 150 + attempt * 100));
      final (code, out, _) = await exec(
        'test -S $_socketPath && echo up || echo down',
      );
      if (code == 0 && out.trim().endsWith('up')) return readEndpoint();
    }
    return null;
  }

  @override
  Future<bool> serverInstalled() async {
    final (code, out, _) = await exec(
      'test -x $serverBinaryPath && test -f $_manifestPath && '
      'echo yes || echo no',
    );
    return code == 0 && out.trim().endsWith('yes');
  }

  @override
  Future<String?> serverSha256() async {
    final (code, out, _) = await exec(
      'sha256sum $serverBinaryPath 2>/dev/null || '
      'shasum -a 256 $serverBinaryPath 2>/dev/null',
    );
    if (code != 0) return null;
    final token = out.trim().split(RegExp(r'\s+')).firstOrNull;
    return (token != null && token.length == 64) ? token.toLowerCase() : null;
  }

  @override
  Future<String?> bundleManifestSha256() async {
    final (code, out, _) = await exec(
      'sha256sum $_manifestPath 2>/dev/null || '
      'shasum -a 256 $_manifestPath 2>/dev/null',
    );
    if (code != 0) return null;
    final token = out.trim().split(RegExp(r'\s+')).firstOrNull;
    return (token != null && token.length == 64) ? token.toLowerCase() : null;
  }

  @override
  Future<void> killServer() async {
    await exec('pkill -f "$serverBinaryPath" || true');
  }

  @override
  Future<void> installFromClient(ClientBundle bundle) async {
    final manifest = await bundle.buildManifest();
    final token = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final stage = r'$HOME/.cockpit/server.staging-' + token;
    final backup = r'$HOME/.cockpit/server.previous-' + token;
    final conflict = r'$HOME/.cockpit/server.conflict-' + token;

    Future<void> run(String command, {List<int>? stdinBytes}) async {
      final (code, out, err) = await exec(command, stdinBytes: stdinBytes);
      if (code != 0) {
        throw HostShellException(err.isNotEmpty ? err : out);
      }
    }

    var locked = false;
    var promotionStarted = false;
    var swapped = false;
    try {
      // `mkdir` é o mutex portátil entre processos/clientes. O mtime recebe
      // heartbeat antes de cada upload; só um lock sem heartbeat por 10min é
      // recuperado. Espera limitada evita deixar a UI presa indefinidamente.
      await run('''
mkdir -p "\$HOME/.cockpit"
attempt=0
while ! mkdir "$_installLock" 2>/dev/null; do
  if find "$_installLock" -prune -mmin +10 -print 2>/dev/null | grep -q .; then
    abandoned="$_installLock.abandoned-$token"
    if mv "$_installLock" "\$abandoned" 2>/dev/null; then
      rm -rf "\$abandoned"
      continue
    fi
  fi
  attempt=\$((attempt + 1))
  if [ "\$attempt" -ge 30 ]; then
    echo "cockpit-server install lock timed out" >&2
    exit 75
  fi
  sleep 1
done
printf '%s\n' '$token' > "$_installLock/owner"
touch "$_installLock"
''');
      locked = true;

      Future<void> runLocked(String command, {List<int>? stdinBytes}) => run('''
if [ "\$(cat "$_installLock/owner" 2>/dev/null)" != "$token" ]; then
  echo "cockpit-server install lock lost" >&2
  exit 75
fi
touch "$_installLock"
$command
''', stdinBytes: stdinBytes);

      Future<void> push(ClientBundleFile file) async {
        final parent = file.remotePath.split('/').first;
        await runLocked(
          'mkdir -p "$stage/$parent" && '
          'cat > "$stage/${file.remotePath}" && '
          'chmod +x "$stage/${file.remotePath}"',
          stdinBytes: await File(file.localPath).readAsBytes(),
        );
      }

      // Sob o lock, recupera um swap antigo interrompido e remove somente
      // stages que não podem mais pertencer a uma transação ativa.
      await runLocked('''
$_noNestRename
if { [ ! -e "$_serverDir" ] && [ ! -L "$_serverDir" ]; }; then
  set -- "\$HOME/.cockpit"/server.previous-*
  if [ -e "\$1" ] || [ -L "\$1" ]; then
    no_nest_rename "\$1" "$_serverDir" || {
      echo "cockpit-server could not safely recover prior backup" >&2
      exit 76
    }
  fi
fi
for stale in "\$HOME/.cockpit"/server.staging-*; do
  if [ -d "\$stale" ]; then rm -rf "\$stale"; fi
done
if [ -e "$backup" ] || [ -L "$backup" ]; then
  echo "cockpit-server transaction backup path is occupied: $backup" >&2
  exit 76
fi
mkdir -p "$stage"
''');

      for (final file in manifest.files) {
        await push(file);
      }

      // O marcador vai por ÚLTIMO: sem ele, serverInstalled() trata qualquer
      // resto de upload interrompido como incompleto e tenta de novo.
      await runLocked(
        'cat > "$stage/bundle.manifest"',
        stdinBytes: utf8.encode(manifest.contents),
      );

      // Verifica cada byte ainda no staging e só então promove. O lock impede
      // dois instaladores cooperantes. Renames para o live usam uma primitiva
      // que nunca interpreta um destino que apareceu na corrida como diretório.
      promotionStarted = true;
      await runLocked('''
set -eu
$_noNestRename
rollback_live() {
  if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then return 0; fi
  if [ -e "$_serverDir" ] || [ -L "$_serverDir" ]; then
    if [ -e "$conflict" ] || [ -L "$conflict" ]; then
      echo "cockpit-server rollback conflict path is occupied: $conflict" >&2
      return 1
    fi
    if ! mv "$_serverDir" "$conflict"; then
      echo "cockpit-server could not quarantine unexpected live directory" >&2
      return 1
    fi
  fi
  if [ -e "$_serverDir" ] || [ -L "$_serverDir" ]; then
    echo "cockpit-server live directory still exists during rollback" >&2
    return 1
  fi
  no_nest_rename "$backup" "$_serverDir"
}
cd "$stage"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c bundle.manifest
else
  shasum -a 256 -c bundle.manifest
fi
if [ -x bin/cockpit ]; then ln -sf cockpit bin/ck; fi
if [ -e "$_serverDir" ] || [ -L "$_serverDir" ]; then
  mv "$_serverDir" "$backup"
fi
if [ -e "$_serverDir" ] || [ -L "$_serverDir" ]; then
  rollback_live ||
    echo "cockpit-server rollback incomplete; backup preserved at $backup" >&2
  echo "cockpit-server live directory changed during promotion" >&2
  exit 76
fi
if no_nest_rename "$stage" "$_serverDir"; then
  # Só o sucesso definitivo da promoção autoriza apagar o known-good.
  rm -rf "$backup" || true
else
  rollback_live ||
    echo "cockpit-server rollback incomplete; backup preserved at $backup" >&2
  exit 1
fi
''');
      swapped = true;
    } finally {
      if (locked) {
        // Ainda sob o lock, repara a janela live→backup caso o transporte tenha
        // caído entre os dois renames. Um live ambíguo é preservado no conflito
        // desta transação; o backup só volta depois de o caminho live sumir.
        if (!swapped) {
          try {
            final failedStageCleanup = promotionStarted
                ? ''
                : 'rm -rf "$stage"';
            await exec('''
$_noNestRename
if [ "\$(cat "$_installLock/owner" 2>/dev/null)" = "$token" ]; then
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    if [ -e "$_serverDir" ] || [ -L "$_serverDir" ]; then
      if [ ! -e "$conflict" ] && [ ! -L "$conflict" ]; then
        mv "$_serverDir" "$conflict" || true
      fi
    fi
    if { [ ! -e "$_serverDir" ] && [ ! -L "$_serverDir" ]; }; then
      no_nest_rename "$backup" "$_serverDir" ||
        echo "cockpit-server final recovery left backup at $backup" >&2
    fi
  fi
  $failedStageCleanup
fi
''');
          } on Object {
            // Transporte caiu: o próximo dono recupera backup e stages stale.
          }
        }
        try {
          await exec('''
if [ "\$(cat "$_installLock/owner" 2>/dev/null)" = "$token" ]; then
  rm -rf "$_installLock"
fi
''');
        } on Object {
          // O lock ganha recovery por mtime se o transporte não voltar.
        }
      }
    }
  }

  @override
  Future<bool> installFromHost() async => false;

  @override
  Future<void> startServer({required int idleSeconds}) async {
    final ptyLib = probe.os == 'darwin'
        ? 'libcockpit_pty.dylib'
        : 'libcockpit_pty.so';
    // nohup + redirects: o servidor sobrevive ao fim desta sessão ssh. A saída
    // vai pra um LOG, não pro /dev/null: um servidor que morre no arranque
    // (arquitetura errada, dylib faltando) precisa deixar rastro — sem isso o
    // `echo started` saía 0 e a falha chegava na UI como silêncio.
    final (code, _, err) = await exec(
      'COCKPIT_PTY_DYLIB=\$HOME/.cockpit/server/lib/$ptyLib '
      'nohup $serverBinaryPath '
      '--socket $_socketPath '
      '--exit-on-idle $idleSeconds '
      '--idle-keeps-sessions '
      '>$bootLogPath 2>&1 & echo started',
    );
    if (code != 0) throw HostShellException(err);
  }

  @override
  Future<String> tailBootLog({int bytes = 2000}) async {
    final (_, out, _) = await exec(
      'tail -c $bytes $bootLogPath 2>/dev/null || true',
    );
    return out;
  }
}

/// Falha crua do host (stderr de terceiros). Vira `detail` de um
/// `RemoteHostException` tipado na borda — nunca frase de usuário.
class HostShellException implements Exception {
  const HostShellException(this.detail);
  final String detail;

  @override
  String toString() => 'HostShellException($detail)';
}
