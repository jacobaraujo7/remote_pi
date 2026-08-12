import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:cockpit/app/core/ui/themes/app_colors.dart';
import 'package:cockpit/app/core/ui/themes/syntax_colors.dart';
import 'package:cockpit/app/core/ui/themes/terminal_theme.dart';
import 'package:cockpit/app/core/ui/themes/theme_codec.dart';
import 'package:cockpit/app/core/ui/themes/theme_spec.dart';
import 'package:flutter/widgets.dart';

/// Id do tema que sempre existe. Persistir um id (e não um enum) é o que abre
/// espaço para temas custom sem migração a cada tema novo.
const String kDefaultThemeId = 'cockpit';

/// O tema oficial do Cockpit, e a raiz de todos os outros built-in.
///
/// Também é a **base implícita** de qualquer tema importado sem `extends`: é o
/// que garante que um arquivo com três tokens ainda gere um app inteiro
/// pintado.
///
/// O realce de código é o GitHub (não o One): é a paleta que casa com as
/// superfícies neutras da UI do Cockpit, e a que a maioria já reconhece de
/// olhar código no navegador.
final CockpitThemeSpec cockpitDefaultTheme = CockpitThemeSpec(
  id: kDefaultThemeId,
  name: 'Cockpit',
  author: 'Remote Pi',
  dark: _variant(
    ui: AppColors.dark,
    syntax: SyntaxColors.githubDark,
    terminal: cockpitTerminalThemeDark,
  ),
  light: _variant(
    ui: AppColors.light,
    syntax: SyntaxColors.githubLight,
    terminal: cockpitTerminalThemeLight,
  ),
);

/// **Cockpit 2** — a hierarquia de superfícies invertida.
///
/// No tema oficial o *chrome* (rail de projetos, árvore de arquivos, painéis de
/// tasks/busca, tab strip) é a camada mais profunda, e o corpo da aba fica uma
/// nota acima. Aqui é o contrário: o chrome sobe e o **conteúdo da aba afunda**,
/// virando a região mais escura da janela.
///
/// A troca é literalmente entre dois tokens — `bg` pinta o chrome e `panel`
/// pinta o corpo da aba —, então o tema inteiro cabe num `copyWith`. Ela muda a
/// leitura da tela: em vez do conteúdo flutuar sobre o chrome, o chrome
/// emoldura o conteúdo. Rende melhor em telas grandes, onde o corpo da aba
/// domina a área e um fundo mais fundo cansa menos.
///
/// `panel2`/`panel3` seguem *acima* do chrome: são as camadas elevadas
/// (seleção do rail, composer, cards, hover), e precisam ler como elevação nos
/// dois lugares — sobre o chrome claro **e** sobre o conteúdo escuro.
///
/// Mesmo realce de código do oficial (GitHub): a mudança aqui é de superfície,
/// não de sintaxe.
final CockpitThemeSpec cockpit2Theme = CockpitThemeSpec(
  id: 'cockpit.2',
  name: 'Cockpit 2',
  author: 'Remote Pi',
  dark: _variant(
    // O conteúdo afunda, mas **não** até o quase-preto: o corpo da aba é onde o
    // olho fica o tempo todo, e um fundo fundo demais aumenta o contraste com o
    // texto a ponto de cansar. Ele fica um degrau abaixo do chrome, o
    // suficiente para a inversão se ler, e ainda acima do `bg` do tema oficial.
    ui: AppColors.dark.copyWith(
      bg: const Color(0xFF24242A), // chrome sobe
      panel: const Color(0xFF1B1B1F), // corpo da aba afunda (sem exagero)
      panel2: const Color(0xFF2D2D34), // elevado sobre os dois
      panel3: const Color(0xFF37373F), // hover
      border: const Color(0xFF33333A), // acompanha: borda fina some se ficar
      border2: const Color(0xFF424249), // escura demais sobre superfície clara
      // Superfície mais clara come contraste do texto fraco: com os valores do
      // tema oficial, `text3` (placeholder, metadado) caía para 2,9:1 sobre o
      // chrome. Sobem junto para voltar acima de 3:1.
      text3: const Color(0xFF7C7C87),
      text4: const Color(0xFF5A5A62),
    ),
    syntax: SyntaxColors.githubDark,
    terminal: cockpitTerminalThemeDark,
  ),
  light: _variant(
    // Mesma inversão no claro: o oficial põe o chrome no cinza e o conteúdo no
    // branco; aqui o conteúdo é o cinza e o chrome sobe.
    //
    // O chrome **não** é branco puro de propósito. No claro a elevação também
    // sobe em luminância, e o branco é o teto: com o chrome em #FFFFFF não
    // sobraria nenhum tom acima dele para `panel2` (composer, cards, seleção
    // do rail) ler como camada elevada. Deixando o chrome um passo abaixo do
    // branco, o branco fica reservado para o que de fato flutua.
    //
    // Com o chrome preso ao teto, o quanto o conteúdo afunda é a única
    // liberdade real — e ele afunda **pouco**: o corpo da aba é onde moram o
    // código e o terminal, e um cinza fechado ali pesa o dia inteiro. Em
    // `#F0F0F5` a inversão vale 1,09, a mesma separação painel/conteúdo do
    // Cockpit 1 — tão legível quanto o arranjo clássico, só invertida.
    ui: AppColors.light.copyWith(
      bg: const Color(0xFFFAFAFC), // chrome — quase branco, mas não o teto
      panel: const Color(0xFFF0F0F5), // corpo da aba afunda (de leve)
      panel2: const Color(0xFFFFFFFF), // elevado = o branco reservado
      panel3: const Color(0xFFDFDFE7), // hover (no claro, escurece)
      border: const Color(0xFFE0E0E7),
      border2: const Color(0xFFCACAD4),
      // O conteúdo afundado não é branco, então o texto fraco perde contraste
      // ali: com o valor do tema oficial, `text3` (placeholder, metadado)
      // ficava a 2,8:1 dentro da aba. Simétrico ao ajuste que o variant escuro
      // já precisou.
      text3: const Color(0xFF7A7A85),
      text4: const Color(0xFFA2A2AC),
    ),
    syntax: SyntaxColors.githubLight,
    terminal: cockpitTerminalThemeLight,
  ),
);

