# 63: Site do Cockpit 2.0

## Contexto

O Cockpit 2.0 sai com o site vendendo um produto que ele deixou de ser. A
`/download` diz "Cockpit drives a local Pi install" e manda instalar `pi`,
plugin e supervisor; a `/cockpit` promete "any tab can be a live Pi agent".
Tudo isso saiu do binário em 2026-09-17 (k16 do `cockpit/2.0-roadmap.kanban`).

Ao mesmo tempo o site é um site do Remote Pi com o Cockpit pendurado em
`/cockpit`, enquanto o Cockpit é o produto que ganhou tração.

Este plano cobre os cards **k1** (release notes consolidadas da 2.0.0) e **k2**
(documentar as novidades no site) do kanban, mais a reorganização do site e o
redesenho da página de download.

Insumos (levantamento feito em 2026-09-17 pelos agentes dos subprojetos):
- `.orchestration/results/site-audit-2.0.md`, raio-X do site
- `.orchestration/results/cockpit-distribuicao.md`, matriz de distribuição
- `.orchestration/results/cockpit-2.0-novidades.md`, o que contar da 2.0

## Decisões tomadas (2026-09-17, com o Jacob)

1. **Cockpit vira a home.** A landing do Cockpit passa a ser `/`; o Remote Pi
   desce para `/remote-pi/*`. Um domínio, um deploy. As URLs já nascem
   organizadas para um eventual split em subdomínio, que vira recorte de
   pastas em vez de reescrita.
2. **O cliente mobile entra na 2.0 com APK direto**, sem botão de loja. App
   Store e Play Store (k11/k12) seguem em Doing; quando saírem, acrescenta-se
   o botão.
3. **Windows sem assinatura.** SignPath submetido, aguardando aprovação: o
   aviso de SmartScreen fica, com a nota de que a assinatura está a caminho.
4. **Sem iOS na página.** Existe projeto iOS, mas zero CI, zero TestFlight,
   zero submissão. Não prometer.
5. **"Remoto" no Cockpit é SSH + cockpit-server**, nunca o relay do Remote Pi.
   Os dois produtos não se misturam na copy.

## Estrutura de rotas alvo

| Rota | Conteúdo |
|---|---|
| `/` | Landing do Cockpit 2.0 (hoje `/cockpit`) |
| `/download` | Cockpit: desktop, mobile (APK), cockpit-server na VPS |
| `/docs` | Referência do Cockpit (hoje `/cockpit/docs`) |
| `/tutorials/*` | Tutoriais do Cockpit (`cockpit-layouts`, `cockpit-team`) |
| `/remote-pi` | Landing do Remote Pi (hoje `/`) |
| `/remote-pi/docs` | Referência do Remote Pi (hoje `/docs`) |
| `/remote-pi/download` | App mobile Remote Pi + APK |
| `/remote-pi/tutorials/*` | `getting-started`, `mesh-local`, `mesh-remote`, `daemon`, `claude-mesh` |
| `/why`, `/privacy`, `/terms` | Como hoje (`/why` é do Remote Pi, revisar) |

Todas as rotas que mudam de lugar ganham redirect permanente em
`next.config.ts`, que já tem o mecanismo (o `cockpit-server.sh` usa).

## Passos

### Passo 1: Corrigir o que está factualmente errado (bloqueante da 2.0)

Independe da reorganização; pode ir primeiro.

- `site/src/app/cockpit/page.tsx:111`, "Any tab can be a live Pi agent:
  streaming rich markdown, taking images, editing your code while you watch
  the diff" descreve a aba de agente removida. Reescrever para o harness de
  escolha do usuário rodando num terminal de verdade.
- Rodapé da `/cockpit`: "Part of the Remote Pi ecosystem, where daemons,
  schedules, and the agent mesh live there" (também gramaticalmente quebrada).
- `/cockpit/docs:219`, "The mesh, pairing, and daemon features light up only
  once you install the plugin": não há mais aba de agente, pairing nem as abas
  Connectivity / Daemon Agents / Schedules.
- `/download`: o rodapé "Cockpit drives a local Pi install" e o link para o
  setup do Pi saem.
- `/tutorials/cockpit-team` assume onboarding checando `pi`, plugin e
  supervisor, e agentes falando pela mesh a partir das abas. Reescrever como
  "N terminais com claude/codex + a CLI `cockpit`", ou aposentar.

**Aceite**: nenhuma página descreve a aba de agente, pairing, daemons ou
schedules como parte do Cockpit; `pnpm lint && pnpm build` passam.

### Passo 2: Consertar a `/download` (três bugs reais)

