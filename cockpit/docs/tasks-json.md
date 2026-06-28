# `.cockpit/tasks.json` — Task Run

O **Task Run** do cockpit roda os comandos de build/dev do seu projeto
(`npm run dev`, `flutter run`, `go run`, `make`…) com streaming de output, ciclo
de vida visual (play/stop/restart), teclas interativas e "reload ao salvar".

Há duas fontes de tasks, que convivem:

1. **Detecção automática** — ao abrir um projeto, o cockpit lê os manifestos
   (`package.json scripts`, `pubspec.yaml`) e já mostra tasks **sem config**.
2. **Manual** — este arquivo, `.cockpit/tasks.json`, na pasta que você abre como
   workspace. Use pra customizar, adicionar tasks ou descrever um **monorepo**.
   Tasks do JSON têm **precedência** sobre detectadas de mesmo `id`.

> O executor é **genérico**: conhece só `command`/`args`/`env`. Não existem
> chaves de stack (flavor, dart-define, NODE_ENV) — tudo isso vira `args`/`env`.

> **JSONC**: o arquivo aceita **comentários** (`//` e `/* */`) e **vírgulas
> finais**, igual ao `tasks.json` do VSCode. São removidos antes do parse.

## Onde fica

Na **raiz do workspace** que você abre no cockpit. A descoberta é literal (sem
subir na árvore), então:

- Projeto de pacote único → abra a pasta do pacote; `.cockpit/tasks.json` ali.
- **Monorepo** → abra a raiz; um único `.cockpit/tasks.json` na raiz dirige os
  subpacotes via `cwd` por task (ver abaixo).

## Exemplo

```jsonc
{
  "tasks": [
    {
      "label": "run",
      "cwd": "app",                 // relativo à pasta do tasks.json
      "command": "flutter",
      "args": ["run"],
      "kind": "watch",
      "interactiveKeys": [
        { "key": "r", "label": "Hot reload", "icon": "refresh", "primary": true },
        { "key": "R", "label": "Hot restart", "icon": "restart", "primary": true },
        { "key": "q", "label": "Quit", "icon": "stop" }
      ],
      "watch": {
        "paths": ["lib", "assets"],
        "ignore": ["build", ".dart_tool"],
        "onChange": "Hot reload",   // = label de um interactiveKey, ou "__restart__"
        "debounceMs": 300
      },
      "progressPatterns": [
        { "begin": "Performing hot reload", "end": "Reloaded .* in .*ms" }
      ],
      "profiles": [
        { "name": "default" },
        { "name": "web", "args": ["-d", "chrome"] }
      ]
    },
    {
      "label": "api",
      "cwd": "backend",             // monorepo: outra subpasta
      "command": "dart",
      "args": ["run", "bin/server.dart"],
      "kind": "watch"
    }
  ]
}
```

## Campos

### Raiz

| Campo   | Tipo     | Obrigatório | Descrição |
|---------|----------|-------------|-----------|
| `tasks` | array    | sim         | Lista de tasks (ver abaixo). |
| `cwd`   | string   | não         | **Default** de `cwd` pra todas as tasks (açúcar de DRY). Cada task pode sobrescrever. |

### Task

| Campo              | Tipo     | Obrigatório | Default     | Descrição |
|--------------------|----------|-------------|-------------|-----------|
| `label`            | string   | **sim**     | —           | Nome curto exibido na lista. |
| `command`          | string   | **sim**     | —           | Executável base (ex.: `npm`, `flutter`). |
| `args`             | string[] | não         | `[]`        | Args base, antes do profile. |
| `cwd`              | string   | não         | raiz/topo   | Pasta de execução, **relativa à pasta do `tasks.json`**. Omitido → herda o `cwd` top-level, senão a raiz. Absoluto também aceito. |
| `kind`             | string   | não         | `oneShot`   | `watch` (processo vivo, ex.: dev-server) ou `oneShot` (roda e termina). |
| `interactiveKeys`  | array    | não         | `[]`        | Teclas enviadas ao stdin (ver abaixo). |
| `watch`            | object   | não         | `null`      | "Reload ao salvar" (ver abaixo). Omitido em ferramentas que já observam (Vite/Next). |
| `progressPatterns` | array    | não         | `[]`        | Regex begin/end pro badge `building↔running`. |
| `profiles`         | array    | não         | `[]`        | Variantes de execução (ver abaixo). |

