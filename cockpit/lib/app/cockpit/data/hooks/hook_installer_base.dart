import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cockpit/app/cockpit/domain/contracts/hook_installer.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Parte comum dos instaladores de hook: materializar a CLI `cockpit` num
/// caminho estável e resolver o comando que vai parar no arquivo de config do
/// harness. O que cada harness tem de próprio (formato do arquivo, lista de
/// eventos, gate de confiança) fica na subclasse, em [writeConfig].
///
/// Nada aqui é específico de Claude ou Codex — os dois recebem o mesmo comando
/// (`<cli> hook`) e o mesmo envelope JSON pelo stdin.
abstract class HookInstallerBase implements HookInstaller {
  const HookInstallerBase();

  /// Serializa, POR CAMINHO DE DESTINO, quem escreve um binário.
  ///
  /// O `bootstrapper` dispara os instaladores de Claude e Codex em paralelo
  /// (`unawaited`, sem esperar um pelo outro), mas os dois materializam **o
  /// mesmo** `~/.cockpit/bin-<flavor>/cockpit.exe`. Sem isto, ambos veem o
  /// destino ausente, pulam o delete de [_copyOver] e chamam `File.copy`
  /// concorrentemente: um vence e o outro morre com `PathExistsException`
  /// (errno 183) — que é como o bug se manifestava no Windows, inclusive com a
  /// pasta recém-criada. No POSIX a corrida existia igual, só era silenciosa
  /// porque lá `copy` sobrescreve.
  ///
  /// Estático de propósito: as instâncias são `const` e distintas por harness,
  /// então o lock precisa viver no tipo, não no objeto.
  static final Map<String, Future<void>> _writeLocks = {};

  static Future<T> _serialized<T>(String key, Future<T> Function() body) async {
    final previous = _writeLocks[key];
    final done = Completer<void>();
    _writeLocks[key] = done.future;
    if (previous != null) {
      // Falha do anterior não contamina o próximo: cada tentativa é
      // independente e best-effort.
      await previous.catchError((_) {});
    }
    try {
      return await body();
    } finally {
      done.complete();
      if (identical(_writeLocks[key], done.future)) _writeLocks.remove(key);
    }
  }

  @override
  Future<Result<void, String>> ensureInstalled() async {
    final home = remotePiHome();
    if (home == null) {
      return const Failure<void, String>('HOME não resolvido');
    }
    try {
      // A CLI vem primeiro: é dela que sai o comando do hook.
      final cliPath = await ensureCli();
      final hookCommand = await resolveHookCommand(cliPath);
      if (hookCommand == null) {
        return const Failure<void, String>('helper de hook não encontrado');
      }
      await writeConfig(home: home, command: hookCommand);
      return const Success<void, String>(null);
    } catch (e) {
      return Failure<void, String>('$e');
    }
  }

  /// Grava a configuração do harness. [command] já vem citado e com o caminho
  /// normalizado; [home] é o diretório do usuário.
  Future<void> writeConfig({required String home, required String command});

  /// Nome curto do harness, para logs.
  String get harnessName;

  /// Comando a registrar na config do harness.
  ///
  /// Preferimos `<cli> hook` (CLI em Rust, que absorveu o helper). Se a CLI
  /// empacotada ainda for a Dart — que não conhece o subcomando — caímos no
  /// binário `cockpit-hook` legado, senão o status de turno morreria em silêncio
  /// nessa plataforma. `null` = nenhum dos dois disponível.
  Future<String?> resolveHookCommand(String? cliPath) async {
    if (cliPath != null && await _cliHandlesHook(cliPath)) {
      return '${shellQuote(cliPath)} hook';
    }
    final name = Platform.isWindows ? 'cockpit-hook.exe' : 'cockpit-hook';
    final dir = cockpitHookDir();
    if (dir == null) return null;
    final legacy = await _materialize(dir, bundledName: name, destName: name);
    return legacy == null ? null : shellQuote(legacy);
  }

  /// `true` quando a CLI materializada tem o subcomando `hook`.
  ///
  /// O sinal é o sufixo `r` da versão (`cockpit 0.6.0r`), que só a CLI em Rust
  /// emite — é exatamente pra isso que ele existe. Perguntar à CLI é mais
  /// confiável que inferir pela plataforma ou pela presença de arquivo no
  /// bundle, e custa um spawn de poucos ms no boot.
  Future<bool> _cliHandlesHook(String cliPath) async {
    try {
      final out = await Process.run(cliPath, <String>['--version']);
      if (out.exitCode != 0) return false;
      return '${out.stdout}'.trim().endsWith('r');
    } catch (_) {
      return false;
    }
  }

