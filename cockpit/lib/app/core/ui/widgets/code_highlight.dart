import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' as hl;

/// Extensões cujo nome **não** bate com o id do highlight.js e cuja gramática
/// não declara alias — precisam ser mapeadas na mão. As demais (rs, yml, sh,
/// toml, rb, py, c, h, …) já são resolvidas pelos aliases das próprias
/// gramáticas; e qualquer extensão desconhecida cai em texto puro (plaintext).
const Map<String, String> _extToLanguage = {
  'ts': 'typescript',
  // `.tsx`/`.jsx` vão pro grammar **javascript** de propósito: o grammar
  // `typescript` do highlight.js **não** entende JSX — ao topar `<Tag/>` ele
  // aborta (regra `illegal`) e devolve um único nó plaintext (nodes=1,
  // relevance=0), ou seja, zero realce. O `javascript` traz o sub-idioma xml e
  // pinta as tags JSX; perde-se só uns keywords TS (interface/enum), troca que
  // compensa (highlight vs. nada). `.ts` puro (sem JSX) fica no `typescript`.
  'tsx': 'javascript',
  'mts': 'typescript',
  'cts': 'typescript',
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'kt': 'kotlin',
  'kts': 'kotlin',
  // `.dbq` (DB tab, plano 51) é SQL com frontmatter em comentário — a
  // gramática sql pinta os dois.
  'dbq': 'sql',
  // `.ckp` (layout de orquestração de panes) é YAML puro.
  'ckp': 'yaml',
  // `.http`/`.rest` (REST Client / JetBrains HTTP Client) tem gramática
  // própria — a `http` do package é o wire format cru e aborta neste formato.
  'http': 'httpfile',
  'rest': 'httpfile',
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
};

/// Language id resolvido pelo **nome do arquivo**, para casos onde a extensão
/// sozinha não identifica a linguagem (dotfiles compostos): `.env` não tem
/// extensão e `.env.local`/`.env.qa` extraem `local`/`qa`. `null` quando o nome
/// não é especial — o caller cai no fluxo normal por extensão.
String? filenameLanguageOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name == '.env' || name.startsWith('.env.')) return 'dotenv';
  // go.mod não tem grammar no package (ext `mod` cai em plaintext); go.sum
  // pega carona (versões/strings — o resto fica neutro).
  if (name == 'go.mod' || name == 'go.sum') return 'gomod';
  // O grammar `dockerfile` existe no package; o que falta é detecção —
  // `Dockerfile` não tem extensão e `Dockerfile.dev`/`app.Dockerfile` extraem
  // `dev`/`dockerfile` (este último até funcionaria, mas normaliza aqui).
  if (name == 'dockerfile' ||
      name == 'containerfile' ||
      name.startsWith('dockerfile.') ||
      name.endsWith('.dockerfile')) {
    return 'dockerfile';
  }
  return null;
}

/// Gramáticas próprias (fora do catálogo do package `highlight`), registradas
/// uma vez no singleton antes do primeiro parse.
bool _customLanguagesRegistered = false;

void _ensureCustomLanguages() {
  if (_customLanguagesRegistered) return;
  _customLanguagesRegistered = true;
  hl.highlight.registerLanguage('dotenv', _dotenvMode());
  hl.highlight.registerLanguage('gomod', _goModMode());
  hl.highlight.registerLanguage('httpfile', _httpFileMode());
}