/// Monta um variant built-in com o **campo unificado**.
///
/// Viewer de código, editor e terminal são a mesma coisa do ponto de vista da
/// janela: conteúdo dentro da aba. Antes cada um trazia o próprio fundo — o
/// terminal seguia o tema, e o código vinha com o fundo da paleta de syntax
/// (o `#0D1117` do GitHub, por exemplo). Duas abas lado a lado mostravam dois
/// pretos diferentes, e a emenda aparecia.
///
/// Aqui os três recebem `ui.panel`. A paleta de syntax continua mandando nas
/// **cores do código**; só o campo atrás dele passa a ser do tema.
///
/// O terminal passa pelo mesmo codec que lê tema de arquivo, de propósito:
/// garante que um built-in nosso não usa nenhum caminho que um tema do usuário
/// não teria.
ThemeVariant _variant({
  required AppColors ui,
  required SyntaxColors syntax,
  required TerminalTheme terminal,
  Map<String, Object?> terminalOverrides = const {},
}) => ThemeVariant(
  ui: ui,
  syntax: syntax.copyWith(background: ui.panel),
  terminal: terminalThemeFromJson({
    'background': encodeHexColor(ui.panel),
    ...terminalOverrides,
  }, base: terminal),
);

/// **Pantera** — preto absoluto no escuro, branco absoluto no claro.
///
/// É o único tema em que **painel e conteúdo têm a mesma cor**: os dois são
/// `#000000` (ou `#FFFFFF`). A hierarquia que os outros temas fazem com
/// degraus de superfície, este faz com **borda** — o traço entre o rail e a
/// aba é a fronteira, não a diferença de tom.
///
/// Isso é uma escolha, não um descuido, e custa alguma coisa: sem degrau de
/// superfície, uma borda que suma leva junto a leitura de onde termina um
/// painel e começa o outro. Por isso as bordas aqui são **mais fortes** que as
/// de qualquer outro tema (1,59 de razão contra o preto, ante ~1,1 do
/// Cockpit).
///
/// O que **não** colapsa: `panel2` (composer, cards) e `panel3` (hover)
/// continuam separados. Eles não têm borda para se apoiar — um card invisível
/// e um hover que não responde seriam defeito, não estilo.
///
/// A marca é acromática (branco no escuro, preto no claro): num tema sem cor,
/// um accent colorido seria a única cor da tela e roubaria a ideia. As cores
/// de **estado** (erro, aviso, git) ficam: elas carregam informação, e um tema
/// monocromático que esconde um erro cobra caro pela estética.
final CockpitThemeSpec panteraTheme = CockpitThemeSpec(
  id: 'pantera',
  name: 'Pantera',
  author: 'Remote Pi',
  dark: _variant(
    ui: AppColors.dark.copyWith(
      bg: const Color(0xFF000000), // painéis
      panel: const Color(0xFF000000), // conteúdo — a MESMA cor, de propósito
      panel2: const Color(0xFF101010), // elevado (sem borda para se apoiar)
      panel3: const Color(0xFF1E1E1E), // hover
      border: const Color(0xFF303030), // a borda é a estrutura aqui
      border2: const Color(0xFF454545),
      text: const Color(0xFFF5F5F5),
      text2: const Color(0xFFA3A3A3),
      text3: const Color(0xFF737373),
      text4: const Color(0xFF4D4D4D),
      accent: const Color(0xFFFFFFFF),
      accentText: const Color(0xFFE5E5E5),
      accentSoft: const Color(0x33FFFFFF),
    ),
    syntax: SyntaxColors.githubDark,
    terminal: cockpitTerminalThemeDark,
    terminalOverrides: {'cursor': '#FFFFFF', 'selection': '#FFFFFF33'},
  ),
  light: _variant(
    ui: AppColors.light.copyWith(
      bg: const Color(0xFFFFFFFF),
      panel: const Color(0xFFFFFFFF),
      panel2: const Color(0xFFF4F4F4),
      panel3: const Color(0xFFE8E8E8),
      border: const Color(0xFFD0D0D0),
      border2: const Color(0xFFB8B8B8),
      text: const Color(0xFF0A0A0A),
      text2: const Color(0xFF525252),
      text3: const Color(0xFF6E6E6E),
      text4: const Color(0xFF9E9E9E),
      accent: const Color(0xFF000000),
      accentText: const Color(0xFF171717),
      accentSoft: const Color(0x14000000),
    ),
    syntax: SyntaxColors.githubLight,
    terminal: cockpitTerminalThemeLight,
    terminalOverrides: {'cursor': '#000000', 'selection': '#00000014'},
  ),
);

