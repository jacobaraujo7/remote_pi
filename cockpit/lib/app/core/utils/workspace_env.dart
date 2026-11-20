import 'dart:io';

import 'package:cockpit/app/core/utils/remote_path.dart';

/// Nome do arquivo de variáveis de ambiente por workspace.
///
/// Um `KEY=VALUE` por linha, injetado no ambiente de **todo terminal** que o
/// Cockpit abre naquele workspace (local). Mora na raiz do workspace de
/// propósito: o sufixo faz a maioria dos `.gitignore` (`.env*`) já ignorá-lo
/// e nenhuma lib de dotenv o lê por engano. Segredos de uso rápido (token,
/// e-mail/senha de uma API) entram aqui em vez de serem colados no prompt do
/// agente.
const kWorkspaceEnvFileName = '.env.cockpit';

/// Faz o parse de um `.env.cockpit`.
///
/// Gramática **deliberadamente burra**, pra não haver duas semânticas de
/// dotenv na mesma máquina:
/// - `KEY=VALUE`, uma por linha; espaços em volta da chave e do valor são
///   removidos;
/// - `#` no início da linha (após espaços) é comentário; linha vazia é ignorada;
/// - prefixo `export ` é aceito e descartado (cola de shell funciona);
/// - valor entre aspas simples ou duplas perde as aspas; **não** há escape,
///   interpolação (`$OUTRA`) nem multiline;
/// - chave inválida (vazia ou fora de `[A-Za-z_][A-Za-z0-9_]*`) é ignorada;
/// - chave em [kBlockedWorkspaceEnvKeys] (ou prefixo `DYLD_`/`LD_`) é
///   ignorada: são as que trocam QUEM executa o quê, e um `.env.cockpit`
///   vindo de um repo clonado não pode redirecionar o shell da máquina;
/// - chave repetida: a última vence.
Map<String, String> parseWorkspaceEnv(String source) {
  final out = <String, String>{};
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trimLeft();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    if (!_kKeyPattern.hasMatch(key) || isBlockedWorkspaceEnvKey(key)) continue;
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' || first == "'") && first == last) {
        value = value.substring(1, value.length - 1);
      }
    }
    out[key] = value;
  }
  return out;
}

final _kKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Chaves que o `.env.cockpit` NUNCA injeta, mesmo escritas pelo usuário:
/// mudam qual binário roda, qual shell sobe ou de onde vem o rc, e um
/// arquivo comitado num repo clonado executaria código no primeiro terminal.
/// Segredo de API não precisa de nenhuma delas.
const Set<String> kBlockedWorkspaceEnvKeys = <String>{
  'PATH',
  'SHELL',
  'HOME',
  'ZDOTDIR',
  'COCKPIT_CODEX_LAUNCHER',
  'COCKPIT_ZSH_USER_DIR',
  'COCKPIT_ZSH_USER_DIR_SET',
  'COCKPIT_ZSH_PROXY_DIR',
  'BASH_ENV',
  'ENV',
  'LD_PRELOAD',
  'LD_LIBRARY_PATH',
  'LD_AUDIT',
  'DYLD_INSERT_LIBRARIES',
  'DYLD_LIBRARY_PATH',
  'DYLD_FRAMEWORK_PATH',
  'PROMPT_COMMAND',
  'IFS',
};

/// `true` se [key] está na lista bloqueada ou nos prefixos `DYLD_`/`LD_`
/// (o loader tem mais variáveis do que vale enumerar).
bool isBlockedWorkspaceEnvKey(String key) =>
    kBlockedWorkspaceEnvKeys.contains(key) ||
    key.startsWith('DYLD_') ||
    key.startsWith('LD_');

/// Pastas de [roots] que têm um `.env.cockpit` legível (na ordem dada). A
/// VM usa pra avisar no terminal quando um deles está rastreado pelo git.
List<String> workspaceEnvRootsWithFile(Iterable<String> roots) => [
  for (final root in roots)
    if (root.isNotEmpty &&
        File(
          '$root${Platform.pathSeparator}$kWorkspaceEnvFileName',
        ).existsSync())
      root,
];

/// Lê e faz o parse do `.env.cockpit` de cada pasta em [roots], fundindo na
/// ordem dada (a última root vence em chave repetida). Pasta sem o arquivo,
/// ou arquivo ilegível, contribui com nada — o terminal abre igual.
///
/// Síncrono de propósito: o spawn do PTY é síncrono e acontece no construtor
/// da sessão; um arquivo de poucas linhas na raiz do workspace não justifica
/// tornar aquele caminho assíncrono.
Map<String, String> loadWorkspaceEnvSync(Iterable<String> roots) {
  final merged = <String, String>{};
  for (final root in roots) {
    if (root.isEmpty) continue;
    final file = File('$root${Platform.pathSeparator}$kWorkspaceEnvFileName');
    String source;
    try {
      if (!file.existsSync()) continue;
      source = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    merged.addAll(parseWorkspaceEnv(source));
  }
  return merged;
}

/// Versão remota de [loadWorkspaceEnvSync]: mesma fusão por root, mas o
/// arquivo é lido no HOST por [readText] (a `fs.read` do `cockpit-server`).
/// [readText] devolve `null` quando o arquivo não existe ou falhou — a root
/// contribui com nada, igual ao local. Separado da I/O pra ser testável.
Future<Map<String, String>> loadWorkspaceEnvRemote(
  Iterable<String> roots,
  Future<String?> Function(String path) readText,
) async {
  final merged = <String, String>{};
  for (final root in roots) {
    if (root.isEmpty) continue;
    final source = await readText(remotePathJoin(root, kWorkspaceEnvFileName));
    if (source == null) continue;
    merged.addAll(parseWorkspaceEnv(source));
  }
  return merged;
}