- **Android descartado em silêncio**: o `latest.json` já traz
  `android/arm64/apk` e `android/universal/aab`, mas o type `CockpitPlatform`
  é `"macos" | "windows" | "linux"` e o filtro de `OS_GROUPS` ignora o resto
  sem erro. Aceitar `"android"`. Atenção: `src/lib/cockpit-release.ts` se
  declara "CLOSED CONTRACT" com o `cockpit-release.yml`, a mudança de type é
  cross-project e precisa ser combinada com o Cockpit.
- **Release notes como texto cru**: `manifest.notes` é markdown multi-linha
  (`###`, `**`, crases) renderizado dentro de um `<p>`. Renderizar markdown e
  linkar o GitHub Release da versão.
- **`cockpit-server` ausente**: nenhuma menção na página, embora o instalador
  esteja publicado e validado em VPS real (k25).

**Aceite**: os 8 artefatos do `latest.json` aparecem na página; as notes
renderizam formatadas; existe bloco de VPS.

### Passo 3: Redesenhar a `/download`

Seções, na ordem:

1. **Detecção de SO/arquitetura** com um CTA primário ("Download for your
   Mac"), e o resto acessível abaixo. Hoje não existe detecção nenhuma.
2. **Desktop**: macOS (dmg universal, assinado e notarizado, requer macOS
   12.0), Windows (Inno x64, aviso de SmartScreen + assinatura a caminho),
   Linux (deb/rpm × x64/arm64, avisar para fechar o app antes de atualizar).
3. **Mobile**: APK arm64 direto, com o passo de "instalar de fonte
   desconhecida". Sem link de loja, sem iOS.
4. **VPS / cockpit-server**, em destaque:
   `curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash`
   com a variante `--service` (systemd --user), `COCKPIT_VERSION=` para pinar,
   link para o script cru ("leia antes de canalizar pro bash") e a regra dura:
   **a versão do servidor tem que ser igual à do app**.
5. **Auto-update**: macOS e Windows se atualizam sozinhos (Sparkle/WinSparkle,
   appcast assinado); Linux não, o app avisa e o usuário baixa o pacote.
6. **Checksums**: o `ShaCopy` por artefato já existe; falta instruir como
   conferir (`shasum -a 256`) e linkar o `SHA256SUMS`.
7. **Requisitos mínimos** por plataforma (ver a tabela em
   `cockpit-distribuicao.md`).

**Aceite**: um usuário que nunca ouviu falar do produto instala em qualquer
plataforma sem sair da página, e um dono de VPS acha o one-liner.

### Passo 4: Reorganizar as rotas

Mover as páginas conforme a tabela acima, com redirects permanentes.
`layout.tsx` (`siteTagline`, `siteDescription`, keywords, OG), header, footer e
`opengraph-image.tsx` passam a falar do Cockpit. O Remote Pi ganha nav própria
dentro de `/remote-pi`.

Nota: `/cockpit` e `/` não compartilham sistema de seções (a `/cockpit` tem
`Shot` inline e não usa `components/landing/`). Isso facilita a troca, mas as
duas landings continuarão com componentes próprios, decidir se vale extrair
um sistema comum ou aceitar a duplicação.

**Aceite**: nenhum link interno quebrado; toda URL antiga redireciona;
`pnpm build` passa.

### Passo 5: Contar a 2.0

Reescrever a landing e ampliar `/docs` com o que a 2.0 trouxe, na prioridade
de `cockpit-2.0-novidades.md`. Manchetes:

1. Remote workspaces por SSH; as sessões sobrevivem ao cliente.
2. `cockpit-server` na VPS, a um curl de distância.
3. Cliente mobile (iPad/Android) como cliente remoto puro.
4. Documentos que viram abas: notebook, `.http`, kanban com dependências,
   Gallery, mermaid, janela de documento.
5. `.env.cockpit` com redaction de segredos.
6. Windows e Linux como cidadãos de primeira.

Pitch proposto:

> **A terminal that grew an IDE around your agents.** Run Claude Code, Codex,
> Pi or anything else in real terminals, local or on any machine over SSH ,
> with the viewer, diagnostics, git, worktrees and databases they need to work.

A saída do agente nativo se comunica **como foco, não como remoção**: a aba de
agente era um harness, com UI própria que nunca ganhou `.env.cockpit`, Restart,
status de turno nem as UI requests da extensão. O caminho do terminal ganhou
tudo isso e roda qualquer harness.

Fora do site: os bugs do ciclo beta, os refactors e a higiene de repo. O site
conta o estado atual, não a via-crúcis.

**Aceite**: as sete manchetes aparecem na landing ou nas docs; nenhuma feature
removida é citada como presente.

### Passo 6: Release notes consolidadas da 2.0.0 (k1)

Escrever a seção única 2.0.0 do `cockpit/CHANGELOG.md` a partir das entradas
1.28.0 → 1.28.33, usando o mesmo corte notícia/detalhe do passo 5. É o texto
que o Sparkle e a página de download mostram. Mora no subprojeto `cockpit`.

## Divergências achadas no levantamento (tarefas próprias)

Não bloqueiam o site, mas foram encontradas e valem correção antes da 2.0:

- `cockpit/packaging/README.md` está desatualizado: diz "gate manual" e lista
  `SPARKLE_PRIVATE_KEY` como pendente; ambos resolvidos desde 2026-07-29.
- `minimumSystemVersion` do appcast macOS diz 10.15.0, mas o deployment
  target é 12.0.
- Windows sem code signing: bloqueio externo (SignPath submetido, aguardando).

## Infra de downloads (rp-s3)

Levantado em `.orchestration/results/rp-s3-cockpit-2.0.md`. O rp-s3 é um
servidor axum de ~200 linhas que serve arquivos de um volume e aceita upload de
manifests. **Nenhum binário é hospedado nele**: tudo aponta para os assets da
GitHub Release.

Confirmado: o `latest.json` já traz os dois artefatos Android. O buraco do
Android é mesmo no site.

O que já dá para consumir e o site ignora:
- `sha256` e `size` por artefato (dá para mostrar "120 MB" sem HEAD extra).
- `notes`: o CHANGELOG completo da versão em markdown. O `<description>` do
  `appcast-macos.xml` tem a mesma coisa já em HTML.
- Os appcasts carregam `sparkle:version` (build number) e
  `minimumSystemVersion`, o dado de requisito de sistema que a página quer e
  não tem de nenhuma outra fonte.

Cuidados para o fetch:
- CORS é `*` para GET, mas `OPTIONS` responde 405 **sem** headers de CORS. Um
  fetch com header custom dispara preflight e morre. Regra: fetch sem headers,
  ou server-side (que é o default melhor, o ISR do Next controla o cache melhor
  que os 5 min do `max-age`).
- Listagem de diretório está desligada de propósito: não dá para descobrir
  nada por varredura.

### Decisões pendentes de infra

- **URL estável por artefato** (`/downloads/cockpit/latest/macos.dmg`) não
  existe. Dois caminhos: uma rota de redirect 302 no rp-s3 (~40 linhas de Rust,
  sem mudar o CI, mas exige rebuild da imagem e `docker compose pull` numa VPS
  **sem SSH**, que é a parte chata), ou usar o
  `releases/latest/download/<nome>` que o GitHub já dá de graça, custo zero,
  mas exige o CI publicar cópias com nome sem versão. Só vale se quisermos link
  bonito para README, docs e botão de download.
- **Histórico de versões** não existe no rp-s3 (um único `latest.json`,
  sobrescrito; os appcasts têm um único `<item>`). Recomendação: histórico via
  GitHub Releases API server-side, com cache. Duplicar histórico nos dois
  lugares é risco de divergência sem ganho.

### Pendência que afeta a página do Remote Pi

O `app-release.yml` **não** usa o endpoint de upload: continua com gate manual.
O `downloads/app/latest.json` está parado em **1.1.2, de 2026-07-16**, e
`downloads/app/SHA256SUMS` responde **404** (assimetria com o cockpit). Antes
de publicar a `/remote-pi/download`, confirmar se 1.1.2 é mesmo a última versão
do app e considerar migrar esse workflow para o `PUT /upload`, matando o último
gate manual.

## Definition of Done

- [ ] Nenhuma página do site descreve a aba de agente, pairing, daemons ou
      schedules como parte do Cockpit
- [ ] Os 8 artefatos do `latest.json` aparecem na `/download`, Android incluso
- [ ] Release notes renderizam como markdown, com link para o GitHub Release
- [ ] A `/download` tem bloco de cockpit-server com o one-liner de VPS
- [ ] A `/download` detecta SO/arquitetura e oferece um CTA primário
- [ ] A `/download` explica auto-update, checksums e requisitos mínimos
- [ ] Cockpit é a home; Remote Pi vive em `/remote-pi/*` com redirects
- [ ] A landing conta as sete manchetes da 2.0
- [ ] `cockpit/CHANGELOG.md` tem a seção consolidada 2.0.0 (k1)
- [ ] A página mostra requisitos mínimos vindos do appcast (build number e
      minimumSystemVersion), não hardcoded
- [ ] Decidido se haverá URL estável por artefato (rp-s3 ou GitHub)
- [ ] Confirmado se `downloads/app/latest.json` (1.1.2) está atualizado
- [ ] `pnpm lint && pnpm build` passam

## Próximos planos

- Publicação nas lojas (k11/k12) destrava o botão de loja no passo 3.
- Assinatura Windows (k3) remove o aviso de SmartScreen.