/// **Flexoki** — esquema de tinta de [Steph Ango](https://stephango.com/flexoki).
///
/// Não é um Cockpit tingido: a paleta inteira (UI, syntax e ANSI) vem do
/// Flexoki. O arranjo é o clássico do Cockpit 1 — chrome mais fundo, conteúdo
/// um degrau acima — porque as bases oficiais (`black`/`base-950` no escuro,
/// `base-50`/`paper` no claro) já nascem nessa ordem.
///
/// A marca é o **ciano**, não o laranja da família: o laranja Flexoki fica a
/// <20° do vermelho de erro, e o teste de separação marca/estado (o mesmo que
/// empurrou o Rosê para o magenta) reprovaria. Ciano é da paleta, se separa
/// limpo de erro e aviso, e ainda lê como "Flexoki" — não como o azul da marca
/// Remote Pi.
///
/// Syntax e terminal usam as séries oficiais (400 no escuro, 600 no claro). O
/// fundo do código/terminal continua sendo `ui.panel`, como em todo built-in.
final CockpitThemeSpec flexokiTheme = CockpitThemeSpec(
  id: 'flexoki',
  name: 'Flexoki',
  author: 'Steph Ango',
  dark: _variant(
    ui: AppColors.dark.copyWith(
      bg: const Color(0xFF100F0F), // black — chrome
      panel: const Color(0xFF1C1B1A), // base-950 — conteúdo
      panel2: const Color(0xFF282726), // base-900 — elevado
      panel3: const Color(0xFF343331), // base-850 — hover
      border: const Color(0xFF282726),
      border2: const Color(0xFF403E3C), // base-800
      text: const Color(0xFFCECDC3), // base-200
      text2: const Color(0xFF878580), // base-500
      // base-700 (#575653) e base-600 (#6F6E69) caem abaixo de 3:1 sobre o
      // elevado — sobe para base-500, o mesmo piso que o Cockpit 2 precisou.
      text3: const Color(0xFF878580),
      text4: const Color(0xFF575653), // base-700
      accent: const Color(0xFF3AA99F), // cyan-400
      accentText: const Color(0xFF3AA99F),
      accentSoft: const Color(0x333AA99F),
      online: const Color(0xFF879A39), // green-400
      ok: const Color(0xFF879A39),
      error: const Color(0xFFD14D41), // red-400
      warn: const Color(0xFFD0A215), // yellow-400
      edited: const Color(0xFFD0A215),
      editedBg: const Color(0xFF242018),
      gitStaged: const Color(0xFF879A39),
      gitUntracked: const Color(0xFF4385BE), // blue-400
      gitDeleted: const Color(0xFFD14D41),
      gitConflict: const Color(0xFFDA702C), // orange-400
    ),
    syntax: SyntaxColors.flexokiDark,
    terminal: cockpitTerminalThemeDark,
    terminalOverrides: {
      'cursor': '#3AA99F',
      'selection': '#3AA99F33',
      'foreground': '#CECDC3',
      'black': '#100F0F',
      'red': '#D14D41',
      'green': '#879A39',
      'yellow': '#D0A215',
      'blue': '#4385BE',
      'magenta': '#CE5D97',
      'cyan': '#3AA99F',
      'white': '#CECDC3',
      'brightBlack': '#878580',
      'brightRed': '#D14D41',
      'brightGreen': '#879A39',
      'brightYellow': '#D0A215',
      'brightBlue': '#4385BE',
      'brightMagenta': '#CE5D97',
      'brightCyan': '#3AA99F',
      'brightWhite': '#FFFCF0',
      'searchHitBackground': '#D0A215',
      'searchHitBackgroundCurrent': '#3AA99F',
      'searchHitForeground': '#100F0F',
    },
  ),
  light: _variant(
    ui: AppColors.light.copyWith(
      bg: const Color(0xFFF2F0E5), // base-50 — chrome
      panel: const Color(0xFFFFFCF0), // paper — conteúdo
      panel2: const Color(0xFFE6E4D9), // base-100 — elevado
      panel3: const Color(0xFFDAD8CE), // base-150 — hover
      border: const Color(0xFFDAD8CE),
      border2: const Color(0xFFCECDC3), // base-200
      text: const Color(0xFF100F0F), // black
      text2: const Color(0xFF6F6E69), // base-600
      // base-500 (#878580) fica a 2,9:1 sobre o elevado — desce para base-600.
      text3: const Color(0xFF6F6E69),
      text4: const Color(0xFF878580), // base-500
      accent: const Color(0xFF24837B), // cyan-600
      accentText: const Color(0xFF24837B),
      accentSoft: const Color(0x2224837B),
      online: const Color(0xFF66800B), // green-600
      ok: const Color(0xFF66800B),
      error: const Color(0xFFAF3029), // red-600
      warn: const Color(0xFFAD8301), // yellow-600
      edited: const Color(0xFFAD8301),
      editedBg: const Color(0xFFF5EED6),
      gitStaged: const Color(0xFF66800B),
      gitUntracked: const Color(0xFF205EA6), // blue-600
      gitDeleted: const Color(0xFFAF3029),
      gitConflict: const Color(0xFFBC5215), // orange-600
    ),
    syntax: SyntaxColors.flexokiLight,
    terminal: cockpitTerminalThemeLight,
    terminalOverrides: {
      // No claro a série 400 some sobre o papel (yellow-400 a 2,3:1) — a 600
      // é a que o próprio Flexoki pede para temas claros.
      'cursor': '#24837B',
      'selection': '#24837B22',
      'foreground': '#100F0F',
      'black': '#100F0F',
      'red': '#AF3029',
      'green': '#66800B',
      'yellow': '#AD8301',
      'blue': '#205EA6',
      'magenta': '#A02F6F',
      'cyan': '#24837B',
      'white': '#6F6E69',
      'brightBlack': '#878580',
      'brightRed': '#AF3029',
      'brightGreen': '#66800B',
      'brightYellow': '#AD8301',
      'brightBlue': '#205EA6',
      'brightMagenta': '#A02F6F',
      'brightCyan': '#24837B',
      'brightWhite': '#100F0F',
      'searchHitBackground': '#D0A215',
      'searchHitBackgroundCurrent': '#24837B',
      'searchHitForeground': '#100F0F',
    },
  ),
);

