import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';

/// Quebra uma linha de comando em tokens respeitando aspas simples/duplas (pra
/// caminhos com espaço). Não expande variáveis — é só tokenização.
List<String> splitLspCommand(String command) {
  final tokens = <String>[];
  final buf = StringBuffer();
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == ' ' || ch == '\t') {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

/// Verifica se [command] se comporta como um language server **válido**:
/// spawna o processo e checa se ele **fica vivo** por um curto intervalo. Um LSP
/// real fica esperando o `initialize` no stdin; um comando errado (ex.:
/// `dart language-serve`) imprime uso e sai na hora com código != 0.
///
/// É mais forte que só checar o binário no PATH (que não valida os argumentos).
/// Mata o processo após a sondagem. `false` se não dá nem pra spawnar.
Future<bool> probeLspCommand(String command) async {
  final parts = splitLspCommand(command.trim());
  if (parts.isEmpty) return false;
  final exec = await resolveExecutable(parts.first);

  Process? process;
  try {
    process = await Process.start(
      exec,
      parts.sublist(1),
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    );
  } catch (_) {
    return false; // nem conseguiu spawnar (binário ausente / inválido)
  }

  // Drena os streams pra não travar o processo num buffer cheio.
  final proc = process;
  unawaited(proc.stdout.drain<void>().catchError((_) {}));
  unawaited(proc.stderr.drain<void>().catchError((_) {}));

  // Saiu dentro da janela → inválido. Continuou vivo → parece um LSP de verdade.
  var aliveAfterWindow = false;
  try {
    await proc.exitCode.timeout(const Duration(milliseconds: 1200));
  } on TimeoutException {
    aliveAfterWindow = true;
  }

  proc.kill(ProcessSignal.sigkill);
  return aliveAfterWindow;
}

/// Roda um **formatador externo** (ex.: `prettier --write %FILE%`) sobre o
/// arquivo em [filePath]. O token `%FILE%` é substituído pelo caminho em cada
/// argumento. File-based: o formatador reescreve o arquivo no disco. Sucesso se
/// exit code 0; senão devolve o stderr (ou exit code) como mensagem.
Future<Result<void, String>> runFormatterCommand(
  String command,
  String filePath,
) async {
  final parts = splitLspCommand(command.trim());
  if (parts.isEmpty) return const Failure('Empty formatter command.');
  if (!command.contains('%FILE%')) {
    return const Failure(
      'Formatter command must include the %FILE% placeholder.',
    );
  }
  final substituted = parts
      .map((t) => t.replaceAll('%FILE%', filePath))
      .toList();
  final exec = await resolveExecutable(substituted.first);
  try {
    final r = await Process.run(
      exec,
      substituted.sublist(1),
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    ).timeout(const Duration(seconds: 30));
    if (r.exitCode == 0) return const Success(null);
    final err = (r.stderr as String? ?? '').trim();
    return Failure(err.isEmpty ? 'Formatter exited with ${r.exitCode}.' : err);
  } on TimeoutException {
    return const Failure('Formatter timed out.');
  } catch (e) {
    return Failure('$e');
  }
}