/// Gramática do arquivo `.http` (dialeto REST Client / JetBrains HTTP Client).
///
/// A gramática `http` do package **não** serve aqui: ela descreve o wire
/// format (`GET /x HTTP/1.1`), exige o sufixo `HTTP/1.1` na request-line e traz
/// `illegal: '\S'` no topo — ou seja, `###`, `@var` e `{{var}}` abortariam o
/// parse e o arquivo inteiro cairia em plaintext. Esta gramática cobre o
/// formato de arquivo: separador `###`, variáveis `@nome = valor`,
/// interpolação `{{nome}}`, request-line sem versão, headers, `< body.json` /
/// `> saida.json` e o body JSON como sub-idioma.
///
/// Mesma restrição do dotenv: lookahead `(?=...)` em `begin` não casa no port
/// Dart — as regras se ancoram em `^` e usam `returnBegin`/`excludeEnd`. E
/// **sem `illegal` no topo**: arquivo com sintaxe exótica degrada em realce
/// parcial em vez de sumir.
hl.Mode _httpFileMode() {
  final interpolation = hl.Mode(
    className: 'variable',
    begin: r'\{\{[^{}\n]*\}\}',
    relevance: 0,
  );
  final comment = hl.Mode(
    className: 'comment',
    begin: r'^[ \t]*(#|//)',
    end: r'$',
    relevance: 0,
  );
  return hl.Mode(
    case_insensitive: false,
    contains: [
      // `### Nome do request` — separador + rótulo. Vem antes do comentário
      // porque `###` também começa com `#`.
      hl.Mode(className: 'section', begin: r'^[ \t]*###.*$', relevance: 10),
      comment,
      // `@nome = valor` (declaração de variável do arquivo).
      hl.Mode(
        begin: r'^[ \t]*@[A-Za-z_][A-Za-z0-9_.-]*',
        returnBegin: true,
        relevance: 10,
        contains: [
          hl.Mode(
            className: 'attr',
            begin: r'@[A-Za-z_][A-Za-z0-9_.-]*',
            endsParent: true,
            relevance: 0,
          ),
        ],
        starts: hl.Mode(
          end: r'$',
          relevance: 0,
          contains: [
            hl.Mode(className: 'operator', begin: r'=', relevance: 0),
            interpolation,
          ],
        ),
      ),
      // Request-line: verbo + URL (a versão `HTTP/1.1` é opcional aqui).
      hl.Mode(
        begin:
            r'^[ \t]*(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT|GRAPHQL)[ \t]+',
        returnBegin: true,
        relevance: 10,
        contains: [
          hl.Mode(
            className: 'keyword',
            begin:
                r'(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT|GRAPHQL)',
            relevance: 0,
          ),
        ],
        starts: hl.Mode(
          end: r'$',
          relevance: 0,
          contains: [
            interpolation,
            hl.Mode(className: 'string', begin: r'[^ \t\n]+', relevance: 0),
          ],
        ),
      ),
      // `< ./body.json` (importa body) e `> ./out.json` (salva resposta).
      hl.Mode(
        className: 'meta',
        begin: r'^[ \t]*[<>][ \t]+\S.*$',
        relevance: 0,
      ),
      // Body JSON: começa na linha em branco seguida de `{` ou `[` e vai até o
      // próximo separador (ou o fim do arquivo). `returnBegin` devolve o
      // cursor para o sub-idioma ver o objeto inteiro.
      hl.Mode(
        begin: '\n[ \t]*\n[ \t]*[\\{\\[]',
        returnBegin: true,
        end: r'^[ \t]*###',
        returnEnd: true,
        subLanguage: ['json'],
        relevance: 0,
      ),
      // Header `Nome: valor` — só o nome é `attribute`; o valor segue neutro
      // (com interpolação pintada). O begin valida a linha inteira até o `:` e
      // `returnBegin` devolve o cursor: nada de `illegal` para delimitar o
      // nome, porque `illegal` num submode aborta o highlight do arquivo
      // **inteiro** (era o que apagava tudo em arquivo com script `> {% %}`).
      hl.Mode(
        begin: r'^[ \t]*[A-Za-z][A-Za-z0-9_-]*[ \t]*:',
        returnBegin: true,
        relevance: 0,
        contains: [
          hl.Mode(
            className: 'attribute',
            begin: r'[A-Za-z][A-Za-z0-9_-]*',
            endsParent: true,
            relevance: 0,
          ),
        ],
        starts: hl.Mode(end: r'$', relevance: 0, contains: [interpolation]),
      ),
      interpolation,
    ],
  );
}

/// Gramática go.mod/go.sum: diretivas no começo da linha (`module`, `require`,
/// `replace`, …) como keyword, versões `vX.Y.Z` como number, strings, `=>` do
/// replace e comentário `//`. Mesma restrição do dotenv: sem lookahead em
/// `begin`.
hl.Mode _goModMode() {
  return hl.Mode(
    contains: [
      hl.Mode(className: 'comment', begin: r'//', end: r'$', relevance: 0),
      hl.Mode(
        className: 'keyword',
        begin:
            r'^[ \t]*(module|go|toolchain|require|replace|exclude|retract|use)\b',
        relevance: 0,
      ),
      hl.Mode(className: 'string', begin: '"', end: '"', relevance: 0),
      hl.Mode(className: 'number', begin: r'\bv\d+\.[^\s/]+', relevance: 0),
      hl.Mode(className: 'keyword', begin: r'=>', relevance: 0),
    ],
  );
}