// ---------------------------------------------------------------------------
// Famílias de tom
// ---------------------------------------------------------------------------

/// Aplica um tom a uma paleta neutra, preservando a **estrutura** dela.
///
/// Um tema de cor não é um conjunto novo de superfícies: é o mesmo arranjo com
/// outro tom. Derivar (em vez de escrever 25 hexes à mão) garante que Violet
/// herde de graça toda a calibragem do Cockpit correspondente — a inversão do
/// Cockpit 2, os degraus de elevação, o contraste dos textos fracos —, e que um
/// ajuste no Cockpit se propague em vez de criar divergência silenciosa.
///
/// A conversão é em HSL: troca matiz e saturação, **mantém a luminosidade**.
/// Por isso a ordem das superfícies (o que é mais fundo, o que é mais alto)
/// sobrevive à tintura, e os testes de estrutura continuam valendo.
///
/// Só os **neutros** são tingidos. `error`/`warn`/`online` e os status de git
/// ficam intactos de propósito: vermelho tem de continuar lendo como vermelho,
/// senão o tema custa informação em vez de custar só gosto.
///
/// [panel] escapa da tintura por um limite da própria conversão: em HSL, a
/// saturação **não rende cor perto do branco** — em `L = 1.0` não rende nada
/// (branco é branco em qualquer matiz) e em `L ≈ 0.98` rende um ponto de
/// diferença. O campo claro dos temas de cor é justamente essa faixa, então
/// ele chega pronto em vez de derivado. Compensar por fórmula (subir a
/// saturação conforme a luminosidade sobe) contaminaria as superfícies médias
/// dos outros temas, que estão calibradas.
///
/// [warn] é a outra exceção, e existe por causa do Sun: quando a **marca** é
/// dourada, o âmbar de aviso vira a cor do app e para de avisar. Aí o `warn`
/// se desloca para o laranja — continua significando cuidado, mas volta a se
/// distinguir. Preservar o significado é a regra; preservar o hex era só o
/// jeito usual de cumpri-la.
AppColors _tinted(
  AppColors base, {
  required double hue,
  required double surfaceSaturation,
  required Color accent,
  required Color accentText,
  required Color accentSoft,
  Color? warn,
  Color? panel,
}) {
  Color tint(Color c, double saturation) =>
      HSLColor.fromColor(c).withHue(hue).withSaturation(saturation).toColor();

  // Texto recebe menos tom que superfície: um cinza muito tingido lê como cor
  // (parece link/estado), não como texto.
  const textSaturation = 0.09;

  return base.copyWith(
    bg: tint(base.bg, surfaceSaturation),
    panel: panel ?? tint(base.panel, surfaceSaturation),
    panel2: tint(base.panel2, surfaceSaturation),
    panel3: tint(base.panel3, surfaceSaturation),
    border: tint(base.border, surfaceSaturation),
    border2: tint(base.border2, surfaceSaturation),
    text: tint(base.text, textSaturation),
    text2: tint(base.text2, textSaturation),
    text3: tint(base.text3, textSaturation),
    text4: tint(base.text4, textSaturation),
    scrim: base.scrim,
    shadow: base.shadow,
    accent: accent,
    accentText: accentText,
    accentSoft: accentSoft,
    warn: warn,
  );
}

