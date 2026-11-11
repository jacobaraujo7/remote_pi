import 'dart:io';

/// Garante um locale UTF-8 no ambiente de terminais e tasks no macOS.
///
/// Um `.app` aberto pelo Dock/Finder não herda `LANG`/`LC_*`. Sem locale, o
/// `pbcopy` (usado pelo Claude Code, vim e scripts pra copiar) lê o stdin como
/// MacRoman e os acentos chegam quebrados no clipboard ("seção" vira
/// "se√ß√£o"); outras ferramentas também caem no locale `C`. O Terminal.app e o
/// iTerm exportam `LANG` sozinhos — aqui fazemos o mesmo.
///
/// Devolve [env] intacto fora do macOS ou se `LANG`, `LC_ALL` ou `LC_CTYPE` já
/// vierem preenchidos (escolha do usuário vence). Senão, `LANG` vira o idioma
/// do usuário em UTF-8 (`pt-BR` → `pt_BR.UTF-8`) se o locale existir no
/// sistema, ou `en_US.UTF-8`. Linux fica de fora: a sessão gráfica já exporta
/// `LANG`, e `en_US.UTF-8` nem sempre está gerado lá.
///
/// Os parâmetros opcionais existem pros testes.
Map<String, String> withUtf8Locale(
  Map<String, String> env, {
  bool? isMacOS,
  String? localeName,
  bool Function(String locale)? localeExists,
}) {
  if (!(isMacOS ?? Platform.isMacOS)) return env;
  bool has(String key) => (env[key] ?? '').isNotEmpty;
  if (has('LANG') || has('LC_ALL') || has('LC_CTYPE')) return env;
  final exists =
      localeExists ??
      (String locale) => Directory('/usr/share/locale/$locale').existsSync();
  // `Platform.localeName` vem como `pt-BR` (ou `pt_BR.ISO8859-1`, `ca@valencia`,
  // `zh-Hans-CN`): fica só idioma_REGIÃO — sem encoding, modificador nem o
  // script de 4 letras, que o /usr/share/locale não usa — e o encoding vira UTF-8.
  final base = (localeName ?? Platform.localeName)
      .split(RegExp('[.@]'))
      .first
      .split(RegExp('[-_]'))
      .where((part) => part.length != 4)
      .join('_');
  final candidate = '$base.UTF-8';
  final lang = base.isNotEmpty && exists(candidate) ? candidate : 'en_US.UTF-8';
  return {...env, 'LANG': lang};
}