/// Gramática dotenv: comentário `#`, `export` opcional, chave (`attr`) até o
/// `=`, valor até o fim da linha com strings aspadas e interpolação
/// `$VAR`/`${VAR}` (`variable`). Estrutura espelha o grammar `properties` do
/// package: o begin externo valida a linha `chave=` inteira, `returnBegin`
/// devolve o cursor e os modes internos consomem keyword/chave, com `starts`
/// encadeando separador → valor. **Atenção**: lookahead `(?=...)` em `begin`
/// não casa no port Dart do highlight.js — por isso os modes internos
/// consomem os tokens direto (sem lookahead), validados pelo begin externo.
hl.Mode _dotenvMode() {
  final interpolation = hl.Mode(
    className: 'variable',
    variants: [
      hl.Mode(begin: r'\$\{[A-Za-z_][A-Za-z0-9_]*\}'),
      hl.Mode(begin: r'\$[A-Za-z_][A-Za-z0-9_]*'),
    ],
    relevance: 0,
  );
  final comment = hl.Mode(
    className: 'comment',
    begin: r'#',
    end: r'$',
    relevance: 0,
  );
  final value = hl.Mode(
    end: r'$',
    relevance: 0,
    contains: [
      hl.Mode(
        className: 'string',
        begin: '"',
        end: '"',
        contains: [
          hl.Mode(begin: r'\\.'),
          interpolation,
        ],
      ),
      hl.Mode(className: 'string', begin: "'", end: "'"),
      interpolation,
      comment,
    ],
  );
  return hl.Mode(
    contains: [
      comment,
      hl.Mode(
        begin: r'^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=',
        returnBegin: true,
        relevance: 0,
        contains: [
          hl.Mode(className: 'keyword', begin: r'export[ \t]+', relevance: 0),
          hl.Mode(
            className: 'attr',
            begin: r'[A-Za-z_][A-Za-z0-9_.-]+',
            endsParent: true,
            relevance: 0,
          ),
        ],
        starts: hl.Mode(end: r'[ \t]*=[ \t]*', relevance: 0, starts: value),
      ),
    ],
  );
}

/// Teto pra ligar o highlight. Acima disso o parse + a árvore de spans não
/// compensam (e o reader já corta arquivos em 2MB); cai no texto puro.
const int _kMaxHighlightChars = 200 * 1024;

/// Um range de diagnostic já convertido para **offsets** lineares no texto
/// (code units UTF-16) — ver `CodeEditingController.offsetFor`. `[start, end)`.
class DiagnosticRange {
  const DiagnosticRange(this.start, this.end, this.severity);

  final int start;
  final int end;
  final LspSeverity severity;
}

/// Um intervalo casado pela busca **no arquivo** (Cmd+F), em offsets lineares
/// UTF-16 `[start, end)`. Pintado com fundo destacado sobre o syntax highlight.
class MatchSpan {
  const MatchSpan(this.start, this.end);

  final int start;
  final int end;
}

/// Um token semântico já convertido para offsets lineares UTF-16 `[start, end)`,
/// com o tipo semântico do LSP (ex: `'class'`, `'variable'`).
class SemanticRange {
  const SemanticRange(this.start, this.end, this.tokenType);

  final int start;
  final int end;
  final String tokenType;
}

/// Converte diagnostics do LSP (posições `line`/`character`, base 0, UTF-16) em
/// [DiagnosticRange]s de offset linear sobre [text]. As code units UTF-16 do LSP
/// batem 1:1 com a `String` Dart — é só aritmética de offset (nunca
/// `.runes`/`.characters`). Posições defasadas são clampadas; ranges de largura
/// zero viram 1 caractere para terem um glifo a sublinhar. Reusada pelo editor
/// (via controller) e pelo viewer read-only.
List<DiagnosticRange> diagnosticRangesFor(
  String text,
  List<LspDiagnostic> diagnostics,
) {
  if (diagnostics.isEmpty) return const <DiagnosticRange>[];

  // Índice de início de cada linha (offset logo após cada '\n').
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }

  int offsetFor(int line, int character) {
    if (line < 0) return 0;
    if (line >= lineStarts.length) return text.length;
    final base = lineStarts[line];
    final contentEnd = line + 1 < lineStarts.length
        ? lineStarts[line + 1] - 1
        : text.length;
    final offset = base + (character < 0 ? 0 : character);
    return offset.clamp(base, contentEnd);
  }

  final ranges = <DiagnosticRange>[];
  for (final d in diagnostics) {
    var start = offsetFor(d.range.start.line, d.range.start.character);
    var end = offsetFor(d.range.end.line, d.range.end.character);
    if (end < start) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    if (end == start) end = (start + 1).clamp(0, text.length);
    if (end > start) ranges.add(DiagnosticRange(start, end, d.severity));
  }
  return ranges;
}

