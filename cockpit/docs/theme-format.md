# Formato de tema do Cockpit (`cockpit-theme-1`)

Um tema é **um arquivo JSON**. Ele pinta as três camadas de uma vez: a UI do
app, o realce de código do viewer e a paleta do terminal.

- Importar: Configurações → Aparência → Tema → **Importar…**
- A pasta é `<pasta de dados>/themes/` (mesma raiz do "Storage"), um arquivo por
  tema, nomeado pelo `id`. Copiar um `.json` pra lá também instala.
- Exportar gera arquivo **completo** (todos os tokens, sem `extends`): serve de
  ponto de partida pra editar à mão.

## Estrutura

```json
{
  "$schema": "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json",
  "id": "acme.aurora",
  "name": "Aurora",
  "author": "Acme",
  "version": "1.0.0",
  "extends": "cockpit",
  "variants": {
    "dark":  { "ui": {}, "syntax": {}, "terminal": {} },
    "light": { "ui": {}, "syntax": {}, "terminal": {} }
  }
}
```

| Campo | Obrigatório | O quê |
|---|---|---|
| `id` | sim | Identidade estável, namespaced (`publisher.nome`). É o que fica salvo nas preferências — renomear o `name` não perde a escolha do usuário. Não pode colidir com um built-in (`cockpit`, `cockpit.2`, `violet`, `violet.2`, `midnight`, `rose`, `sun`, `flexoki`, `pantera`). |
| `name` | sim | O que aparece no seletor. |
| `author`, `version` | não | Metadados. |
| `extends` | não | Id de um tema built-in do qual herdar. Hoje existem `cockpit`, `cockpit.2`, `violet`, `violet.2`, `midnight`, `rose`, `sun`, `flexoki` e `pantera`. Ausente = herda de `cockpit`. |
| `variants` | sim | Pelo menos um de `dark` / `light`. |

**Herança é o ponto.** Todo token não declarado vem da base, então um tema útil
pode ter cinco linhas. Um tema com só `dark` é aplicado também no modo claro
(melhor que misturar meio-claro com meio-escuro).

## Cores

Hex no estilo CSS: `#RGB`, `#RRGGBB` ou `#RRGGBBAA` — **alpha no fim**. Não é o
`0xAARRGGBB` do Dart.

## Tokens

### `ui` (25) — a interface

| Grupo | Tokens |
|---|---|
| Superfícies | `bg` (fundo mais profundo) · `panel` (pane/rail) · `panel2` (elevado: composer, cards) · `panel3` (hover / código embutido) |
| Traços | `border` (fio de cabelo) · `border2` (divisor forte) |
| Texto | `text` (primário) · `text2` (secundário) · `text3` (terciário/placeholder) · `text4` (fraco, ícone em repouso) |
| Marca | `accent` · `accentSoft` (fundo de seleção, translúcido) · `accentText` (texto na cor da marca) |
| Estado | `online` · `ok` · `error` · `warn` |
| Edição | `edited` · `editedBg` |
| Git | `gitStaged` · `gitUntracked` · `gitDeleted` · `gitConflict` |
| Overlay | `scrim` (fundo de dialog, translúcido) · `shadow` (sombra projetada) |

> O texto **sobre** `accent` e `error` não é um token: é derivado da luminância
> da cor. Accent claro recebe texto escuro automaticamente.

### `syntax` (12) — o realce de código

`background` · `base` · `comment` · `keyword` · `string` · `number` · `class` ·
`builtin` · `function` · `variable` · `meta` · `deletion`

> **`background` tem um default especial.** Viewer de código, editor e terminal
> são conteúdo dentro da aba, então os três compartilham o campo: quando o tema
> **não** declara `syntax.background` (nem `terminal.background`), eles seguem o
> `ui.panel` **deste** tema — e não o da base. Declare o campo para escapar
> disso, se a paleta de código precisar de fundo próprio.

### `terminal` (23) — a paleta ANSI

`cursor` · `selection` · `foreground` · `background`, as 8 cores normais
(`black` `red` `green` `yellow` `blue` `magenta` `cyan` `white`), as 8 `bright*`
correspondentes, e `searchHitBackground` · `searchHitBackgroundCurrent` ·
`searchHitForeground`.

## Exemplo mínimo real

Troca só a marca e mantém tudo do tema nativo:

```json
{
  "$schema": "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json",
  "id": "acme.violet",
  "name": "Violet",
  "variants": {
    "dark":  { "ui": { "accent": "#8B5CF6", "accentSoft": "#8B5CF633", "accentText": "#C4B5FD" } },
    "light": { "ui": { "accent": "#7C3AED", "accentSoft": "#7C3AED22", "accentText": "#5B21B6" } }
  }
}
```

Ver [`theme.example.json`](./theme.example.json) para um arquivo comentado com
todos os grupos preenchidos.

## O `$schema`

O schema fica **no repositório**, não num domínio nosso:

```
https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/docs/theme.schema.json
```

Versionado junto do código que o implementa, então não existe o caso de o site
servir uma versão e o app entender outra. Fixado em `main` de propósito: quem
escreve tema quer o autocomplete do formato atual.

Ao contrário do `tasks.json` (que mora no repo e pode usar caminho relativo), um
tema vive numa pasta de dados qualquer e é copiado entre máquinas — por isso a
URL absoluta.

O app **ignora** `$schema` ao ler o tema; o campo só serve ao editor. O CI trava
o desencontro: `test/ui/theme_codec_test.dart` compara os tokens do schema com
os que o codec serializa, o `enum` de `extends` com os built-in registrados, e
valida o `theme.example.json` deste diretório.

## Erros de importação

O parser aponta o **caminho do campo** que quebrou
(`variants.dark.ui.accent`), então o diagnóstico não é "arquivo inválido" seco.
Arquivo inválido nunca chega à pasta de temas: a validação roda antes da cópia.
