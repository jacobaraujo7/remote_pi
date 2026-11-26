import 'package:path/path.dart' as p;

/// Regras de destino do fluxo "Clonar repositório", puras e com a plataforma
/// injetável: o mesmo código decide caminhos de macOS (Silicon/Intel) e de
/// Windows (`C:\Users\...`) sem depender do host que roda o teste.

/// Pasta onde o dialog começa: a pasta-mãe do workspace selecionado (clonar
/// "ao lado" do projeto atual), senão o home do usuário, senão [fallback].
///
/// [context] decide o separador (`p.windows` / `p.posix`); o padrão é o do
/// host, que é o certo em produção.
String cloneInitialParent({
  String? selectedProjectPath,
  String? home,
  required String fallback,
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final selected = selectedProjectPath?.trim();
  if (selected != null && selected.isNotEmpty) {
    final parent = ctx.dirname(selected);
    // dirname da raiz devolve a própria raiz (`/`, `C:\`): ainda é um destino.
    if (parent.isNotEmpty && parent != '.') return parent;
  }
  if (home != null && home.isNotEmpty) return home;
  return fallback;
}

/// Caminho final do clone: [parent] + [folder] com o separador da plataforma.
String cloneTargetPath(String parent, String folder, {p.Context? context}) =>
    (context ?? p.context).join(parent, folder.trim());

/// Nome exibido de um caminho (último segmento), com o separador da
/// plataforma. `C:\Projetos\app` → `app`; `/Users/me/app/` → `app`.
String folderDisplayName(String path, {p.Context? context}) {
  final ctx = context ?? p.context;
  final name = ctx.basename(ctx.normalize(path));
  return name.isEmpty ? path : name;
}

/// Por que um nome de pasta não serve como destino do clone.
enum CloneFolderError {
  /// Vazio (ou só espaços).
  empty,

  /// `.` ou `..`.
  dotName,

  /// Contém `/` ou `\`: o nome é UM segmento, nunca um caminho. Barra
  /// invertida é recusada até no macOS (é válida lá, mas vira caminho no
  /// Windows e confunde quem sincroniza a pasta entre máquinas).
  separator,

  /// Windows: `< > : " | ? *` ou caractere de controle.
  invalidChar,

  /// Windows: nome reservado (`CON`, `NUL`, `COM1`…), com ou sem extensão.
  reserved,

  /// Windows: termina em `.` ou espaço (o Explorer remove e o git se perde).
  trailingDotOrSpace,
}

const _windowsReserved = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// Valida o nome da pasta do clone. `null` = serve. [windows] liga as regras
/// do NTFS/Win32, que são mais restritas que as do macOS.
CloneFolderError? validateCloneFolderName(String raw, {required bool windows}) {
  final name = raw.trim();
  if (name.isEmpty) return CloneFolderError.empty;
  if (name == '.' || name == '..') return CloneFolderError.dotName;
  if (name.contains('/') || name.contains(r'\')) {
    return CloneFolderError.separator;
  }
  if (!windows) return null;
  if (RegExp(r'[<>:"|?*\x00-\x1F]').hasMatch(name)) {
    return CloneFolderError.invalidChar;
  }
  final stem = name.split('.').first.toUpperCase();
  if (_windowsReserved.contains(stem)) return CloneFolderError.reserved;
  if (name.endsWith('.') || raw.endsWith(' ')) {
    return CloneFolderError.trailingDotOrSpace;
  }
  return null;
}

/// Falha conhecida de um `git clone`, reconhecida pela saída, pra o dialog
/// dizer o que fazer em vez de só mostrar o erro cru do git.
enum CloneFailure {
  /// O executável do git não foi encontrado (nem nos caminhos conhecidos nem
  /// no PATH).
  gitMissing,

  /// macOS: `/usr/bin/git` é o shim do Xcode e as Command Line Tools não estão
  /// instaladas.
  xcodeToolsMissing,

  /// O git não achou o `ssh` pra uma URL SSH.
  sshMissing,

  /// Host key do servidor mudou ou não pôde ser verificada.
  hostKey,

  /// Sem credencial: chave SSH recusada, HTTPS sem usuário/senha, ou repo
  /// privado/inexistente (o GitHub responde igual pros dois).
  auth,
}

/// Classifica a saída de um clone que falhou. `null` = falha sem dica (o erro
/// do git já basta, ex.: pasta não vazia, rede).
CloneFailure? classifyCloneFailure(Iterable<String> lines) {
  final out = lines.join('\n').toLowerCase();
  if (out.contains('failed to run git')) return CloneFailure.gitMissing;
  if (out.contains('xcrun: error') ||
      out.contains('invalid active developer path')) {
    return CloneFailure.xcodeToolsMissing;
  }
  if (out.contains('cannot run ssh') ||
      out.contains('ssh: command not found') ||
      out.contains('ssh: not found') ||
      out.contains("'ssh' is not recognized")) {
    return CloneFailure.sshMissing;
  }
  if (out.contains('host key verification failed') ||
      out.contains('remote host identification has changed')) {
    return CloneFailure.hostKey;
  }
  if (out.contains('permission denied (publickey') ||
      out.contains('could not read username') ||
      out.contains('authentication failed') ||
      out.contains('repository not found') ||
      out.contains('could not read from remote repository')) {
    return CloneFailure.auth;
  }
  return null;
}
