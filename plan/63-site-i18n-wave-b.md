# 63 — Site: internacionalização Wave B (docs, cockpit/docs, tutorials)

## Contexto

A Wave A ([`plan/62-site-i18n-llms-txt.md`](./62-site-i18n-llms-txt.md)) entregou
infra `next-intl` + tradução completa de landing, nav/header/footer, legal
(privacy/terms), download, `/cockpit` (marketing) e `/why`, mais `llms.txt` /
`robots.txt`. Essas páginas ficam em `src/app/[locale]/`.

O que ficou de fora, por decisão explícita da Wave A (é 70% do volume total do
site e o maior risco de tradução técnica errada), está hoje em
`src/app/(static)/` — fora do `[locale]`, servido só em inglês, sem prefixo:

| Página | Linhas | Onde |
|---|---|---|
| Docs geral | 984 | `src/app/(static)/docs/page.tsx` |
| Docs do Cockpit | 1380 | `src/app/(static)/cockpit/docs/page.tsx` |
| 7 tutoriais | ~1850 | `src/app/(static)/tutorials/*/page.tsx` |

**~4200 linhas**, quase todo prosa técnica densa com comandos, flags, exemplos
de terminal e blocos de código intercalados — cada bloco de texto precisa ser
extraído com cuidado pra não vazar nem quebrar os elementos técnicos que a
Wave A já provou funcionar (decisão G): `Pi`, `Cockpit`, `Claude Code`, nomes
de comando/flag, blocos de código e exemplos de terminal **não traduzem**.

Componentes compartilhados por essas páginas que também têm string hardcoded
e ainda não foram tocados pela Wave A (só usados fora do `[locale]` até
agora): `src/components/docs-shell.tsx` (`DocsSection`, `DocsSubsection`,
`DocsTable`), `src/components/docs-toc.tsx`, `src/components/pager.tsx`
(`aria-label="Tutorial navigation"`), `src/components/callout.tsx` (fallback
de título "Warning"/"Note"), `src/components/install-tabs.tsx` (variante de
`landing/install.tsx` usada dentro dos tutoriais/docs, com seu próprio texto
duplicado).

### Decisões fechadas nesta conversa (2026-08-26)

Propostas pelo agente do pane Site (rascunho pós-Wave A), revisadas e
aceitas pelo orquestrador sem alteração.