/// Uma família de tom: o matiz e como a marca se comporta em cada brilho.
///
/// Existe para que um tema de cor novo seja uma declaração, não uma cópia de 25
/// hexes. O arranjo de superfícies vem sempre de um Cockpit; isto aqui é só a
/// camada de tom por cima.
@immutable
class _Hue {
  const _Hue({
    required this.hue,
    required this.darkSaturation,
    required this.lightSaturation,
    required this.darkAccent,
    required this.darkAccentText,
    required this.lightAccent,
    required this.lightAccentText,
    this.lightChrome,
    this.lightRaised,
    this.darkWarn,
    this.lightWarn,
  });

  final double hue;

  /// Quanto tom entra nas superfícies. No claro pode (e deve) ser maior: sobre
  /// branco o olho lê muito menos tinta do que sobre preto com o mesmo número.
  final double darkSaturation;
  final double lightSaturation;

  final Color darkAccent;
  final Color darkAccentText;
  final Color lightAccent;
  final Color lightAccentText;

  /// Painel do modo claro, em valor **neutro** (a tintura entra depois).
  /// `null` = usar o de [_deepChromeLightBase].
  ///
  /// Existe porque luminância igual não é peso visual igual: um tom quente lê
  /// mais pesado que um frio no mesmo valor. Medindo, o painel claro do Rosê e
  /// o do Midnight têm a *mesma* luminância (0,81) — e mesmo assim o rosé
  /// parecia escuro demais enquanto o marinho estava certo. Não é ilusão do
  /// olho a corrigir com número: é o número que precisa ceder ao olho. Famílias
  /// quentes sobem o painel aqui; as frias deixam `null`.
  final Color? lightChrome;

  /// Camada elevada do modo claro (composer, cards, seleção do rail), também em
  /// valor neutro. `null` = a do tema base.
  ///
  /// Anda junto com [lightChrome]: conforme o painel sobe, ele **cruza** o
  /// valor do elevado. Abaixo do cruzamento o elevado lê como camada acima do
  /// painel (Midnight); acima, lê como recuo (Rosê). Os dois funcionam — o que
  /// não funciona é parar em cima, que foi onde o Sun caiu na primeira
  /// tentativa: painel e elevado a 1,008 de razão, indistinguíveis. Quem sobe o
  /// painel para perto do elevado precisa tirar o elevado da frente.
  final Color? lightRaised;

