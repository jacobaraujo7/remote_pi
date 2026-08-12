import 'dart:io';

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
    try {
      await Process.run(path, <String>['install-skill']);
    } catch (_) {
      /* best-effort */
    }
    return path;
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
      if (!await _sameContent(bundled, dest)) {
        await destDir.create(recursive: true);
        await bundled.copy(dest.path);
        await _chmodExec(dest.path);
      }
      return hookPath(dest.path);
    }

    // Dev / sem bundle: usa cópia pré-existente (colocada manualmente).
    if (await dest.exists()) return hookPath(dest.path);
    return null;
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