| # | Decisão |
|---|---|
| **A** | Reaproveita **toda a infra da Wave A** sem mudança de arquitetura: mesmas `routing.ts`/`navigation.ts`/`request.ts`, mesmo `localePrefix: "as-needed"`, mesma regra de árvore-fonte `en.json` + build falhando em chave faltando (`scripts/check-messages.mjs` já existe e escala pro volume novo sem mudança) |
| **B** | As 3 páginas/grupos migram pra dentro de `src/app/[locale]/` (docs, cockpit/docs, tutorials/**). Isso **esvazia** `src/app/(static)/` — depois desta wave não sobra nenhuma rota fora do `[locale]`, então o grupo `(static)/layout.tsx` (workaround de múltiplos root layouts que a Wave A precisou criar só pra manter essas páginas intocadas) é **removido**, e tudo passa a viver sob um único root (`[locale]/layout.tsx`) — simplificação, não regressão |
| **C** | Ordem de execução por **risco crescente de erro de tradução**: tutoriais primeiro (menor, mais concreto, passo-a-passo), depois `/docs` (referência geral), por último `/cockpit/docs` (maior, mais denso, mais superfície de comando/flag pra errar) |
| **D** | Componentes compartilhados (`docs-shell`, `docs-toc`, `pager`, `callout`, `install-tabs`) ganham chaves de tradução na mesma leva do primeiro passo que os usa — não ficam pra depois soltos em inglês |
| **E** | `llms.txt` **não muda** — continua só inglês (decisão F da Wave A), linkando pra URL canônica de cada página; localização não quebra esses links (o unprefixed continua resolvendo em inglês) |
| **F** | Nomes próprios e trechos técnicos continuam sem traduzir (decisão G da Wave A) — inclui aqui explicitamente: nomes de arquivo de config, variáveis de ambiente, flags de CLI, saída de comando de exemplo |

## Estrutura esperada

```
site/src/
├── app/
│   ├── [locale]/
│   │   ├── layout.tsx              # agora é o ÚNICO root (sem mudança de conteúdo)
│   │   ├── docs/page.tsx           # movido de (static)/
│   │   ├── cockpit/
│   │   │   ├── page.tsx            # já existe (Wave A)
│   │   │   └── docs/page.tsx       # movido de (static)/
│   │   └── tutorials/
│   │       ├── page.tsx
│   │       └── <7 tutoriais>/page.tsx
│   ├── (static)/                   # REMOVIDO ao final desta wave (fica vazio)
│   └── sitemap.ts                  # ganha alternates pras rotas que eram English-only
└── messages/
    ├── en.json                     # novos namespaces: DocsShellShared, DocsPage,
    │                                #   CockpitDocsPage, TutorialsIndex,
    │                                #   TutorialGettingStarted, TutorialDaemon, ...
    ├── pt-BR.json
    └── es.json
```

## Passos

### 1. Extrair componentes compartilhados

- `Pager`, `Callout` (fallback title), `DocsToc` (se tiver texto fixo além dos
  labels já passados por prop) ganham `useTranslations`/props traduzidas.
- `install-tabs.tsx`: mesma extração que `landing/install.tsx` já recebeu na
  Wave A — decidir se vale **unificar os dois** (hoje são componentes quase
  duplicados) ou só replicar o padrão de tradução no componente separado.

**Aceite**: nenhum desses componentes tem string hardcoded em inglês; usados
de qualquer página `[locale]`, respeitam o locale ativo.

### 2. Mover + traduzir os 7 tutoriais

- Um `git mv` de cada `(static)/tutorials/<slug>/page.tsx` pra
  `[locale]/tutorials/<slug>/page.tsx`; extrair prosa pra
  `messages/en.json` sob um namespace por tutorial; traduzir pt-BR/es.
- Preservar blocos `CodeBlock`/`InlineCode`/exemplos de terminal intactos.
- `tutorials/page.tsx` (índice) também traduz.

**Aceite**: os 3 locales renderizam os 7 tutoriais + índice sem string solta
em inglês (fora nomes próprios/código); `pnpm build` continua limpo.

### 3. Mover + traduzir `/docs`

- Mesma mecânica do passo 2, aplicada a `docs/page.tsx` (984 linhas — maior
  volume de prosa contínua da wave, dividir a extração por `DocsSection` pra
  manter os PRs/commits revisáveis).
- `DOCS_TOC` (array de labels do sumário) também precisa de tradução.

**Aceite**: `/docs`, `/pt-BR/docs`, `/es/docs` renderizam completos; sumário
lateral (`DocsToc`) também traduzido; navegação por âncora continua
funcionando (ids das seções não mudam, só os labels visíveis).

### 4. Mover + traduzir `/cockpit/docs`

- Mesma mecânica, aplicada ao maior arquivo da wave (1380 linhas). Mesma
  recomendação de dividir a extração por seção.

**Aceite**: `/cockpit/docs` completo nas 3 locales; qualquer link interno
vindo de `/cockpit` (página de marketing, já traduzida na Wave A) continua
apontando pro anchor certo dentro do locale ativo.

### 5. Remover o grupo `(static)`

- Depois dos passos 2–4, `src/app/(static)/` fica vazio — apagar a pasta e
  `(static)/layout.tsx`. Voltar a ter um único root layout simplifica a
  arquitetura que a Wave A precisou criar como workaround.
- Revisar `src/proxy.ts`: o `matcher` não precisa mais excluir
  `docs`/`cockpit/docs`/`tutorials` — essas rotas passam a ser roteadas pelo
  next-intl como qualquer outra.

**Aceite**: `pnpm build` sem a pasta `(static)`; `/docs` sem prefixo carrega
em inglês (default locale), `/pt-BR/docs` e `/es/docs` carregam traduzidos;
nenhuma rota antiga quebra.

### 6. Metadata + hreflang + sitemap

- `generateMetadata` com `getTranslations` + `alternates.languages` nas 9
  páginas migradas (docs, cockpit/docs, 7 tutoriais + índice).
- `sitemap.ts`: essas páginas saem da lista "English-only" e entram na lista
  com alternates de locale (mesmo tratamento das páginas da Wave A).

**Aceite**: `/sitemap.xml` lista as 3 variantes de locale pra todas as
páginas antes English-only; `hreflang` correto em cada uma.

## Definition of Done

- [x] Componentes compartilhados (`Pager`, `Callout`, `install-tabs`, etc.)
      sem string hardcoded
- [x] 7 tutoriais + índice traduzidos (en/pt-BR/es), sem string solta
- [x] `/docs` traduzido, incluindo `DocsToc`
- [x] `/cockpit/docs` traduzido, incluindo `DocsToc`
- [x] `src/app/(static)/` removido; único root layout de novo
- [x] `src/proxy.ts` matcher simplificado (sem exclusões de Wave B)
- [x] `generateMetadata` + `hreflang` nas 9 páginas migradas
- [x] `sitemap.ts` sem nenhuma URL "English-only" restante
- [x] `messages/en.json` fonte de verdade; `pt-BR`/`es` com árvore idêntica
      (`scripts/check-messages.mjs` continua passando, agora ~1000+ chaves)
- [x] `pnpm lint` e `pnpm build` limpos

> Implementado 2026-08-26. Dois bugs reais encontrados e corrigidos no
> processo (documentando porque são fáceis de reintroduzir):
> - **ICU malformado**: literais como `<shortid>`, `<owner_pk_hash>`,
>   `{ status: "received" }` dentro de texto extraído são interpretados pelo
>   parser ICU do `next-intl` como tag/placeholder — `next-intl` não falha o
>   build (`pnpm build` passa com exit 0), a página só renderiza texto de
>   erro em runtime (`INVALID_MESSAGE`). Fix: escapar com aspas simples ICU
>   (`'<shortid>'`, `'{ ... }'`). Volume grande de exemplo de código/JSON
>   dentro de prosa (como docs/tutoriais) é o gatilho — a Wave A não bateu
>   nisso por não ter esse tipo de conteúdo. **Só um teste de render real
>   pega isso, não o build.**
> - **`proxy.ts` matcher desatualizado durante a migração incremental**: ao
>   mover uma rota pra dentro de `[locale]/` sem tirar a exclusão
>   correspondente do matcher, a rota fica sem rewrite do `next-intl` —
>   sintoma variou entre 404 (`/docs`) e 500 "static→dynamic at runtime"
>   (`/cockpit/docs`, por causa de `headers()`). Corrigido tirando a exclusão
>   assim que cada rota migra, não só no passo final.
> - **Gotcha de ambiente**: `next start` ignora `output: "standalone"`
>   silenciosamente e mascara os dois bugs acima. Teste local correto:
>   `node .next/standalone/server.js` com `public/` e `.next/static/`
>   copiados pra dentro antes. Vale documentar no `site/CLAUDE.md`.

## Fora de escopo (Wave C? — avaliar se ainda é necessário)

- `llms-full.txt` (conteúdo completo inline) — já adiado desde a Wave A,
  reavaliar depois que `/docs` e `/cockpit/docs` estiverem traduzidos: pode
  fazer sentido ainda ser só inglês, ou gerar uma versão por locale
- Geração automática do `llms.txt` a partir do conteúdo das páginas — mesma
  reavaliação