  /// Substitui o âmbar de aviso quando a **marca** ocupa o mesmo matiz.
  /// `null` = manter o do tema base. Ver [_tinted] e [_sun].
  final Color? darkWarn;
  final Color? lightWarn;
}

/// Violet — roxo-azulado, vizinho do azul da marca: o app muda de temperatura
/// sem deixar de parecer o mesmo produto.
const _Hue _violet = _Hue(
  hue: 264,
  darkSaturation: 0.16,
  lightSaturation: 0.30,
  darkAccent: Color(0xFF9B7BF7),
  darkAccentText: Color(0xFFCDBAFD),
  lightAccent: Color(0xFF7C3AED),
  lightAccentText: Color(0xFF6027C8),
);

/// Midnight — azul-marinho profundo. O tom é mais forte que o do Violet de
/// propósito: aqui a cor **é** o tema, não um tempero sobre o cinza.
///
/// A marca é o **próprio azul do Cockpit**, e não um azul mais claro puxado
/// para destacar do fundo. Um azul mais claro destacaria mais (5,3:1 contra
/// 3,9:1), mas cruzaria o ponto em que o texto legível sobre ele passa a ser
/// escuro — e botão azul com texto escuro lê como defeito, não como tema. Com
/// o azul da marca o botão do Midnight fica idêntico ao do Cockpit (branco a
/// 4,5:1) e ainda se separa do marinho com folga sobre o mínimo de 3:1 que
/// vale para elemento não-textual.
const _Hue _midnight = _Hue(
  hue: 220,
  darkSaturation: 0.26,
  lightSaturation: 0.34,
  darkAccent: Color(0xFF2F6FF0),
  darkAccentText: Color(0xFF93B8FF),
  lightAccent: Color(0xFF1D5FD8),
  lightAccentText: Color(0xFF1A4CAC),
);

/// Constrói um tema a partir de um Cockpit, herdando dele o arranjo de
/// superfícies e trocando só o tom.
/// [darkFrom]/[lightFrom] são independentes de propósito: um arranjo que
/// funciona no escuro pode não funcionar no claro. A inversão do Cockpit 2 é
/// justamente esse caso — ver [midnightTheme].
/// [lightContent] é o campo claro (código, terminal, corpo da aba) **já
/// tingido** — ver o parâmetro `panel` de [_tinted] para o porquê de não ser
/// derivado. Fica aqui, e não no [_Hue], porque depende do **arranjo**: só faz
/// sentido onde o campo claro é quase-branco. O Violet prova a diferença —
/// mesmo matiz, dois arranjos: o Violet 1 tem campo branco (e precisa de tom),
/// o Violet 2 tem campo cinza (e não precisa).
///
/// `null` = o campo da base. Branco puro é o que os temas de cor tinham, e é o
/// que destoava: painéis com tom e conteúdo sem nenhum, como um recorte branco
/// colado por cima do tema.
CockpitThemeSpec _tintedThemeOf(
  _Hue tone, {
  required String id,
  required String name,
  required ThemeVariant darkFrom,
  required ThemeVariant lightFrom,
  Color? lightContent,
}) => CockpitThemeSpec(
  id: id,
  name: name,
  author: 'Remote Pi',
  dark: _tintedVariant(
    darkFrom,
    tone,
    saturation: tone.darkSaturation,
    accent: tone.darkAccent,
    accentText: tone.darkAccentText,
    accentSoft: tone.darkAccent.withValues(alpha: 0.20),
    syntax: SyntaxColors.githubDark,
    warn: tone.darkWarn,
  ),
  light: _tintedVariant(
    tone.lightChrome == null
        ? lightFrom
        : ThemeVariant(
            ui: lightFrom.ui.copyWith(
              bg: tone.lightChrome,
              panel2: tone.lightRaised,
            ),
            syntax: lightFrom.syntax,
            terminal: lightFrom.terminal,
          ),
    tone,
    saturation: tone.lightSaturation,
    accent: tone.lightAccent,
    accentText: tone.lightAccentText,
    accentSoft: tone.lightAccent.withValues(alpha: 0.13),
    syntax: SyntaxColors.githubLight,
    warn: tone.lightWarn,
    panel: lightContent,
  ),
);

