import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';

/// Definição de uma linguagem para o LSP: como detectá-la (extensões), onde
/// está a raiz do projeto (markers, ver [ProjectRootFinder]) e o comando padrão
/// do language server. O comando é **binário + args** separados — split ingênuo
/// de string quebra em caminhos com espaço.
///
/// Na Wave 2 a tela "Language" sobrescreve `defaultExecutable`/`defaultArgs` por
/// preferência do usuário; a detecção no PATH preenche o default.
class LanguageDef {
  const LanguageDef({
    required this.id,
    required this.label,
    required this.extensions,
    required this.markers,
    required this.defaultExecutable,
    this.defaultArgs = const <String>[],
  });

  /// `languageId` do LSP (vai no `didOpen`) e chave de config/pool.
  final String id;

  /// Nome amigável pra UI (tela Language).
  final String label;

  /// Extensões (sem ponto, minúsculas) que mapeiam pra esta linguagem.
  final List<String> extensions;

  /// Arquivos marcadores de raiz de projeto (nome exato ou `*.sufixo`).
  final List<String> markers;

  final String defaultExecutable;
  final List<String> defaultArgs;

  LspServerSpec toSpec({String? executable, List<String>? args}) =>
      LspServerSpec(
        languageId: id,
        executable: executable ?? defaultExecutable,
        args: args ?? defaultArgs,
      );
}

/// Catálogo de linguagens suportadas. Dart é o caso campeão (servidor vem com o
/// Flutter SDK). As demais ficam prontas para a Wave 2 (config + status no PATH).
const List<LanguageDef> kLanguageDefs = <LanguageDef>[
  LanguageDef(
    id: 'dart',
    label: 'Dart',
    extensions: <String>['dart'],
    markers: <String>['pubspec.yaml'],
    defaultExecutable: 'dart',
    defaultArgs: <String>['language-server', '--client-id', 'cockpit'],
  ),
  LanguageDef(
    id: 'typescript',
    label: 'TypeScript',
    extensions: <String>['ts', 'tsx', 'mts', 'cts'],
    markers: <String>['tsconfig.json', 'package.json'],
    defaultExecutable: 'typescript-language-server',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'javascript',
    label: 'JavaScript',
    extensions: <String>['js', 'jsx', 'mjs', 'cjs'],
    markers: <String>['jsconfig.json', 'package.json'],
    defaultExecutable: 'typescript-language-server',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'python',
    label: 'Python',
    extensions: <String>['py', 'pyi'],
    markers: <String>[
      'pyproject.toml',
      'setup.py',
      'setup.cfg',
      'requirements.txt',
      'Pipfile',
    ],
    defaultExecutable: 'pyright-langserver',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'go',
    label: 'Go',
    extensions: <String>['go'],
    markers: <String>['go.mod', 'go.work'],
    defaultExecutable: 'gopls',
  ),
  LanguageDef(
    id: 'rust',
    label: 'Rust',
    extensions: <String>['rs'],
    markers: <String>['Cargo.toml'],
    defaultExecutable: 'rust-analyzer',
  ),
  LanguageDef(
    id: 'php',
    label: 'PHP',
    extensions: <String>['php'],
    markers: <String>['composer.json'],
    defaultExecutable: 'intelephense',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'csharp',
    label: 'C#',
    extensions: <String>['cs'],
    markers: <String>['*.csproj', '*.sln'],
    defaultExecutable: 'csharp-ls',
  ),
  LanguageDef(
    id: 'java',
    label: 'Java',
    extensions: <String>['java'],
    markers: <String>[
      'pom.xml',
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
    ],
    defaultExecutable: 'jdtls',
  ),
];

/// Resolve a [LanguageDef] de um caminho pela extensão, ou `null` se nenhuma
/// linguagem suportada bate.
LanguageDef? languageForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  for (final def in kLanguageDefs) {
    if (def.extensions.contains(ext)) return def;
  }
  return null;
}
