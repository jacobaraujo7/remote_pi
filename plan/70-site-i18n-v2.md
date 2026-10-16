# 70 — Site: internacionalização (en/pt-BR/es) sobre a estrutura 2.0

## Contexto

Este plano **substitui** os planos 62 e 63 da branch `feat/site-i18n-llms-txt`
(PR #165, aberto antes da 2.0). Os números 62 e 63 já foram ocupados no `main`
por outros planos (`62-cockpit-gallery`, `63-site-cockpit-2.0`), por isso o
trabalho é renumerado como 70.

O PR #165 internacionalizou o site com `next-intl`, mas sobre a árvore de rotas
antiga. O [plano 63 (Site do Cockpit 2.0)](./63-site-cockpit-2.0.md) reorganizou
tudo: o Cockpit virou a home e o Remote Pi desceu para `/remote-pi/*`. Um merge
dá conflito estrutural (rename/delete) em 17 arquivos, e resolver na mão
equivale a reescrever. Por isso: **branch nova a partir do `main`, reaproveitando
a infraestrutura e as traduções que ainda valem** e refazendo o `[locale]` sobre
as rotas novas.

Escopo: **o site inteiro** (landing, download, docs, tutoriais, legais, Remote Pi)
nos três idiomas, mais `llms.txt` e `robots.txt`. Nada fica só em inglês no fim.

### O que existe no PR #165 e pode ser reaproveitado

A branch antiga continua acessível como `origin/feat/site-i18n-llms-txt` (fork
`tecrodrigocastro`). Trazer arquivo a arquivo com:

```bash
git checkout origin/feat/site-i18n-llms-txt -- site/src/i18n site/scripts/check-messages.mjs ...
```

| Artefato | Destino | Observação |
|---|---|---|
| `src/i18n/{routing,request,navigation,alternates}.ts` | igual | Independente de rotas. Revisar `alternates.ts` para as rotas novas |
| `scripts/check-messages.mjs` | igual | Falha o build se `pt-BR`/`es` divergirem de `en` |
| `src/proxy.ts` | igual | **Reescrever o matcher**: nasce sem exclusões, já que não há rota fora do `[locale]` |
| `src/components/language-switcher.tsx` | igual | Preserva o path ao trocar de locale |
| `public/llms.txt`, `public/robots.txt` | igual | `llms.txt` precisa refletir a 2.0 (ver passo 7) |
| `src/messages/{en,pt-BR,es}.json` | **garimpar** | Chaves de header/footer/tutoriais Remote Pi servem. Landing e `/cockpit` mudaram de conteúdo: re-extrair |
| `next.config.ts`, `package.json` | **mesclar** | Há redirects novos no `main`; não sobrescrever |

### Mapa de rotas (antigo → novo)

| Rota nova (2.0) | Origem no PR #165 | Reaproveitamento das traduções |
|---|---|---|
| `/` (landing Cockpit) | `[locale]/cockpit/page.tsx` | Baixo: a copy foi reescrita na 2.0 |
| `/download` (Cockpit) | `[locale]/download/page.tsx` | Baixo: página redesenhada (`components/download/*`) |
| `/docs` (Cockpit) | `[locale]/cockpit/docs/page.tsx` | Parcial: conferir o que mudou |
| `/tutorials/cockpit-layouts`, `cockpit-team` | idem | Parcial: `cockpit-team` foi reescrito |
| `/tutorials/cockpit-telemetry` | — (nova) | Nenhum: traduzir do zero |
| `/remote-pi` | `[locale]/page.tsx` | Alto: mesma landing, outro caminho |
| `/remote-pi/docs` | `[locale]/docs/page.tsx` | Alto |
| `/remote-pi/download` | — (era parte de `/download`) | Parcial |
| `/remote-pi/why` | `[locale]/why/page.tsx` | Alto |
| `/remote-pi/tutorials/*` (5) | `[locale]/tutorials/*` | Alto: só mudaram de lugar |
| `/privacy`, `/terms` | `[locale]/privacy`, `terms` | Alto |

## Decisões

Herdadas do PR #165 (fechadas em 2026-08-26) e mantidas:

| # | Decisão |
|---|---|
| **A** | Lib = `next-intl`, `localePrefix: "as-needed"` (`en` sem prefixo, `pt-BR` em `/pt-BR`, `es` em `/es`) |
| **B** | `en.json` é a árvore-fonte; `pt-BR.json`/`es.json` com as mesmas chaves; o build falha se divergirem |
| **C** | `llms.txt` só em inglês (saída para máquina não se traduz); `robots.txt` junto |
| **D** | Nomes próprios e trechos técnicos não se traduzem: `Pi`, `Cockpit`, `Claude Code`, comandos, flags, variáveis de ambiente, nomes de arquivo, blocos de código e saída de terminal |
| **E** | Cuidado com ICU: literais como `<shortid>` ou `{ status: "received" }` dentro de texto extraído viram tag/placeholder no parser do `next-intl`. Escapar com aspas simples ICU. O `pnpm build` passa mesmo assim, então só um teste de render real pega |

Novas neste plano:

| # | Decisão |
|---|---|
| **F** | **Sem rota fora do `[locale]`.** O PR #165 criou o grupo `(static)` como solução temporária para manter páginas só em inglês. Aqui tudo nasce sob um único root `[locale]/layout.tsx`, então a solução temporária não existe |
| **G** | **As rotas novas da 2.0 são a fonte.** Não recriar a estrutura antiga. Os redirects permanentes que o plano 63 definiu em `next.config.ts` continuam valendo e têm que funcionar com e sem prefixo de locale (`/pt-BR/cockpit` → `/pt-BR`) |
| **H** | **Entrega em ondas, um PR por onda** (ver abaixo). Ondas menores são o que o Jacob pediu nas revisões recentes (ver #245) |
| **I** | **A copy da 2.0 manda.** Onde a tradução antiga contradiz o plano 63 (ex.: "Cockpit drives a local Pi install", aba de agente, pairing, daemons no Cockpit), vale o texto atual do `main`. Nunca traduzir o texto desatualizado |

## Estrutura esperada

```
site/
├── public/
│   ├── llms.txt                  # Cockpit em destaque, só inglês
│   └── robots.txt                # allow explícito para crawlers de IA
├── scripts/check-messages.mjs
└── src/
    ├── proxy.ts                  # next-intl, matcher sem exclusões de rota
    ├── i18n/{routing,navigation,request,alternates}.ts
    ├── messages/{en,pt-BR,es}.json
    ├── components/               # header, footer, download/*, docs-shell, docs-toc,
    │                             #   pager, callout, install-tabs, language-switcher
    └── app/
        ├── sitemap.ts
        └── [locale]/
            ├── layout.tsx        # único root: provider, fonts, header/footer, <html lang>
            ├── page.tsx          # landing do Cockpit
            ├── download/  docs/  privacy/  terms/
            ├── tutorials/{page,cockpit-layouts,cockpit-team,cockpit-telemetry}
            └── remote-pi/
                ├── layout.tsx  page.tsx  docs/  download/  why/
                └── tutorials/{page,getting-started,mesh-local,mesh-remote,daemon,claude-mesh}
```

## Passos

Cada passo termina com `pnpm lint && pnpm build` limpos. Teste de render sempre
com `node .next/standalone/server.js`: o `next start` ignora
`output: "standalone"` e esconde erros de ICU e de matcher.

### Onda 1 — Infra, layout e home (PR 1)

**1. Infra `next-intl` sobre a árvore 2.0.**
- Trazer `src/i18n/*`, `check-messages.mjs`, `language-switcher.tsx` do PR #165.
- Criar `src/proxy.ts` e `src/app/[locale]/layout.tsx` como único root.
- Mover **todas** as rotas atuais para dentro de `[locale]/`, sem mudar conteúdo.
- Mesclar `next.config.ts` mantendo os redirects da 2.0.

*Aceite*: `/`, `/pt-BR`, `/es` carregam; todas as rotas da 2.0 (incluindo
`/remote-pi/*`) respondem sem prefixo em inglês; os redirects antigos
(`/cockpit`, `/why`, `/tutorials/getting-started`...) continuam levando ao lugar
certo, também com prefixo de locale.

**2. Header, footer e metadata do layout raiz.** Extrair as chaves, traduzir
`pt-BR` e `es` na mesma leva (nenhuma chave solta em inglês).

*Aceite*: trocar de idioma muda header, footer e metadata; remover uma chave de
um dos três arquivos **falha o build**.

**3. Seletor de idioma.** Preserva o path (`/download` → `/pt-BR/download`).

*Aceite*: trocar de idioma em qualquer rota mantém a rota relativa, sem link quebrado.

**4. Landing do Cockpit (`/`) e `/download` do Cockpit.** Incluir os componentes
novos da 2.0: `components/download/*` (picker de plataforma, card, notas de
release, cópia de SHA). Os textos do `latest.json` (notas de release) vêm do
manifest e **não se traduzem**.

*Aceite*: as três locales renderizam as duas páginas sem inglês vazando (fora
nomes próprios e código).

**5. Metadata, hreflang e `sitemap.ts`** para as páginas da onda.

*Aceite*: `view-source` de `/pt-BR` mostra `<html lang="pt-BR">` e os
`hreflang` de `en` e `es`; `/sitemap.xml` lista as rotas com as três variantes.

### Onda 2 — Remote Pi (PR 2)

**6. `/remote-pi`, `/remote-pi/download`, `/remote-pi/why`, `/privacy`, `/terms`.**
Garimpar as traduções do PR #165 e conferir contra o texto atual.

*Aceite*: as três locales renderizam sem inglês solto; a copy não mistura os
dois produtos (decisão 5 do plano 63: "remoto" no Cockpit é SSH +
`cockpit-server`, nunca o relay).

**7. `llms.txt` e `robots.txt` da 2.0.** Cockpit primeiro (home, docs, download),
depois Remote Pi em `/remote-pi`, tutoriais e GitHub. `robots.txt` com `Allow: /`
e entradas explícitas para `GPTBot`, `ClaudeBot`, `Claude-User`,
`Claude-SearchBot`, `PerplexityBot`, `Google-Extended`, `CCBot`, mais `Sitemap:`.

*Aceite*: `/llms.txt` e `/robots.txt` acessíveis; as duas primeiras entradas do
`llms.txt` são a home e a doc do Cockpit; nenhum link aponta para rota antiga.

### Onda 3 — Tutoriais (PR 3)

**8. Componentes compartilhados** (`docs-shell`, `docs-toc`, `pager`, `callout`,
`install-tabs`): chaves de tradução na mesma leva do primeiro passo que os usa.

**9. Tutoriais do Cockpit**: `cockpit-layouts`, `cockpit-team`,
`cockpit-telemetry` (este último do zero) e a página índice `/tutorials`.

**10. Tutoriais do Remote Pi** (5) e o índice `/remote-pi/tutorials`.

*Aceite (8–10)*: as três locales renderizam todos os tutoriais; comandos, flags,
variáveis e saídas de terminal idênticos nas três; o pager e o TOC funcionam em
cada locale.

### Onda 4 — Docs (PR 4)

**11. `/remote-pi/docs`**, depois **12. `/docs` (Cockpit)**, por último por ser a
maior e a mais densa em comandos e flags. A referência foi alterada na 2.0:
traduzir o texto atual do `main`, não o do PR #165 (decisão I).

*Aceite*: as três locales renderizam as duas páginas; um diff dos blocos de
código e dos nomes de flag entre `en` e as outras locales não mostra diferença.

## Definition of Done

- [ ] `next-intl` e `proxy.ts` sobre a árvore 2.0, sem nenhuma rota fora do `[locale]`
- [ ] `messages/en.json` como fonte; `pt-BR.json`/`es.json` idênticos em chaves; build falha se divergir
- [ ] Redirects da 2.0 funcionam com e sem prefixo de locale
- [ ] Seletor de idioma preserva o path em todas as rotas
- [ ] Onda 1: header, footer, home do Cockpit e `/download` nas 3 locales
- [ ] Onda 2: `/remote-pi`, `/remote-pi/download`, `/remote-pi/why`, privacy e terms nas 3 locales
- [ ] Onda 2: `llms.txt` e `robots.txt` atualizados para a 2.0
- [ ] Onda 3: todos os tutoriais (Cockpit e Remote Pi) nas 3 locales
- [ ] Onda 4: `/docs` e `/remote-pi/docs` nas 3 locales
- [ ] `generateMetadata` por locale, `hreflang` e `sitemap.ts` com alternates
- [ ] Nenhum texto da copy antiga (aba de agente, pairing, daemons no Cockpit) reintroduzido
- [ ] `pnpm lint` e `pnpm build` limpos; teste de render com `node .next/standalone/server.js`
- [ ] PR #165 fechado com link para os PRs novos

## Riscos

- **Volume**: ~5900 linhas de conteúdo, 70% prosa técnica densa. O risco é
  tradução técnica errada, não código. Mitigação: a decisão D e o diff dos blocos
  de código na onda 4.
- **ICU malformado** passa no build e quebra em runtime (decisão E). Mitigação:
  render real de cada página nas três locales antes do PR.
- **Conflito com mudanças em paralelo no `site/`**: o `main` anda rápido (284
  commits desde a base do PR #165). Rebasear a cada onda e manter ondas curtas.
- **Contrato do `latest.json`**: `src/lib/cockpit-release.ts` é um "closed
  contract" com o `cockpit-release.yml`. A i18n não deve mexer nele.

## Fora de escopo

- `llms-full.txt` e geração automática do `llms.txt` a partir do conteúdo.
- Novos idiomas além de `en`, `pt-BR`, `es`.
- Reescrita de copy: este plano traduz o texto vigente, não o revisa.

## Próximos planos

Nenhum previsto. Se aparecer demanda de um idioma novo, é aditivo: um
`<locale>.json` a mais, sem mudança de arquitetura.