/// Constrói os spans coloridos de [source] para a linguagem [language] (a
/// extensão do arquivo), aplicando o sublinhado ondulado dos [diagnostics] nos
/// ranges cobertos e cores semânticas (tokenType) se houver [semanticTokens].
/// Retorna `null` apenas quando não há nada a pintar (sem linguagem **e** sem
/// overlays). O chamador então renderiza o texto puro.
TextSpan? buildCodeSpan(
  BuildContext context, {
  required String source,
  required String? language,
  required TextStyle baseStyle,
  List<DiagnosticRange> diagnostics = const <DiagnosticRange>[],
  List<MatchSpan> matches = const <MatchSpan>[],
  int currentMatch = -1,
  Color? matchColor,
  Color? currentMatchColor,
  List<SemanticRange> semanticTokens = const <SemanticRange>[],
  ({int start, int end})? underlineRange,
  Color? underlineColor,
}) {
  final palette = context.syntax;
  final leaves = _cachedLeavesOf(source, language, palette);
  final overlays = _Overlays(
    diagnostics,
    matches,
    currentMatch,
    matchColor,
    currentMatchColor,
    semanticTokens,
    palette,
    underlineRange,
    underlineColor,
  );
  if (leaves == null) {
    // Sem highlight possível. Só vale construir spans se houver overlays
    // (diagnostics, matches ou semantic) a pintar; senão, deixa o chamador
    // renderizar o texto puro.
    if (!overlays.hasAny) return null;
    return TextSpan(
      style: baseStyle,
      children: _applyOverlays(<_Leaf>[_Leaf(source, null)], overlays),
    );
  }
  return TextSpan(style: baseStyle, children: _applyOverlays(leaves, overlays));
}

/// Sobreposições a fundir sobre os spans de syntax: sublinhado de diagnostics
/// (LSP), fundo dos matches da busca (Cmd+F), e cor de semantic tokens (LSP).
class _Overlays {
  const _Overlays(
    this.diagnostics,
    this.matches,
    this.currentMatch,
    this.matchColor,
    this.currentMatchColor,
    this.semanticTokens,
    this.palette,
    this.underlineRange,
    this.underlineColor,
  );

  final List<DiagnosticRange> diagnostics;
  final List<MatchSpan> matches;
  final int currentMatch;
  final Color? matchColor;
  final Color? currentMatchColor;
  final List<SemanticRange> semanticTokens;
  final SyntaxColors palette;
  final ({int start, int end})? underlineRange;
  final Color? underlineColor;

  bool get hasAny =>
      diagnostics.isNotEmpty ||
      matches.isNotEmpty ||
      semanticTokens.isNotEmpty ||
      underlineRange != null;

  /// Fundo do match que cobre `[a, b)` (o match atual tem cor mais forte), ou
  /// `null` se nenhum match cobre o trecho.
  Color? backgroundFor(int a, int b) {
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.start <= a && m.end >= b) {
        return i == currentMatch ? currentMatchColor : matchColor;
      }
    }
    return null;
  }
}

/// Folha achatada da árvore do highlight.js: um trecho de texto + seu estilo
/// (cor de syntax já resolvida). A ordem reconstrói o texto inteiro.
class _Leaf {
  _Leaf(this.text, this.style);
  final String text;
  final TextStyle? style;
}

/// Entrada do cache de parse léxico: a chave (fonte + linguagem + paleta) e as
/// folhas resultantes (`null` é resultado VÁLIDO — "não dá pra destacar" — e
/// também é cacheado, senão arquivo sem grammar re-tentaria o parse sempre).
class _LeafCacheEntry {
  _LeafCacheEntry(this.source, this.language, this.palette, this.leaves);

  final String source;
  final String? language;
  final SyntaxColors palette;
  final List<_Leaf>? leaves;
}

/// Cache LRU do parse léxico. Pequeno de propósito: cobre o editor ativo + as
/// poucas abas que repintam junto, sem segurar árvores de arquivos grandes.
const int _kLeafCacheSize = 6;
final List<_LeafCacheEntry> _leafCache = <_LeafCacheEntry>[];