  /// Envolve em aspas duplas quando o caminho tem espaço.
  ///
  /// Os harnesses executam o `command` por um shell, então um caminho com espaço
  /// (`/Users/John Smith/...`) seria fatiado em dois argumentos. Isso já era
  /// latente com o comando de um token só; com `<cli> hook` passa a importar
  /// sempre. Só cita quando precisa, pra não churnar a config de quem tem
  /// caminho simples.
  String shellQuote(String path) => path.contains(' ') ? '"$path"' : path;

  /// Materializa a CLI interna `cockpit` em `~/.cockpit/bin[-debug]/cockpit[.exe]`
  /// (o fonte é empacotado como `cockpit-cli` pra não colidir com `cockpit.app`) e,
  /// se materializou, roda `cockpit install-skill` (idempotente) pra a skill
  /// nascer instalada. Silencioso: falha aqui não pode derrubar o boot.
  /// Devolve o caminho materializado, ou `null`.
  Future<String?> ensureCli() async {
    final bundledName = Platform.isWindows ? 'cockpit-cli.exe' : 'cockpit-cli';
    final destName = Platform.isWindows ? 'cockpit.exe' : 'cockpit';
    final dir = cockpitCliDir();
    if (dir == null) return null;
    final path = await _materialize(
      dir,
      bundledName: bundledName,
      destName: destName,
    );
    if (path == null) return null;
    await ensureShortAlias(dir, destName);
    try {
      await Process.run(path, <String>['install-skill']);
    } catch (_) {
      /* best-effort */
    }
    return path;
  }

  /// Nome curto da CLI — `ck` digita melhor que `cockpit` num terminal onde o
  /// agente (ou o humano) chama o comando o tempo todo.
  ///
  /// É o **mesmo binário**, não um segundo programa: nada muda de acordo com o
  /// nome pelo qual foi invocado, e a ajuda segue dizendo `cockpit`. Se o
  /// usuário já tem um `ck` próprio, o alias de shell dele vence o PATH e nada
  /// se quebra.
  static const String shortAliasName = 'ck';

  /// Cria o alias ao lado da CLI já materializada.
  ///
  /// POSIX usa symlink (custo zero em disco). No Windows o symlink exige
  /// Developer Mode ou privilégio de administrador, então lá é uma cópia do
  /// mesmo `.exe` — funciona em PowerShell, cmd e git-bash sem privilégio
  /// nenhum, e evita as pegadinhas de um shim `.cmd` com código de saída e
  /// aspas em argumentos.
  ///
  /// Silencioso: o alias é conveniência, nunca motivo para falhar o boot.
  @visibleForTesting
  Future<void> ensureShortAlias(String dirPath, String cliName) async {
    final aliasName = Platform.isWindows
        ? '$shortAliasName.exe'
        : shortAliasName;
    final target = File('$dirPath/$cliName');
    final alias = '$dirPath/$aliasName';
    try {
      if (!await target.exists()) return;
      // Mesmo destino para os dois harnesses (ver [_serialized]): sem o lock,
      // Claude e Codex criam o alias em paralelo e um dos dois falha.
      await _serialized(alias, () async {
        if (Platform.isWindows) {
          final dest = File(alias);
          if (await _sameContent(target, dest)) return;
          await _copyOver(target, alias);
          return;
        }
        final link = Link(alias);
        // Já aponta para o lugar certo? Não mexe. Aponta para outra coisa (ou
        // sobrou um arquivo solto de uma versão anterior): refaz.
        if (await link.exists()) {
          if (await link.target() == cliName) return;
          await link.delete();
        } else if (await File(alias).exists()) {
          await File(alias).delete();
        }
        // Alvo RELATIVO: a pasta pode ser movida junto com o `$HOME` (backup,
        // usuário renomeado) sem o link virar ponteiro morto.
        await link.create(cliName);
      });
    } on Object {
      /* best-effort */
    }
  }

  /// Copia um binário empacotado ([bundledName]) para `[destDirPath]/[destName]`.
  /// Devolve o caminho, ou `null` se não está no bundle (ex.: dev sem o passo de
  /// build) e não há cópia prévia.
  ///
  /// **Tamanho não decide se está atualizado.** Dois exe AOT do Dart compilados
  /// de fontes diferentes saem com frequência com o byte count idêntico (o
  /// snapshot é padded), então a checagem antiga por `length()` deixava a cópia
  /// velha pra trás em silêncio — o app novo rodando com a CLI de semanas atrás.
  /// Comparamos o conteúdo e só recopiamos quando difere de verdade.
  Future<String?> _materialize(
    String destDirPath, {
    required String bundledName,
    required String destName,
  }) async {
    final destDir = Directory(destDirPath);
    final dest = File('${destDir.path}/$destName');

    final bundled = _bundledHelper(bundledName);
    if (bundled != null && await bundled.exists()) {
      // A checagem de conteúdo entra DENTRO do lock junto da cópia: fora dele
      // ela é só um palpite, e dois instaladores concorrentes decidiriam
      // "desatualizado" ao mesmo tempo e copiariam em cima um do outro.
      await _serialized(dest.path, () async {
        if (await _sameContent(bundled, dest)) return;
        await destDir.create(recursive: true);
        await _copyOver(bundled, dest.path);
        await _chmodExec(dest.path);
      });
      return hookPath(dest.path);
    }

    // Dev / sem bundle: usa cópia pré-existente (colocada manualmente).
    if (await dest.exists()) return hookPath(dest.path);
    return null;
  }

