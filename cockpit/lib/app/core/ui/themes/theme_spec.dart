import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:cockpit/app/core/ui/themes/app_colors.dart';
import 'package:cockpit/app/core/ui/themes/syntax_colors.dart';
import 'package:cockpit/app/core/ui/themes/terminal_theme.dart';
import 'package:cockpit/app/core/ui/themes/theme_codec.dart';
import 'package:flutter/widgets.dart';

/// As três paletas de **um** brilho: a UI do app, o syntax do viewer e o
/// terminal. Antes eram escolhidas em lugares diferentes (syntax nas
/// Configurações, terminal fixo no brilho); juntá-las é o que faz "tema" virar
/// uma coisa só em vez de três decisões independentes.
@immutable
class ThemeVariant {
  const ThemeVariant({
    required this.ui,
    required this.syntax,
    required this.terminal,
  });

  final AppColors ui;
  final SyntaxColors syntax;
  final TerminalTheme terminal;

  /// Lê um variant de [json], herdando de [base] o que não for declarado.
  ///
  /// O fundo do viewer de código e o do terminal são a exceção à herança
  /// simples: quando o arquivo **não** os declara, eles seguem o `panel` deste
  /// tema, e não o da base. Sem isso, um tema que troca só as superfícies
  /// ficaria com o campo do código e do terminal pintados pelas cores do tema
  /// herdado — a emenda exata que unificar o campo veio resolver.
  factory ThemeVariant.fromJson(
    Map<String, Object?> json, {
    required ThemeVariant base,
    required String path,
  }) {
    final syntaxJson = objectAt(json, 'syntax', path: path);
    final terminalJson = objectAt(json, 'terminal', path: path);

    final ui = AppColors.fromJson(
      objectAt(json, 'ui', path: path),
      base: base.ui,
      path: '$path.ui',
    );
    return ThemeVariant(
      ui: ui,
      syntax: SyntaxColors.fromJson(
        // Declarou explicitamente? Manda o arquivo. Não declarou? Segue a aba.
        syntaxJson.containsKey('background')
            ? syntaxJson
            : {...syntaxJson, 'background': encodeHexColor(ui.panel)},
        base: base.syntax,
        path: '$path.syntax',
      ),
      terminal: terminalThemeFromJson(
        terminalJson.containsKey('background')
            ? terminalJson
            : {...terminalJson, 'background': encodeHexColor(ui.panel)},
        base: base.terminal,
        path: '$path.terminal',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'ui': ui.toJson(),
    'syntax': syntax.toJson(),
    'terminal': terminalThemeToJson(terminal),
  };
}

/// Um tema completo do Cockpit: identidade + um variant por brilho.
///
/// Um tema pode trazer só um dos dois variants (um "tema dark" puro). Nesse
/// caso [variantFor] devolve o que existe para qualquer brilho — melhor um tema
/// aplicado fora do brilho pedido do que um Frankenstein meio-claro-meio-escuro.
@immutable
class CockpitThemeSpec {
  const CockpitThemeSpec({
    required this.id,
    required this.name,
    this.author,
    this.version,
    this.dark,
    this.light,
  }) : assert(dark != null || light != null, 'tema sem nenhum variant');

  /// Id estável, namespaced (`cockpit.dark`, `acme.midnight`). É o que fica
  /// persistido nas preferências — renomear o `name` não perde a escolha.
  final String id;
  final String name;
  final String? author;
  final String? version;

  final ThemeVariant? dark;
  final ThemeVariant? light;

  bool get hasDark => dark != null;
  bool get hasLight => light != null;

  /// O variant para [brightness], com fallback no outro quando o tema só traz
  /// um dos dois.
  ThemeVariant variantFor(Brightness brightness) {
    final wanted = brightness == Brightness.dark ? dark : light;
    return wanted ?? dark ?? light!;
  }

  /// Parseia um tema em JSON. [resolveBase] resolve o `extends` para o tema
  /// herdado (tipicamente o registry dos built-in); quando o arquivo não declara
  /// `extends`, a base é [fallbackBase].
  factory CockpitThemeSpec.fromJson(
    Map<String, Object?> json, {
    required CockpitThemeSpec? Function(String id)? resolveBase,
    required CockpitThemeSpec fallbackBase,
  }) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const ThemeParseError(ThemeParseErrorKind.missingField, path: 'id');
    }
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const ThemeParseError(
        ThemeParseErrorKind.missingField,
        path: 'name',
      );
    }

    var base = fallbackBase;
    final extendsId = json['extends'];
    if (extendsId is String && extendsId.trim().isNotEmpty) {
      final resolved = resolveBase?.call(extendsId.trim());
      if (resolved == null) {
        throw ThemeParseError(
          ThemeParseErrorKind.unknownBase,
          path: 'extends',
          value: extendsId,
        );
      }
      base = resolved;
    }

    final variants = objectAt(json, 'variants', path: r'$');
    if (variants.isEmpty) {
      throw const ThemeParseError(
        ThemeParseErrorKind.noVariants,
        path: 'variants',
      );
    }

    ThemeVariant? read(String key, ThemeVariant? baseVariant) {
      final node = variants[key];
      if (node == null) return null;
      if (node is! Map<String, Object?>) {
        throw ThemeParseError(
          ThemeParseErrorKind.notAnObject,
          path: 'variants.$key',
        );
      }
      // Um tema que declara um variant que a base não tem (ex.: `extends` de um
      // tema só-dark, declarando light) herda do variant disponível na base.
      return ThemeVariant.fromJson(
        node,
        base: baseVariant ?? base.variantFor(Brightness.dark),
        path: 'variants.$key',
      );
    }

    final dark = read('dark', base.dark);
    final light = read('light', base.light);
    if (dark == null && light == null) {
      throw const ThemeParseError(
        ThemeParseErrorKind.noVariants,
        path: 'variants',
      );
    }
    return CockpitThemeSpec(
      id: id.trim(),
      name: name.trim(),
      author: json['author'] is String ? json['author'] as String : null,
      version: json['version'] is String ? json['version'] as String : null,
      dark: dark,
      light: light,
    );
  }

  /// Export sempre completo e sem `extends` — o arquivo gerado é autônomo e
  /// abre em qualquer versão que entenda o schema.
  Map<String, Object?> toJson() => {
    r'$schema': themeSchemaUrl,
    'id': id,
    'name': name,
    if (author != null) 'author': author,
    if (version != null) 'version': version,
    'variants': {
      if (dark != null) 'dark': dark!.toJson(),
      if (light != null) 'light': light!.toJson(),
    },
  };
}

/// URL do schema. Serve de dica de versão e liga o autocomplete em editores que
/// resolvem `$schema`.
///
/// Aponta pro arquivo **no repositório** (raw), não pra um domínio nosso: o
/// schema é versionado junto do código que o implementa, então não existe o
/// caso de o site servir uma versão e o app entender outra. Fixado em `main` de
/// propósito — quem escreve tema quer o autocomplete do formato atual, e o
/// `$schema` não participa do parse (o app ignora o campo ao ler o tema).
const String themeSchemaUrl =
    'https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json';