ThemeVariant _tintedVariant(
  ThemeVariant base,
  _Hue tone, {
  required double saturation,
  required Color accent,
  required Color accentText,
  required Color accentSoft,
  required SyntaxColors syntax,
  Color? warn,
  Color? panel,
}) {
  final ui = _tinted(
    base.ui,
    hue: tone.hue,
    surfaceSaturation: saturation,
    accent: accent,
    accentText: accentText,
    accentSoft: accentSoft,
    warn: warn,
    panel: panel,
  );
  return _variant(
    ui: ui,
    syntax: syntax,
    terminal: base.terminal,
    // Cursor e seleção são chrome do terminal, então seguem a marca. As 16
    // cores ANSI **não** são tocadas: `blue` tem de continuar azul para a
    // saída de qualquer programa fazer sentido.
    terminalOverrides: {
      'cursor': encodeHexColor(accent),
      'selection': encodeHexColor(accentSoft),
    },
  );
}

/// **Violet 1** — o arranjo do Cockpit oficial em roxo.
final CockpitThemeSpec violet1Theme = _tintedThemeOf(
  _violet,
  id: 'violet',
  name: 'Violet 1',
  darkFrom: cockpitDefaultTheme.dark!,
  lightFrom: cockpitDefaultTheme.light!,
  lightContent: const Color(0xFFFCFAFF),
);

/// **Violet 2** — o arranjo invertido do Cockpit 2 em roxo: chrome acima,
/// corpo da aba afundado.
final CockpitThemeSpec violet2Theme = _tintedThemeOf(
  _violet,
  id: 'violet.2',
  name: 'Violet 2',
  darkFrom: cockpit2Theme.dark!,
  lightFrom: cockpit2Theme.light!,
);

/// Base do **claro** dos temas de cor: o arranjo do Cockpit 1 (chrome fundo,
/// conteúdo no topo) com o chrome puxado mais um passo para baixo.
///
/// A inversão do Cockpit 2 não sobrevive ao modo claro. No escuro ela funciona
/// porque sobra range abaixo do chrome para o conteúdo afundar. No claro o
/// chrome tem de ficar quase branco para o conteúdo caber acima dele — e aí a
/// tela vira dois cinzas quase iguais, sem hierarquia: os painéis param de
/// emoldurar coisa nenhuma.
///
/// Então aqui o claro volta ao arranjo clássico, e o chrome desce um degrau
/// além do Cockpit 1. Isso devolve a separação painel/conteúdo que o modo claro
/// perde, e dá ao claro a mesma leitura do escuro: painéis como moldura,
/// conteúdo como campo.
///
/// Todo tema de cor nasce daqui no claro — a lição vale para o matiz que for.
final ThemeVariant _deepChromeLightBase = ThemeVariant(
  ui: AppColors.light.copyWith(
    bg: const Color(0xFFE8E8EF), // painéis mais fundos que no Cockpit 1
    panel3: const Color(0xFFDDDDE6),
    border: const Color(0xFFD8D8E1),
    border2: const Color(0xFFC3C3CF),
    // Painel mais fundo come contraste do texto fraco — o mesmo efeito que o
    // Cockpit 2 sofreu no escuro, aqui espelhado. Com os valores do Cockpit 1,
    // `text3` caía para 2,8:1 sobre o painel; escurecem para voltar acima de
    // 3:1 sem virar texto primário.
    text3: const Color(0xFF787883),
    text4: const Color(0xFF9C9CA8),
  ),
  syntax: SyntaxColors.githubLight,
  terminal: cockpitTerminalThemeLight,
);

/// **Midnight** — azul-marinho, com arranjo **diferente por brilho**.
///
/// Escuro: a inversão do Cockpit 2 (conteúdo afundado), que é o que faz o
/// marinho ler como "noite" em vez de "azulzinho no fundo".
/// Claro: o arranjo clássico do Cockpit 1 com o chrome reforçado — ver
/// [_deepChromeLightBase] para o porquê.
final CockpitThemeSpec midnightTheme = _tintedThemeOf(
  _midnight,
  id: 'midnight',
  name: 'Midnight',
  darkFrom: cockpit2Theme.dark!,
  lightFrom: _deepChromeLightBase,
  lightContent: const Color(0xFFF7FAFF),
);