  /// Copia [src] por cima de [destPath], sobrescrevendo o que estiver lá.
  ///
  /// `File.copy` **não** sobrescreve no Windows: o destino existente faz o
  /// `CopyFile` do Win32 falhar com `ERROR_ALREADY_EXISTS` (errno 183), e a
  /// instalação do hook morria em `PathExistsException` já na segunda execução
  /// do app — a primeira criava o arquivo, todas as seguintes batiam nele. No
  /// POSIX o `copy` sobrescreve sozinho, então o bug só aparecia no Windows.
  ///
  /// Remover antes resolve, com um porém: um `.exe` **em uso** não pode ser
  /// apagado no Windows, mas pode ser **renomeado**. Então, se o delete falhar,
  /// empurramos o velho para um `.old` ao lado e copiamos por cima — é assim que
  /// atualizador de binário no Windows funciona. O `.old` é descartável e a
  /// próxima passada o remove.
  Future<void> _copyOver(File src, String destPath) async {
    final dest = File(destPath);
    try {
      if (await dest.exists()) await dest.delete();
    } on FileSystemException {
      /* provavelmente em uso — o `exists` abaixo decide o que fazer */
    }
    // Recheca em vez de renomear direto do `catch`: no Windows o delete de um
    // arquivo aberto com FILE_SHARE_DELETE pode lançar E ainda assim levar o
    // arquivo embora. Renomear às cegas nesse caso dava
    // `PathNotFoundException` — trocando um erro por outro.
    if (await dest.exists()) {
      final stale = File('$destPath.old');
      try {
        if (await stale.exists()) await stale.delete();
      } on FileSystemException {
        /* sobra de uma troca anterior ainda presa; o rename abaixo decide */
      }
      await dest.rename(stale.path);
    }
    await src.copy(destPath);
  }

  /// `true` quando [dest] já é byte-a-byte igual a [src]. O tamanho é só o
  /// descarte barato; quem decide é a comparação de conteúdo.
  Future<bool> _sameContent(File src, File dest) async {
    if (!await dest.exists()) return false;
    if (await src.length() != await dest.length()) return false;
    try {
      final a = await src.readAsBytes();
      final b = await dest.readAsBytes();
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    } catch (_) {
      // Ilegível por qualquer motivo: trata como desatualizado e recopia — o
      // custo é uma cópia extra, o risco oposto é ficar com binário velho.
      return false;
    }
  }

  /// Normaliza o caminho para o `command` do hook usando **forward slashes**.
  ///
  /// Os harnesses executam os hooks via `bash` (git-bash/MSYS) mesmo no Windows.
  /// O `bash` trata `\` como escape, então um caminho com `\` (ex.:
  /// `C:\Users\x\.cockpit\bin\cockpit-hook.exe`) vira `C:Usersx.cockpit...` e dá
  /// `command not found`. Como `$home` (`USERPROFILE`) vem com `\` no Windows, o
  /// caminho montado ficava misto/quebrado. Convertendo tudo para `/`
  /// (`C:/Users/x/.cockpit/bin/cockpit-hook.exe`) o bash executa normalmente. Em
  /// POSIX é no-op.
  String hookPath(String path) =>
      Platform.isWindows ? path.replaceAll(r'\', '/') : path;

  /// Caminho do helper empacotado no app, por plataforma:
  /// - macOS: `…/Contents/MacOS/<app>` → `…/Contents/Resources/cockpit-hook`
  /// - Windows/Linux: ao lado do executável (`<dir>/cockpit-hook[.exe]`)
  File? _bundledHelper(String name) {
    try {
      final exe = File(Platform.resolvedExecutable);
      if (Platform.isMacOS) {
        final contents = exe.parent.parent; // Contents/MacOS → Contents
        return File('${contents.path}/Resources/$name');
      }
      return File('${exe.parent.path}/$name');
    } catch (_) {
      return null;
    }
  }

  Future<void> _chmodExec(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (_) {
      /* best-effort */
    }
  }
}