> O cockpit gera o `id` da task automaticamente (`json:<label>`); ele sobrescreve
> uma task detectada de mesmo `id`.

### `interactiveKeys[]`

Cada item vira um controle na linha da task (ou no overflow). **Sem `if (flutter)`
no app** — o que existe vem daqui.

| Campo     | Tipo    | Obrigatório | Descrição |
|-----------|---------|-------------|-----------|
| `key`     | string  | **sim**     | Sequência escrita no PTY (ex.: `"r"`, `"R"`, `"q"`). |
| `label`   | string  | **sim**     | Rótulo amigável (ex.: `"Hot reload"`). |
| `icon`    | string  | não         | Token de ícone: `refresh`, `restart`, `stop`, `bolt` (raio). Sem ícone → chip com a tecla. |
| `primary` | boolean | não (`false`) | `true` = botão fixo na linha; `false` = botão secundário. |

### `watch`

O `flutter run` **não** recarrega ao salvar — isso é feature de plugin de IDE; o
cockpit reimplementa via observação de arquivos. Fica **sempre ligado** enquanto
a task com `watch` está viva.

| Campo        | Tipo     | Obrigatório | Default | Descrição |
|--------------|----------|-------------|---------|-----------|
| `paths`      | string[] | não         | `[]`    | Pastas/arquivos a observar (relativos ao `cwd`). Vazio = tudo. |
| `ignore`     | string[] | não         | `[]`    | Padrões a ignorar (ex.: `build`, `.dart_tool`). Evita loop. |
| `onChange`   | string   | **sim**     | —       | Ação ao mudar: o `label` de um `interactiveKey` (ex.: `"Hot reload"`) **ou** `"__restart__"` (mata+relança). |
| `debounceMs` | number   | não         | `300`   | Janela de debounce (um save emite vários eventos). |

### `progressPatterns[]`

Detectam recompilação no output pro badge oscilar `building↔running`.

| Campo   | Tipo   | Obrigatório | Descrição |
|---------|--------|-------------|-----------|
| `begin` | string | **sim**     | Regex de "começou a recompilar". |
| `end`   | string | **sim**     | Regex de "voltou ao idle". |

### `profiles[]`

Variantes nomeadas de execução ("launch configs"). Na UI, um chip cicla os
profiles antes do play; o subtítulo mostra o comando final. Genérico — flavor e
dart-define do Flutter entram como `args`.

| Campo  | Tipo               | Obrigatório | Descrição |
|--------|--------------------|-------------|-----------|
| `name` | string             | **sim**     | Nome exibido (ex.: `dev`, `prod`, `web`). Use nomes únicos. |
| `args` | string[]           | não         | Args concatenados **após** os `args` da task. |
| `env`  | object<string,str> | não         | Variáveis mescladas no ambiente do processo. |

## Validação no editor (JSON Schema)

Há um JSON Schema em [`docs/tasks.schema.json`](./tasks.schema.json). Pra ganhar
autocomplete/validação no editor, referencie-o no topo do arquivo:

```jsonc
{ "$schema": "../cockpit/docs/tasks.schema.json", "tasks": [ ... ] }
```

(O cockpit ignora `$schema` ao executar — é só pro editor.)

## Limitações conhecidas

- Pra valores de arg com espaço, use **itens separados** em `args`
  (ex.: `["--dart-define", "MSG=oi mundo"]`).
- A tab de output não sobrevive ao reinício do app (a task morre junto).
