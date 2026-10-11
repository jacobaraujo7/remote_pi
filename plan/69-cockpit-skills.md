# 69 — Cockpit skills: várias skills, instalação em todo host, e `cockpit-design`

## Contexto

Hoje o Cockpit instala **uma** skill, `cockpit-cli` (717 linhas num `SKILL.md`),
embutida no binário Rust por `include_str!` e gravada em
`~/.claude/skills/cockpit-cli/` pelo `cockpit install-skill`, chamado no boot do
app desktop. Problemas observados (2026-10-09/10):

- O `cockpit-server` **não** instala a skill no host: agente numa VPS "não sabe
  que está num Cockpit".
- A `description` do front-matter tenta cobrir CLI, DB, layout, kanban,
  notebook e telemetria; o gatilho dispara tarde ou errado.
- Zero orientação de **design**: a primeira versão de qualquer `.panel` ou
  `.html` gerado por agente é feia. Os Artifacts do Claude saem melhores só por
  carregarem uma skill de design antes de escrever a página.
- Só Claude Code recebe a skill; Codex e Pi num terminal do Cockpit ficam sem.
- O agente escreve o HTML às cegas: `read-tab` não lê webview, então ele não
  consegue iterar visualmente.

Decisões fechadas nesta conversa:

| # | Decisão |
|---|---|
| A | Divisão por **gatilho**, não por tamanho: `cockpit-cli`, `cockpit-db`, `cockpit-telemetry`, `cockpit-design`. Cada `SKILL.md` curto (até ~150 linhas) + `references/` e `templates/` lidos sob demanda (revelação progressiva) |
| B | `cockpit-design` cobre tudo que o **humano vai ver**: `.panel`, `.html` (mesma webview, mesmas `--ckp-*`), `.kanban`, `.notebook`, `.ckp`. Cada formato numa `references/<formato>.md` |
| C | Fonte no repo como **árvore** em `cockpit/cli/skills/<nome>/`; o binário embute a árvore e o `install-skill` grava uma pasta por skill, com manifesto pra remover arquivo que sumiu e detectar "igual, no-op" por skill |
| D | `cockpit-server` passa a chamar `install-skill` no boot (espelho do `ensureCli` do desktop) |
| E | `install-skill --agent claude|codex|pi|all`, default `all` quando a pasta do harness existir |
| F | O agente ganha olho: `cockpit panel screenshot <tab-id>` (PNG da webview) pra iterar no próprio painel |
| G | `cockpit.css` vira mini design system de **estrutura** (`.page`, `.toolbar`, `.kpis`, `.split`, `.empty`, `.skeleton`, `.status-dot`, escala de espaçamento), documentado na skill. Objetivo: o agente escrever quase zero CSS |
| H | Templates de verdade: Galeria "panel" deixa de ser arquivo vazio; `cockpit panel new --template dashboard|list-detail|form <arquivo>` |
| I | Nada de framework maior nem "design por IA" dentro do app. O problema é contrato, não render |

## Estrutura esperada

```
cockpit/cli/
├── skills/                          # fonte das skills (substitui text/skill.md)
│   ├── cockpit-cli/SKILL.md
│   ├── cockpit-cli/references/{tabs,tasks,exec,errors}.md
│   ├── cockpit-db/SKILL.md
│   ├── cockpit-db/references/{connections,dbq,redis,mongo,ssh-tunnel}.md
│   ├── cockpit-telemetry/SKILL.md
│   ├── cockpit-telemetry/references/{wrapper,query,app,probes}.md
│   ├── cockpit-design/SKILL.md      # regras + checklist, curto
│   ├── cockpit-design/references/{panel,html,kanban,notebook,ckp,css-classes}.md
│   └── cockpit-design/templates/{dashboard,list-detail,form}.panel
├── build.rs                         # gera a tabela (path → bytes) da árvore
└── src/skills.rs                    # install_skill: manifesto, --agent, no-op
cockpit/assets/panel/lib/cockpit.css  # classes de estrutura (decisão G)
cockpit/packages/cockpit_server/bin/cockpit_server.dart  # chama install-skill
cockpit/lib/app/cockpit/ui/viewmodels/cockpit_cli_handler.dart  # panel screenshot, panel new
```

## Passos

### Onda 1 — mecanismo (nada muda pro usuário)

