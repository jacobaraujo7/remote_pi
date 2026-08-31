# 62 — Site: internacionalização (en/pt-BR/es) + llms.txt

## Contexto

O `site/` (NextJS 16, App Router) hoje **não tem nenhuma infra de i18n** —
zero locale, todo texto hardcoded em JSX, `<html lang="en">` fixo no
`layout.tsx`. É um site de conteúdo pesado, não uma landing pequena:

| Área | Volume | Onde |
|---|---|---|
| Landing | moderado | `app/page.tsx` + `components/landing/*` |
| Nav/footer/legal | pequeno | `components/header.tsx`, `footer.tsx`, `app/privacy`, `app/terms` |
| Página Cockpit (marketing) | moderado | `app/cockpit/page.tsx` |
| **Docs do Cockpit** | **1380 linhas** | `app/cockpit/docs/page.tsx` |
| Docs geral | 984 linhas | `app/docs/page.tsx` |
| 7 tutoriais | ~1850 linhas | `app/tutorials/*/page.tsx` |

**~5900 linhas no total**, ~70% (docs + tutoriais) é prosa técnica densa —
volume e risco de tradução bem maiores que UI curta. Também não existe
`robots.txt` nem `sitemap.xml` hoje.

Separado (mas relacionado — mesmo objetivo de "visibilidade pra IAs"): criar
`public/llms.txt` seguindo a convenção [llmstxt.org](https://llmstxt.org),
com o **Cockpit em destaque**, por pedido explícito.

### Decisões fechadas nesta conversa (2026-08-26)

| # | Decisão |
|---|---|
| **A** | Escopo **faseado**. Este plano é a **Wave A**: landing, nav/header/footer, legal (privacy/terms), download, página Cockpit (marketing, **não** `cockpit/docs`). Docs geral, docs do Cockpit e os 7 tutoriais ficam pra uma **Wave B** (plano futuro) — é 70% do volume e o maior risco de tradução técnica errada |
| **B** | Lib = **`next-intl`** — padrão de fato pro App Router, funciona em Server Components (`getTranslations`) sem forçar `"use client"` em toda página, suporta `generateStaticParams`/`alternates.languages` (hreflang) |
| **C** | Locale URL = **prefixo "as-needed"**: `en` continua em `/` (sem prefixo — preserva URLs já indexadas/linkadas), `pt-BR` em `/pt-BR`, `es` em `/es` |
| **D** | Páginas da Wave B (`/docs`, `/cockpit/docs`, `/tutorials/**`) **ficam fora da rota `[locale]`** nesta wave — continuam exatamente como estão (só inglês, sem prefixo), excluídas do matcher do middleware. Evita a pergunta "o que mostrar pra pt-BR numa página não traduzida" adiando-a pra quando a Wave B existir de fato |
| **E** | `en.json` é a **árvore-fonte** (mesma regra do `slang` no cockpit): `pt-BR.json`/`es.json` precisam ter as mesmas chaves; build falha se faltar uma |
| **F** | `llms.txt` fica **só em inglês**, não localizado — mesma lógica de "saída pra máquina não se traduz" (CLI aqui, crawler/IA ali). `robots.txt` entra de brinde (custo baixo, mesmo objetivo de visibilidade) |
| **G** | Nomes próprios e trechos técnicos **não traduzem**: `Pi`, `Cockpit`, `Claude Code`, nomes de comando/flag, blocos de código e exemplos de terminal — mesma regra que já existe no `cockpit/CLAUDE.md` |

## Estrutura esperada

```
site/
├── middleware.ts                       # next-intl: matcher exclui /docs, /cockpit/docs,
│                                        #   /tutorials/**, /_next, /api, estáticos
├── public/
│   ├── llms.txt                        # novo — Cockpit em destaque, só inglês
│   └── robots.txt                      # novo — allow explícito pra crawlers de IA
└── src/
    ├── i18n/
    │   ├── routing.ts                  # defineRouting({locales, defaultLocale:'en',
    │   │                                #   localePrefix:'as-needed'})
    │   ├── navigation.ts               # Link/redirect/usePathname localizados
    │   └── request.ts                  # getRequestConfig → carrega messages/<locale>.json
    ├── messages/
    │   ├── en.json                     # fonte de verdade
    │   ├── pt-BR.json
    │   └── es.json
    └── app/
        ├── layout.tsx                  # root mínimo (passthrough, next-intl exige)
        ├── sitemap.ts                  # novo — inclui alternates de locale da Wave A
        ├── docs/  cockpit/docs/  tutorials/**   # INTOCADOS nesta wave (fora do [locale])
        └── [locale]/
            ├── layout.tsx              # NextIntlClientProvider, fonts, Header/Footer, <html lang>
            ├── page.tsx                # landing
            ├── download/page.tsx
            ├── privacy/page.tsx
            ├── terms/page.tsx
            └── cockpit/page.tsx        # marketing (docs/ do cockpit fica de fora, é Wave B)
```

## Passos

### 1. Infra `next-intl` + middleware

- Instalar `next-intl`; criar `src/i18n/{routing,navigation,request}.ts`.
- `middleware.ts` com `matcher` **excluindo** `/docs`, `/cockpit/docs`,
  `/tutorials/:path*`, `/_next/*`, `/api/*`, arquivos com extensão (`.xml`,
  `.txt`, `.svg`, `.png`...).
- Mover as rotas da Wave A pra `src/app/[locale]/...`; `docs/`,
  `cockpit/docs/`, `tutorials/` **continuam onde estão**, fora do `[locale]`.
- `app/layout.tsx` vira passthrough mínimo; `app/[locale]/layout.tsx` herda o
  que hoje está no root (fonts, `SiteHeader`/`SiteFooter`, `<html lang={locale}>`)
  envolvido em `NextIntlClientProvider`.

**Aceite**: `pnpm dev` → `/` carrega em inglês sem prefixo, `/pt-BR` e `/es`
carregam (mesmo com strings ainda hardcoded nesta etapa), `/docs`,
`/cockpit/docs` e qualquer `/tutorials/*` continuam funcionando exatamente
como hoje, sem prefixo de locale.

### 2. Extrair header/footer/metadata do layout raiz

- `messages/en.json` ganha as chaves de `SiteHeader`, `SiteFooter` e a
  metadata do `layout.tsx` (title/description/OG/twitter).
- Traduzir para `pt-BR.json`/`es.json` já nesta etapa (não deixar chave em
  inglês solta esperando etapa futura).

**Aceite**: trocar locale muda header/footer/metadata sem erro de chave
faltando; build falha de propósito se uma chave sumir de um dos 3 arquivos
(confirmar que o `next-intl` está configurado pra isso, não só logar warning).

### 3. Seletor de idioma no header

- Componente client novo, usando `Link`/`usePathname` de
  `src/i18n/navigation.ts` pra trocar de locale **preservando o path atual**
  (ex.: em `/download` trocar pra pt-BR vai pra `/pt-BR/download`, não pra
  `/pt-BR`).
- Rótulos são autoglotônimos (`EN`/`PT-BR`/`ES`) — não traduzem (decisão G).
- Numa página fora do `[locale]` (`/docs`, `/tutorials/*`), o seletor ainda
  não tem o que fazer nesta wave — decidir na implementação: esconder, ou
  desabilitar com tooltip "disponível em breve" (ambos aceitáveis, é
  ergonomia, não arquitetura).

**Aceite**: trocar idioma em qualquer página da Wave A troca a URL e mantém
a rota relativa; nenhum link quebrado.

### 4. Extrair + traduzir o conteúdo da Wave A

- Landing (`app/[locale]/page.tsx` + `components/landing/*`), `download`,
  `privacy`, `terms`, `cockpit/page.tsx` (marketing).
- Preservar **nomes próprios e blocos de código intactos** (decisão G) —
  comandos de instalação, exemplos de terminal, nomes de harness/modelo.

**Aceite**: as 3 locales renderizam essas páginas sem string em inglês
vazando (fora nomes próprios/termos técnicos) nem chave faltando.

### 5. Metadata por locale + hreflang

- `generateMetadata` de cada página da Wave A usa `getTranslations`;
  `alternates.languages` aponta pras 3 versões de cada página.

**Aceite**: view-source de `/pt-BR` mostra `<html lang="pt-BR">` e
`<link rel="alternate" hreflang="es" href=".../es">` (e `en`) na página
equivalente.

### 6. `sitemap.ts`

- `src/app/sitemap.ts` novo: lista as páginas da Wave A com suas 3 variantes
  de locale (alternates) + as páginas English-only de hoje (`docs`,
  `cockpit/docs`, `tutorials/*`) como estão.

**Aceite**: `/sitemap.xml` acessível e lista todas as URLs corretas.

### 7. `llms.txt` + `robots.txt` (independente de i18n)

- `public/llms.txt`: H1 `# Remote Pi`, blockquote-resumo, seções em ordem —
  **Cockpit primeiro** (página + docs), depois Mobile app, Docs geral,
  Tutorials, GitHub. Cada item: link absoluto + uma frase. Só inglês
  (decisão F).
- `public/robots.txt`: `Allow: /` geral + entradas explícitas pra
  `GPTBot`, `ClaudeBot`, `Claude-User`, `Claude-SearchBot`, `PerplexityBot`,
  `Google-Extended`, `CCBot`; `Sitemap: https://remote-pi.jacobmoura.work/sitemap.xml`.

**Aceite**: `/llms.txt` e `/robots.txt` acessíveis em produção; as duas
primeiras entradas de `llms.txt` são a página e a doc do Cockpit.

## Definition of Done

- [x] `next-intl` instalado, `middleware.ts` com matcher excluindo as rotas da Wave B
- [x] `[locale]` cobre landing/download/privacy/terms/cockpit(marketing); docs/tutoriais intocados
- [x] `messages/en.json` fonte de verdade; `pt-BR.json`/`es.json` com árvore idêntica, build falha se faltar chave
- [x] Seletor de idioma no header preserva o path ao trocar locale
- [x] Wave A 100% traduzida (pt-BR e es) sem string solta em inglês (fora nomes próprios/código)
- [x] `generateMetadata` por locale + `hreflang` alternates
- [x] `sitemap.ts` com alternates de locale
- [x] `public/llms.txt` com Cockpit em destaque (primeiras entradas)
- [x] `public/robots.txt` com allow explícito pra crawlers de IA + `Sitemap:`
- [x] `pnpm lint` e `pnpm build` limpos

> Implementado 2026-08-26. Desvios do plano original:
> - `middleware.ts` → `src/proxy.ts` (Next.js 16 depreciou `middleware.ts` em
>   favor de `proxy.ts`; mesma API do `next-intl`).
> - `/why` entrou na Wave A (não existia quando o plano foi escrito; é
>   marketing curto, mesma natureza de `/cockpit`, não prosa densa de doc).
> - Layout raiz: Next.js exige `<html>`/`<body>` únicos por root, então em vez
>   de "passthrough mínimo" o app ganhou dois roots via route groups —
>   `app/[locale]/layout.tsx` (Wave A) e `app/(static)/layout.tsx` (Wave B,
>   preservado como estava, só com `NextIntlClientProvider` fixo em `en` pra
>   `Header`/`Footer` compartilhados funcionarem sem quebrar).

## Fora de escopo (Wave B — próximo plano)

- Tradução de `app/docs/page.tsx`, `app/cockpit/docs/page.tsx` e dos 7
  `app/tutorials/*/page.tsx` (~4200 linhas, 70% do volume total)
- `llms-full.txt` (conteúdo completo inline, não só links)
- Geração automática de `llms.txt` a partir do conteúdo das páginas —
  mantido manual nesta fase (conteúdo não vem de Markdown/MDX fonte único)