/// [_leavesOf] memoizado — **a otimização que mais importa aqui**.
///
/// `buildTextSpan` roda a cada repaint do campo, e repaint dispara em muito
/// mais coisa que digitação: mover o cursor, chegar um batch de diagnostics,
/// mudar os matches da busca e — o pior caso — mover o mouse no hover de
/// go-to-definition (cada identifier novo chama `notifyListeners`). Sem cache,
/// cada um desses eventos re-parseava o ARQUIVO INTEIRO com o highlight.js
/// (tokenizer de regex sobre todo o texto, ordens de magnitude mais caro que o
/// merge de overlays) — passar o mouse sobre o código travava a UI.
///
/// Chaveado por **identidade** da String (`identical`), não `==`: comparar
/// 200KB de texto a cada repaint anularia parte do ganho. O texto vem sempre
/// da mesma instância enquanto o buffer não muda, então o hit rate é alto; um
/// miss só custa o parse que aconteceria de qualquer jeito (nunca incorreto,
/// só mais lento). Editar o buffer cria String nova → miss → re-parse, que é
/// exatamente o comportamento desejado.
///
/// Por que cache e não isolate: as folhas são necessárias **sincronamente** pra
/// pintar o frame. Num isolate, o primeiro frame sairia sem cor e re-pintaria
/// depois (piscada), e ainda haveria a cópia da String entre isolates. O VSCode
/// também tokeniza na thread principal — o que o salva é justamente cache
/// (por linha) + só tokenizar o que está visível, não paralelismo.
List<_Leaf>? _cachedLeavesOf(
  String source,
  String? language,
  SyntaxColors palette,
) {
  for (var i = 0; i < _leafCache.length; i++) {
    final e = _leafCache[i];
    if (identical(e.source, source) &&
        e.language == language &&
        identical(e.palette, palette)) {
      if (i != 0) {
        // Move-to-front: mantém o editor ativo no topo do LRU.
        _leafCache
          ..removeAt(i)
          ..insert(0, e);
      }
      return e.leaves;
    }
  }
  final leaves = _leavesOf(source, language, palette);
  _leafCache.insert(0, _LeafCacheEntry(source, language, palette, leaves));
  if (_leafCache.length > _kLeafCacheSize) _leafCache.removeLast();
  return leaves;
}

/// Busca no cache SEM inserir em caso de miss — usado pelo caminho aproximado,
/// que precisa das folhas de um texto **anterior** e não deve poluir o LRU.
List<_Leaf>? _lookupCachedLeaves(
  String source,
  String? language,
  SyntaxColors palette,
) {
  for (final e in _leafCache) {
    if (identical(e.source, source) &&
        e.language == language &&
        identical(e.palette, palette)) {
      return e.leaves;
    }
  }
  return null;
}

/// Teto da região editada que o caminho aproximado aceita remendar. Acima disso
/// (colar um bloco grande, substituir tudo) o texto sem cor seria visível demais
/// e um parse exato — que é O(arquivo) de qualquer forma — sai mais honesto.
const int _kMaxApproxEditedChars = 2 * 1024;

/// Span **aproximado**: reusa as folhas já parseadas de [previousSource] e
/// remenda apenas a região que mudou, sem rodar o tokenizer.
///
/// Serve pra digitação em arquivo grande: o parse léxico é O(arquivo) (~47ms a
/// 5k linhas) e rodava a cada tecla, porque cada tecla gera texto novo → miss no
/// cache. Aqui, em vez de re-tokenizar, calcula prefixo e sufixo comuns entre o
/// texto velho e o novo, mantém as folhas que caem inteiras neles e substitui o
/// meio por **uma folha sem estilo**. Cobertura do texto fica exata (o teste
/// verifica), só a *cor* da região editada fica temporariamente neutra — o
/// `CodeEditingController` agenda o parse exato no idle.
///
/// `null` quando não dá pra aproximar (folhas de [previousSource] já saíram do
/// LRU, ou a edição é grande demais) — o chamador cai no caminho exato.
TextSpan? buildApproximateCodeSpan(
  BuildContext context, {
  required String source,
  required String previousSource,
  required String? language,
  required TextStyle baseStyle,
  List<DiagnosticRange> diagnostics = const <DiagnosticRange>[],
  List<MatchSpan> matches = const <MatchSpan>[],
  int currentMatch = -1,
  Color? matchColor,
  Color? currentMatchColor,
  List<SemanticRange> semanticTokens = const <SemanticRange>[],
  ({int start, int end})? underlineRange,
  Color? underlineColor,
}) {
  final palette = context.syntax;
  final previous = _lookupCachedLeaves(previousSource, language, palette);
  if (previous == null) return null;
  final patched = _patchLeaves(previous, previousSource, source);
  if (patched == null) return null;

  return TextSpan(
    style: baseStyle,
    children: _applyOverlays(
      patched,
      _Overlays(
        diagnostics,
        matches,
        currentMatch,
        matchColor,
        currentMatchColor,
        semanticTokens,
        palette,
        underlineRange,
        underlineColor,
      ),
    ),
  );
}