1. **Árvore embutida.** `build.rs` percorre `cli/skills/` e gera um array
   `(rel_path, &[u8])`. `include_str!` do arquivo único sai. Aceite: `cargo
   build` falha se `skills/` estiver vazio; `cockpit install-skill --list`
   imprime as skills e arquivos embutidos.
2. **Manifesto por skill.** `~/.claude/skills/<nome>/.cockpit-skill.json`
   com `{version, files: [...]}`. Instalação: grava os arquivos, remove os que
   estavam no manifesto anterior e não existem mais, reescreve o manifesto.
   Igual = no-op silencioso. Aceite: teste Rust com pasta temporária cobrindo
   install limpo, update que remove arquivo, e no-op.
3. **`--agent`.** `claude` → `~/.claude/skills/`; `codex` → pasta de skills do
   Codex; `pi` → do Pi; `all` (default) instala em cada pasta de harness que
   existir no HOME. Aceite: teste com HOME falso contendo só `.codex/`.
4. **Server instala.** `cockpit_server.dart` chama `<cli> install-skill` após
   resolver a CLI (mesmo lugar do `resolveCli`). Respeita `--no-hooks`? Não:
   flag própria `--no-skills` pro smoke test do `install.sh`. Aceite: subir o
   server numa VPS limpa deixa `~/.claude/skills/cockpit-*` no host.
5. **Migração.** Primeira skill da árvore é a `cockpit-cli` atual, intacta.
   Aceite: `diff` entre a skill instalada antes e depois é vazio.

### Onda 2 — divisão

6. Fatiar o `skill.md` em quatro `SKILL.md` + `references/`. Regra: o corpo de
   cada `SKILL.md` só tem o que o agente precisa **sempre**; o resto vira
   referência apontada por frase do tipo "pra X, leia `references/x.md`".
   Descriptions curtas e disjuntas (uma frase de gatilho cada). Aceite:
   nenhum `SKILL.md` acima de 150 linhas; `grep -c` de cada verbo confirma que
   nada do conteúdo atual se perdeu.
7. Teste de gatilho manual com 8 prompts (2 por skill) num terminal do
   Cockpit: a skill certa dispara, as outras não. Registrar resultado no plano.

### Onda 3 — `cockpit-design`

8. **`cockpit.css` de estrutura** (decisão G). Classes novas, nomes
   documentados em `references/css-classes.md` com um exemplo cada. Aceite:
   os dois painéis da raiz (`pull-requests.panel`, `github-actions.panel`)
   reescritos só com classes do `cockpit.css`, sem `<style>` próprio além de
   um bloco de ajuste.
9. **Regras de design** no `SKILL.md`: anatomia obrigatória (cabeçalho com
   título, status e ações à direita; corpo em grid; rodapé de erro), estados
   (loading, vazio, erro) sempre presentes, só `--ckp-*` pra cor, números em
   `.stat`, nunca CSS antes de esgotar o `cockpit.css`, checklist final.
   Destilar da `artifact-design` da Anthropic o que vale pro nosso contexto.
10. **Templates** `templates/{dashboard,list-detail,form}.panel` funcionais,
    com ponte, rotas e estados. Aceite: cada um abre e roda sem edição.
11. **Galeria**: o template "panel" passa a copiar `templates/dashboard.panel`.
12. **`cockpit panel new --template <t> <arquivo>`**: copia o template e abre.
13. **Screenshot** (decisão F): `cockpit panel screenshot <tab-id> [--out
    x.png]` via `InAppWebViewController.takeScreenshot`; sem `--out`, grava em
    arquivo temporário e imprime o caminho (o agente lê a imagem). Aceite:
    agente num terminal gera o PNG do painel aberto e descreve o que vê.

## Definition of Done

- [x] Onda 1: árvore embutida, manifesto, `--agent`, server instalando, skill atual intacta (2026-10-10, `522f7aa9`)
- [ ] Onda 2: quatro skills, nenhuma acima de 150 linhas (feito 2026-10-10), teste de gatilho registrado (pendente)
- [ ] Onda 3: `cockpit.css` de estrutura, regras, três templates, Galeria, `panel new`, `panel screenshot`
- [ ] Os dois painéis da raiz reescritos com as classes novas e sem CSS próprio
- [ ] Release do app e do server na mesma versão (o server precisa do `--no-skills` e da chamada ao `install-skill`)

## Próximos planos

- Assets relativos de `.panel` remoto servidos por `fs.read` (hoje só `/__cockpit__/`).
- `wait`/`signal` na CLI (IPC efêmero), depois `listen` HTTP e WebSocket no `.http`.