/// Rosê — rosa de vinho: quente, saturado no ponto de virar identidade sem
/// virar doce. O matiz mais quente da casa, então entra com **menos**
/// saturação nas superfícies que o Midnight: vermelho em baixa luminosidade
/// embarra rápido, e o que era para ser rosé vira marrom.
///
/// A marca é um rosa fechado (e não o rosa claro que primeiro vem à cabeça)
/// pela mesma razão do Midnight: o rosa claro cruzaria o ponto em que o texto
/// legível sobre o botão passa a ser escuro. Assim o botão fica branco sobre
/// rosa a 4,6:1, e ainda se separa do campo a 3,8:1.
///
/// E ela puxa para o **magenta**, não para o vermelho. O rosa "natural" desta
/// família (`#E11D48`, matiz 347) fica a 11° do vermelho de erro — perto
/// demais: num tema rosé, um estado de erro que parece a cor da marca deixa de
/// avisar. Em 333° a distância triplica e o vermelho volta a significar
/// vermelho. Foi a mesma preocupação que manteve `error`/`warn`/git fora da
/// tintura; aqui ela alcançou também a escolha da marca.
const _Hue _rose = _Hue(
  hue: 342,
  darkSaturation: 0.18,
  lightSaturation: 0.30,
  darkAccent: Color(0xFFDB2777),
  darkAccentText: Color(0xFFF9A8D4),
  lightAccent: Color(0xFFBE185D),
  lightAccentText: Color(0xFF9D174D),
  // Sobe o painel claro: ver [_Hue.lightChrome]. Aqui o painel chega à mesma
  // luminância do Cockpit 1 (0,914) — o rosa fica no tom, não no peso. A
  // separação painel/conteúdo cai para 1,09, igual à do oficial: é o piso, não
  // um degrau a descer de novo. Abaixo disso o painel encosta no branco do
  // conteúdo e a moldura some — que é justamente o defeito do Cockpit 2 claro.
  lightChrome: Color(0xFFF4F4F9),
);

/// Sun — dourado. O matiz mais quente da casa, e o mais problemático: é
/// **exatamente** onde vive o âmbar de aviso.
///
/// Nenhum ajuste de matiz resolvia isso — `warn` nasce em 38°, e um dourado
/// fora dessa vizinhança deixa de ser dourado. Então quem se move é o `warn`:
/// vira laranja (21° no escuro, 26° no claro), mantendo ≥20° tanto da marca
/// quanto do vermelho de erro. Continua lendo como cuidado, e volta a se
/// distinguir do app.
///
/// A marca **clara** puxa mais para o amarelo (48°) que a escura (45°) para
/// abrir esse espaço: com 42° a janela entre erro e marca ficava estreita
/// demais para o `warn` caber com folga dos dois lados.
///
/// Saturação de superfície é a menor de todas (0,13 no escuro): amarelo em
/// baixa luminosidade vira mostarda suja mais rápido que qualquer outro matiz.
const _Hue _sun = _Hue(
  hue: 44,
  darkSaturation: 0.13,
  lightSaturation: 0.30,
  darkAccent: Color(0xFFEAB308),
  darkAccentText: Color(0xFFFDE68A),
  lightAccent: Color(0xFF876B00),
  lightAccentText: Color(0xFF7A5E00),
  // Amarelo tem a maior luminância por unidade de tinta, então o painel claro
  // já sobe sozinho: precisa de menos empurrão que o do Rosê. Mas esse valor
  // cai justamente em cima do elevado padrão (#F0F0F3), então o elevado desce
  // para reabrir o degrau — ver [_Hue.lightRaised].
  lightChrome: Color(0xFFF0F0F5),
  lightRaised: Color(0xFFE9E9EE),
  darkWarn: Color(0xFFE8703A),
  lightWarn: Color(0xFFB45309),
);

/// **Sun** — dourado, mesmo arranjo por brilho do Midnight e do Rosê.
final CockpitThemeSpec sunTheme = _tintedThemeOf(
  _sun,
  id: 'sun',
  name: 'Sun',
  darkFrom: cockpit2Theme.dark!,
  lightFrom: _deepChromeLightBase,
  lightContent: const Color(0xFFFFFDF7),
);

/// **Rosê** — mesmo arranjo por brilho do Midnight (ver [midnightTheme]):
/// invertido no escuro, clássico com chrome reforçado no claro.
final CockpitThemeSpec roseTheme = _tintedThemeOf(
  _rose,
  id: 'rose',
  name: 'Rosê',
  darkFrom: cockpit2Theme.dark!,
  lightFrom: _deepChromeLightBase,
  lightContent: const Color(0xFFFFF9FB),
);

/// Todos os temas que vêm no app, na ordem em que aparecem no seletor.
final List<CockpitThemeSpec> builtInThemes = [
  cockpitDefaultTheme,
  cockpit2Theme,
  violet1Theme,
  violet2Theme,
  midnightTheme,
  roseTheme,
  sunTheme,
  flexokiTheme,
  panteraTheme,
];

/// Resolve um built-in por id (`null` se não existe). É o `resolveBase` usado
/// pelo `extends` de temas importados.
CockpitThemeSpec? builtInThemeById(String id) {
  for (final theme in builtInThemes) {
    if (theme.id == id) return theme;
  }
  return null;
}