/// Remenda [leaves] (de [oldText]) para cobrir [newText]. Ver
/// [buildApproximateCodeSpan]. `null` se a edição é grande demais.
List<_Leaf>? _patchLeaves(List<_Leaf> leaves, String oldText, String newText) {
  final oldLen = oldText.length;
  final newLen = newText.length;

  // Prefixo comum.
  final maxCommon = oldLen < newLen ? oldLen : newLen;
  var prefix = 0;
  while (prefix < maxCommon &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  // Sufixo comum, sem invadir o prefixo já casado.
  var suffix = 0;
  final maxSuffix = maxCommon - prefix;
  while (suffix < maxSuffix &&
      oldText.codeUnitAt(oldLen - 1 - suffix) ==
          newText.codeUnitAt(newLen - 1 - suffix)) {
    suffix++;
  }

  // Região efetivamente tocada, no texto velho: `[prefix, removedEnd)`; e o que
  // entrou no lugar dela.
  final removedEnd = oldLen - suffix;
  final inserted = newText.substring(prefix, newLen - suffix);
  if (inserted.length > _kMaxApproxEditedChars ||
      removedEnd - prefix > _kMaxApproxEditedChars) {
    return null;
  }

  // Emenda DENTRO da folha atingida, preservando todas as outras byte a byte —
  // mesmo texto, mesmo estilo. Essa é a propriedade que importa: nenhuma letra
  // fora da edição pode trocar de cor.
  //
  // A 1ª versão descartava as folhas que cruzavam a fronteira e fundia tudo num
  // único estilo herdado. Resultado: o texto VIZINHO já digitado perdia a cor
  // própria e só a recuperava no parse exato, 120ms depois. Como digitação
  // normal tem intervalos maiores que isso, o efeito era a cor de outras letras
  // mudando a cada tecla.
  final out = <_Leaf>[];
  var offset = 0;
  var insertPlaced = false;
  for (final leaf in leaves) {
    final start = offset;
    final end = start + leaf.text.length;
    offset = end;
    if (leaf.text.isEmpty) continue;

    // Pedaço da folha que sobrevive ANTES da edição.
    final headLen = prefix <= start
        ? 0
        : (prefix >= end ? leaf.text.length : prefix - start);
    // Pedaço que sobrevive DEPOIS da remoção.
    final tailStart = removedEnd <= start
        ? 0
        : (removedEnd >= end ? leaf.text.length : removedEnd - start);

    // O texto inserido entra na primeira folha que contém o ponto da edição —
    // inclusive quando ele cai exatamente no fim dela, que é o caso comum de
    // continuar digitando um identificador (aí a cor do token é preservada).
    final takesInsert = !insertPlaced && prefix >= start && prefix <= end;
    if (takesInsert) insertPlaced = true;

    final text =
        leaf.text.substring(0, headLen) +
        (takesInsert ? inserted : '') +
        leaf.text.substring(tailStart);
    if (text.isEmpty) continue;
    // Folha intocada → reusa a instância (nada de span novo à toa).
    out.add(
      text.length == leaf.text.length && !takesInsert
          ? leaf
          : _Leaf(text, leaf.style),
    );
  }
  // Edição depois da última folha (ou arquivo vazio).
  if (!insertPlaced && inserted.isNotEmpty) {
    out.add(_Leaf(inserted, leaves.isNotEmpty ? leaves.last.style : null));
  }
  return out;
}

/// Esvazia o cache de parse léxico (e zera [codeHighlightParseCount]). Só para
/// testes — em produção o LRU se autolimita.
@visibleForTesting
void clearCodeHighlightCache() {
  _leafCache.clear();
  codeHighlightParseCount = 0;
}

/// Quantos parses léxicos de fato rodaram (ou seja, cache miss). Só para
/// testes: é o que permite asseverar "repaint não re-parseou".
@visibleForTesting
int codeHighlightParseCount = 0;

/// Parseia [source] e achata a árvore do highlight.js em folhas. Retorna `null`
/// quando não dá pra destacar (sem linguagem, arquivo grande, parse vazio).
List<_Leaf>? _leavesOf(String source, String? language, SyntaxColors palette) {
  if (language == null || language.isEmpty) return null;
  if (source.length > _kMaxHighlightChars) return null;

  codeHighlightParseCount++;
  _ensureCustomLanguages();
  final lang = _extToLanguage[language.toLowerCase()] ?? language.toLowerCase();
  final nodes = hl.highlight.parse(source, language: lang).nodes;
  if (nodes == null || nodes.isEmpty) return null;

  final leaves = <_Leaf>[];
  for (final node in nodes) {
    _flatten(node, null, palette, leaves);
  }
  return leaves;
}

/// Recursão que acumula o estilo herdado (containers do highlight.js aplicam
/// `className` aos descendentes) e emite uma folha por `value`.
void _flatten(
  hl.Node node,
  TextStyle? inherited,
  SyntaxColors palette,
  List<_Leaf> out,
) {
  final own = node.className == null ? null : palette.styleFor(node.className!);
  final style = own == null
      ? inherited
      : (inherited ?? const TextStyle()).merge(own);
  if (node.value != null) {
    out.add(_Leaf(node.value!, style));
    return;
  }
  final children = node.children;
  if (children == null) return;
  for (final child in children) {
    _flatten(child, style, palette, out);
  }
}

/// Corta as folhas nos limites dos diagnostics **e** dos matches de busca, e
/// funde em cada sub-trecho o sublinhado ondulado (diagnostics) + o fundo do
/// match (busca), preservando a cor de syntax. Sem overlays, devolve 1:1.
///
/// Os semantic tokens do LSP chegam em ORDEM CRESCENTE de offset e **não se
/// sobrepõem** (garantia do protocolo — são deltas relativos sempre positivos).
/// Isso permite varrer com um ÚNICO ponteiro monotônico (`semIdx`) em vez de
/// re-escanear a lista inteira pra cada leaf/corte: sem isso, um arquivo grande
/// (milhares de tokens semânticos, comum no Dart — quase todo identifier vira
/// token) faz `_applyOverlays` custar O(leaves × tokens), travando a UI a cada
/// rebuild (troca de arquivo, cada tecla do debounce). Com o ponteiro, o custo
/// cai pra O(leaves + tokens) amortizado. Diagnostics/matches ficam como scan
/// linear mesmo — a contagem típica é pequena (dezenas), não vale a
/// complexidade extra de um sweep ali.
List<InlineSpan> _applyOverlays(List<_Leaf> leaves, _Overlays overlays) {
  if (!overlays.hasAny) {
    return _joinRuns(<(String, TextStyle?)>[
      for (final leaf in leaves) (leaf.text, leaf.style),
    ]);
  }
  final diagnostics = overlays.diagnostics;
  final matches = overlays.matches;
  final semanticTokens = overlays.semanticTokens;
  // Acumula (texto, estilo) e só materializa TextSpans no fim, fundindo
  // vizinhos de estilo igual — ver [_joinRuns].
  final runs = <(String, TextStyle?)>[];
  var pos = 0;
  // Ponteiro compartilhado: nunca anda pra trás — leaves são processadas em
  // ordem crescente de offset, tokens também, então uma vez que um token fica
  // pra trás (seu `end` já passou o início da leaf atual) ele nunca mais
  // importa pro resto do arquivo.
  var semIdx = 0;
  for (final leaf in leaves) {
    final start = pos;
    final end = pos + leaf.text.length;
    pos = end;
    if (leaf.text.isEmpty) continue;

    // Avança o ponteiro além dos tokens que já ficaram pra trás desta leaf.
    while (semIdx < semanticTokens.length &&
        semanticTokens[semIdx].end <= start) {
      semIdx++;
    }

    // Pontos de corte = início/fim da folha + limites de overlays internos
    // (diagnostics, matches, semantic tokens).
    final cuts = <int>{start, end};
    for (final d in diagnostics) {
      if (d.end <= start || d.start >= end) continue;
      if (d.start > start && d.start < end) cuts.add(d.start);
      if (d.end > start && d.end < end) cuts.add(d.end);
    }
    for (final m in matches) {
      if (m.end <= start || m.start >= end) continue;
      if (m.start > start && m.start < end) cuts.add(m.start);
      if (m.end > start && m.end < end) cuts.add(m.end);
    }
    // Só percorre os tokens que efetivamente tocam esta leaf (a partir de
    // `semIdx`, já sem os que ficaram pra trás) — bounded pela sobreposição
    // real leaf↔tokens, não pelo total de tokens do arquivo.
    for (var i = semIdx; i < semanticTokens.length; i++) {
      final t = semanticTokens[i];
      if (t.start >= end) {
        break; // ordenados → nenhum token daqui em diante toca esta leaf
      }
      if (t.start > start && t.start < end) cuts.add(t.start);
      if (t.end > start && t.end < end) cuts.add(t.end);
    }
    final underline = overlays.underlineRange;
    if (underline != null && underline.end > start && underline.start < end) {
      if (underline.start > start && underline.start < end) {
        cuts.add(underline.start);
      }
      if (underline.end > start && underline.end < end) cuts.add(underline.end);
    }
    final sorted = cuts.toList()..sort();
    // Ponteiro LOCAL a esta leaf (parte de `semIdx`, sem regredir) — avança
    // pelos cortes em ordem crescente, então cada token é examinado no máximo
    // uma vez por leaf, não uma vez por corte.
    var styleIdx = semIdx;
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final sub = leaf.text.substring(a - start, b - start);
      var style = leaf.style;
      // Cor semântica primeiro (fallback → léxico), depois diagnostics e
      // matches. Tokens não se sobrepõem: no máximo um cobre [a,b).
      TextStyle? semanticStyle;
      while (styleIdx < semanticTokens.length &&
          semanticTokens[styleIdx].end <= a) {
        styleIdx++;
      }
      if (styleIdx < semanticTokens.length) {
        final t = semanticTokens[styleIdx];
        if (t.start <= a && t.end >= b) {
          semanticStyle = overlays.palette.styleForSemanticType(t.tokenType);
        }
      }
      if (semanticStyle != null) {
        style = (style ?? const TextStyle()).merge(semanticStyle);
      }
      final severity = _coveringSeverity(diagnostics, a, b);
      if (severity != null) {
        style = (style ?? const TextStyle()).merge(
          SyntaxColors.underlineStyleFor(severity),
        );
      }
      final bg = overlays.backgroundFor(a, b);
      if (bg != null) {
        style = (style ?? const TextStyle()).copyWith(backgroundColor: bg);
      }
      if (underline != null && underline.start <= a && underline.end >= b) {
        // Recolore o texto (não só sublinha) — feedback tipo link/hyperlink,
        // igual VSCode: fica óbvio que aquele identifier é navegável.
        style = (style ?? const TextStyle()).merge(
          TextStyle(
            color: overlays.underlineColor,
            decoration: TextDecoration.underline,
            decorationColor: overlays.underlineColor,
          ),
        );
      }
      runs.add((sub, style));
    }
  }
  return _joinRuns(runs);
}

/// Materializa os trechos em [TextSpan]s.
///
/// Fundir vizinhos de estilo igual foi tentado e **medido**: num arquivo Dart
/// de 5k linhas rendeu só 3% menos spans (38.664 → 37.448) e ~2% de layout,
/// dentro do ruído. Com semantic tokens densos (quase todo identifier vira
/// token) praticamente todo trecho vizinho tem estilo genuinamente diferente,
/// então não há o que fundir. Mantido simples de propósito.
List<InlineSpan> _joinRuns(List<(String, TextStyle?)> runs) {
  return <InlineSpan>[
    for (final (text, style) in runs)
      if (text.isNotEmpty) TextSpan(text: text, style: style),
  ];
}

/// Severidade mais grave que cobre `[a, b)` (error > warning > info > hint), ou
/// `null` se nenhum diagnostic cobre o trecho.
LspSeverity? _coveringSeverity(
  List<DiagnosticRange> diagnostics,
  int a,
  int b,
) {
  LspSeverity? result;
  for (final d in diagnostics) {
    if (d.start <= a && d.end >= b) {
      // index menor = mais grave (error=0).
      if (result == null || d.severity.index < result.index) {
        result = d.severity;
      }
    }
  }
  return result;
}
