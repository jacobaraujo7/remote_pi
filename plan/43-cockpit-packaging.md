# 43 — Cockpit: Empacotamento & Distribuição (macOS · Windows · Linux)

## Contexto

O Cockpit (`cockpit/`, Flutter desktop) está com MVP funcional: os três runners
existem (`macos/`, `windows/`, `linux/`), lint e testes verdes, e o Linux já tem
integração de desktop (app ID `work.jacobmoura.cockpit`, `.desktop`, ícones).
Mas **nada está pronto pra distribuir**: assinatura macOS é ad-hoc, bundle ID é
placeholder `com.example.cockpit`, `CompanyName` do Windows é `com.example`,
não há instalador de nenhuma plataforma, nenhum workflow de CI no monorepo e
nenhum script de release.

### Decisões fechadas (2026-06-11)

| Tema | Decisão |
|---|---|
| Lojas | **Não** publicar em lojas (App Store/MS Store/Snap/Flathub) |
| Builds | **GitHub Actions** — matrix macOS/Windows/Linux, trigger por tag `cockpit-v*` |
| Hospedagem dos artefatos | **GitHub Releases** (tags prefixadas `cockpit-v*`; CDN/banda grátis). ⚠️ **Revisão 2026-06-12**: a decisão original era "artefatos direto pra VPS via rsync", mas **a VPS não tem acesso SSH** — Releases com tag prefixada resolve o monorepo como puro storage de assets. A VPS (rp-s3) hospeda **só o `latest.json`** (e opcionalmente `SHA256SUMS`), colocado **manualmente** pelo usuário a cada release — funciona como gate de publicação |
| Assinatura macOS | **Developer ID Application + notarização** (conta Apple Developer já existe) |
| Assinatura Windows | **Sem assinatura** nesta fase — aviso do SmartScreen aceito e documentado; certificado pode vir depois sem retrabalho |
| Linux | **`.deb` e `.rpm`**, arquiteturas **x86_64 e arm64** (só 64 bits, sem AppImage/tarball) |
| Updates | **Sem auto-update in-app** nesta fase. Descoberta de versão nova acontece pelo **Site** (`site/`), via página de downloads alimentada por um `latest.json` na VPS. ⚠️ **Revisão 2026-06-12**: além do site, o Cockpit ganha um **aviso leve in-app** (mini card no shell, dispensável por versão, consultando o `latest.json`) com download por clique — continua **sem** auto-replace (passo 7) |

### Matriz de artefatos por release

| Plataforma | Arquitetura | Artefato |
|---|---|---|
| macOS | universal (x64+arm64, binário único do Flutter) | `RemotePiCockpit-<v>-macos-universal.dmg` (assinado + notarizado + stapled) |
| Windows | x64 | `RemotePiCockpit-Setup-<v>-windows-x64.exe` (Inno Setup, sem assinatura) |
| Linux | x86_64 | `remote-pi-cockpit_<v>_amd64.deb` · `remote-pi-cockpit-<v>.x86_64.rpm` |
| Linux | arm64 | `remote-pi-cockpit_<v>_arm64.deb` · `remote-pi-cockpit-<v>.aarch64.rpm` |

Total: **6 artefatos** + `SHA256SUMS` + `latest.json` por release.

### Premissas e riscos a validar cedo

- **Runner Linux arm64**: usar `ubuntu-24.04-arm`. ~~Validar custo~~ →
  **resolvido 2026-06-12**: o repo `jacobaraujo7/remote_pi` é público, então
  os runners arm64 são gratuitos.
- **`.rpm` em runner Ubuntu**: `rpmbuild` disponível via `apt install rpm` —
  não precisa de runner Fedora.
- **Versão Windows no `Runner.rc`**: scout viu `VERSION_AS_STRING "1.0.0"`;
  pode ser apenas o fallback `#else` do template (Flutter injeta
  `FLUTTER_VERSION_*` em build). Verificar; se for hardcode real, corrigir
  pra usar os defines gerados.
- **Dependências runtime do Cockpit** (`pi` CLI, supervisor, node): **não
  embarcar** nos instaladores. O onboarding gate do app já checa e orienta.
- **Ferramenta de empacotamento**: **`plus_flutter_distributor`** / projeto
  **Fastforge** (CLI: `dart pub global activate fastforge`) — cobre dmg, exe
  via Inno Setup, deb e rpm com configs declarativas. **Não usar o
  `flutter_distributor` original: está descontinuado** (renomeado pra
  Fastforge). Fallbacks se algum formato decepcionar: `create-dmg` (macOS),
  `iscc` direto (Windows), `fpm` (deb/rpm).

## Estrutura esperada

```
cockpit/
  pubspec.yaml                      # SSOT de versão (x.y.z+n)
  distribute_options.yaml           # config do fastforge (plus_flutter_distributor)
  macos/packaging/dmg/make_config.yaml    # convenção REAL do Fastforge:
  windows/packaging/exe/make_config.yaml  # <plataforma>/packaging/<formato>/
  linux/packaging/deb/make_config.yaml    # (path hardcoded no loader;
  linux/packaging/rpm/make_config.yaml    #  diagrama corrigido 2026-06-12)
  packaging/README.md               # runbook de release (macOS documentado)
  CHANGELOG.md
.github/workflows/
  cockpit-release.yml               # trigger: tag cockpit-v* (+ workflow_dispatch)
site/
  src/app/download/...              # página de downloads (consome latest.json)
VPS:
  /downloads/cockpit/<versão>/<artefatos>
  /downloads/cockpit/latest.json    # {version, date, platforms: {url, sha256, size}}
  /downloads/cockpit/SHA256SUMS
```

## Passos

### 1. Identidade e metadados (cockpit/)

> **Status 2026-06-12**: concluído via `[ORCH:43-cockpit-identity-packaging]`.
> Bundle ID já estava `work.jacobmoura.cockpit`; display name, Hardened
> Runtime, Runner.rc e metainfo AppStream aplicados. Confirmado: a versão do
> Windows usa os defines `FLUTTER_VERSION_*` (o `1.0.0` era só fallback).

- Bundle ID macOS: adotar **`work.jacobmoura.cockpit`** (mesmo app ID que o
  Linux já usa), fixando `PRODUCT_BUNDLE_IDENTIFIER` no pbxproj/xcconfig.
  Nome de exibição: **"Remote Pi Cockpit"**; binário continua `cockpit`.
- Windows `Runner.rc`: `CompanyName` → `Jacob Moura`, `ProductName` →
  `Remote Pi Cockpit`; confirmar que a versão vem dos defines
  `FLUTTER_VERSION_*` (corrigir se hardcoded).
- macOS Release: garantir Hardened Runtime habilitado (exigência da
  notarização) com `Release.entitlements` atual (sandbox off é compatível
  com Developer ID).
- Linux: adicionar `metainfo.xml` (AppStream) mínimo — nome, descrição,
  licença, screenshot opcional.

**Aceite**: `flutter build macos|windows|linux --release` local (macOS) mostra
nome/bundle ID/versão corretos no app gerado (`plutil -p Info.plist`; no
Windows/Linux conferir via CI no passo 3).

### 2. Empacotamento local (cockpit/)

> **Status 2026-06-12**: macOS ponta a ponta concluído — DMG universal
> assinado, notarizado (**Accepted**) e stapled; `spctl` = accepted /
> Notarized Developer ID (`dist/RemotePiCockpit-1.0.0-macos-universal.dmg`).
> make_configs Windows/Linux prontos; validação `.deb`/`.rpm` em container
> ficou pro CI (passo 3). DMG gerado via `hdiutil` (runbook) — no CI, decidir
> entre `npm i -g appdmg` (maker do Fastforge) ou manter `hdiutil`. Licença
> nos pacotes ficou `LicenseRef-proprietary` até o monorepo fechar licença.

- Instalar o Fastforge (`dart pub global activate fastforge`) e criar os 4
  `make_config.yaml` + `distribute_options.yaml`.
- macOS (manual primeiro, antes de automatizar): assinar com **Developer ID
  Application** (`--options runtime`), gerar DMG, `xcrun notarytool submit
  --wait`, `xcrun stapler staple`. Documentar o passo-a-passo num
  `cockpit/packaging/README.md` (vira base do job de CI).
- Linux: validar `.deb` num container Docker `ubuntu:24.04` (instala, ícone e
  entrada de menu presentes, binário abre — pode ser via `xvfb` ou só checar
  que linka: `ldd`). `.rpm` idem em `fedora:40`.
- Declarar dependências runtime nos pacotes Linux (libgtk-3-0/gtk3, etc. —
  extrair de `ldd` do bundle).

**Aceite**: DMG assinado+notarizado abre num Mac sem aviso do Gatekeeper
(testar com `spctl -a -t open --context context:primary-signature` e download
real via navegador). `.deb`/`.rpm` x86_64 instalam e removem limpo nos
containers.

### 3. Workflow `cockpit-release.yml` (raiz `.github/`)

> **Status 2026-06-12**: workflow escrito
> (`.github/workflows/cockpit-release.yml`, YAML validado) no fluxo revisado
> — jobs `meta` (valida tag↔pubspec) → `macos`/`windows`/`linux` (matrix
> amd64+arm64, com smoke test de `.deb` no runner e `.rpm` em `fedora:40`) →
> `publish` (GitHub Release + `SHA256SUMS` + `latest.json` com exatamente 6
> artefatos, `--latest=false` pra não poluir o monorepo).
> **Validado em produção 2026-06-12** (5 iterações até o verde): release
> `cockpit-v1.0.0` criada com 6 artefatos + SHA256SUMS + latest.json.
> Fixes do ciclo: YAML multilinha no `--notes` (block scalar), executável
> do Fastforge é `fastforge:main`, **não há SDK Flutter empacotado pra
> linux-arm64** (job arm64 usa git clone do Flutter), `installed_size`
> obrigatório no deb, smoke do rpm via `rpm -qpl` (nome interno do pacote
> vem do pubspec).

- Trigger: push de tag `cockpit-v*` + `workflow_dispatch`. Primeiro step
  valida que a tag bate com `version:` do `pubspec.yaml` (falha cedo se
  divergir).
- Jobs:
  - `macos` (`macos-latest`): import do certificado (secrets `MACOS_CERT_P12`,
    `MACOS_CERT_PASSWORD`), build, sign, dmg, notarize (App Store Connect API
    key: `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY`), staple.
    **Os 5 secrets Apple já estão cadastrados no repo (2026-06-12)**; Team ID
    de assinatura: `U843T2P7A2`. Com o publish via GitHub Release, **não
    falta nenhum secret** (os `VPS_HOST`/`VPS_DEPLOY_PATH` cadastrados ficam
    sem uso no CI; servem só de documentação do host).
  - `windows` (`windows-latest`): build + Inno Setup → `Setup.exe`.
  - `linux-x64` (`ubuntu-24.04`) e `linux-arm64` (`ubuntu-24.04-arm`):
    deps de sistema, build, `.deb` + `.rpm`.
  - `publish` (needs: todos) — **revisado 2026-06-12 (sem SSH na VPS)**:
    junta artefatos, gera `SHA256SUMS` e o `latest.json` (URLs absolutas
    apontando pros assets da release:
    `https://github.com/jacobaraujo7/remote_pi/releases/download/cockpit-v<versão>/<arquivo>`),
    e cria a **GitHub Release** `cockpit-v<versão>` com os 6 artefatos +
    `SHA256SUMS` + `latest.json` anexados. Usa o `GITHUB_TOKEN` nativo do
    workflow — **nenhum secret extra**. Passo manual pós-CI (gate de
    publicação): baixar o `latest.json` da release e colocar no rp-s3.
- Validar disponibilidade/custo do runner arm64 logo no primeiro run.

**Aceite**: tag de teste (ex: `cockpit-v1.0.0`) produz os 6 artefatos +
checksums + `latest.json` publicados na VPS, com sha256 conferindo após
download público via HTTPS.

### 4. Layout na VPS

> **Status 2026-06-12**: lado servidor pronto — novo subprojeto **`rp-s3/`**
> (Rust/axum + Dockerfile + docker-compose) roda em container na VPS com o
> `VPS_DEPLOY_PATH` (`/Users/flutterando/cockpit/data`, host macOS) montado
> read-only em `/data/cockpit`; serve `/downloads/...` com cache/CORS/
> attachment corretos e `/healthz`. Build release verde + smoke test local OK.
> URL pública: `https://rp-s3.jacobmoura.work` (TLS no proxy da VPS).
> **Revisão 2026-06-12 (sem SSH na VPS)**: o rp-s3 passa a hospedar **só o
> `latest.json`** (e opcionalmente `SHA256SUMS`) — os binários ficam nos
> assets da GitHub Release. O usuário coloca o `latest.json` no volume
> manualmente a cada release (gate de publicação). **Pendência única**:
> subir o container na VPS e apontar o proxy de `rp-s3.jacobmoura.work`.

- A VPS guarda só `/downloads/cockpit/latest.json` (URL estável, nunca muda)
  e opcionalmente `SHA256SUMS`. As URLs **dentro** do manifest apontam pros
  assets da GitHub Release (`releases/download/cockpit-v<versão>/...`).
- Schema do `latest.json` — **contrato entre CI (passo 3) e Site (passo 5)**,
  fechado em 2026-06-12; mudanças exigem atualizar os dois lados:

  ```json
  {
    "version": "1.0.0",
    "date": "2026-06-12",
    "notes": "resumo do changelog",
    "artifacts": [
      { "platform": "macos",   "arch": "universal", "format": "dmg", "url": "…", "sha256": "…", "size": 0 },
      { "platform": "windows", "arch": "x64",       "format": "exe", "url": "…", "sha256": "…", "size": 0 },
      { "platform": "linux",   "arch": "x64",       "format": "deb", "url": "…", "sha256": "…", "size": 0 },
      { "platform": "linux",   "arch": "arm64",     "format": "deb", "url": "…", "sha256": "…", "size": 0 },
      { "platform": "linux",   "arch": "x64",       "format": "rpm", "url": "…", "sha256": "…", "size": 0 },
      { "platform": "linux",   "arch": "arm64",     "format": "rpm", "url": "…", "sha256": "…", "size": 0 }
    ]
  }
  ```
- Servir com HTTPS e `Content-Disposition`/MIME corretos pra download
  (dmg/exe/deb/rpm).
- Histórico de versões fica nas releases do GitHub (nada a reter na VPS) —
  rollback é colocar de volta o `latest.json` da versão anterior (cada
  release tem o seu anexado).

**Aceite**: `curl -fsSL https://<host>/downloads/cockpit/latest.json` retorna
o manifest da última release; cada URL listada baixa o artefato íntegro.

### 5. Página de downloads no Site (site/)

> **Status 2026-06-12**: implementado (`/download`, lint+build verdes) via
> `[ORCH:43-site-downloads]`. Em modo preview (manifest mock + botões
> desabilitados) até a VPS existir — aí basta setar
> `NEXT_PUBLIC_COCKPIT_MANIFEST_URL` (ou usar o default
> `<host do site>/downloads/cockpit/latest.json`). Aceite final depende do
> passo 4.

- Página/seção de download que consome o `latest.json` (client-side ou em
  build com revalidação) e mostra: versão atual, data, botão por
  plataforma/arquitetura, sha256, e instruções curtas por SO — incluindo o
  aviso do SmartScreen no Windows ("Mais informações → Executar assim mesmo")
  e instalação via `dpkg -i`/`dnf install` no Linux.
- Sem screenshots no fluxo de verificação (regra do site): `pnpm lint &&
  pnpm build`.

**Aceite**: build do site passa; página renderiza os 6 artefatos a partir do
manifest real da VPS.

### 6. Runbook de release

- Documentar (em `cockpit/packaging/README.md`): bump de `version:` no
  pubspec → commit → tag `cockpit-vX.Y.Z` → push → CI publica → smoke test
  de download nas 3 plataformas → anúncio.
- Iniciar `cockpit/CHANGELOG.md` (entrada por release; o `notes` do
  `latest.json` pode derivar dele).

**Aceite**: uma release inteira executada só seguindo o runbook, sem passo
improvisado.

### 7. Aviso de atualização in-app (cockpit/)

> **Status 2026-06-12**: implementado via `[ORCH:43-cockpit-update-banner]`
> em camadas (domain/data/ui/config), deps novas `package_info_plus` e
> `url_launcher`. `flutter analyze` zero issues; `flutter test` 55/55 (13
> novos: semver compare + parse do manifest, incluindo schema inválido).
> Card no rodapé do rail, acima do nome da máquina. Verificação visual de
> ponta a ponta acontece junto com a primeira release real (manifest no
> rp-s3 com versão > app).

- No startup, consultar
  `https://rp-s3.jacobmoura.work/downloads/cockpit/latest.json` (GET com
  timeout curto; qualquer falha é silenciosa — sem rede, sem manifest, payload
  inválido → nenhum aviso). Comparar `version` (semver `x.y.z`) com a versão
  do app.
- Se houver versão mais nova: **mini card no shell, acima do nome da máquina
  e do botão de configurações**, informando a atualização, com **botão de
  fechar**. Dispensa persistida **por versão** (fechou a 1.1.0, só reaparece
  quando sair a 1.2.0).
- Clique no card → baixa direto o artefato da plataforma corrente (URL do
  manifest: macOS→dmg, Windows→exe, Linux→deb da arch); fallback se não
  resolver: abrir a página `/download` do site no navegador.

**Aceite**: com um manifest fake servindo versão maior que a do app, o card
aparece; fechar persiste e não volta pra mesma versão; clique abre o
download; com manifest indisponível/igual/menor, nada aparece; `flutter
analyze` zero issues.

## Definition of Done

- [x] Identidade aplicada: bundle ID `work.jacobmoura.cockpit`, nome "Remote Pi Cockpit", CompanyName corrigido, versão Windows dinâmica
- [x] DMG universal assinado + notarizado abre sem aviso do Gatekeeper após download real (validado 2026-06-12: download da URL do manifest, sha256 OK, spctl accepted/Notarized Developer ID, staple válido)
- [ ] `Setup.exe` instala/desinstala em Windows 10/11 x64 (aviso SmartScreen documentado no site)
- [x] `.deb` x86_64 e arm64 instalam em Ubuntu 24.04; `.rpm` x86_64 e arm64 instalam em Fedora (smoke no CI com `.desktop` presente; menu/ícone visual a confirmar em máquina real)
- [x] `cockpit-release.yml` gera os 6 artefatos + `SHA256SUMS` + `latest.json` a partir de tag `cockpit-v*`
- [x] Release `cockpit-v*` no GitHub com 6 artefatos + `SHA256SUMS` + `latest.json`; checksums conferindo após download; `latest.json` no rp-s3 servindo na URL estável (validado 2026-06-12: headers CORS/cache OK, 7 URLs de artefato respondendo, sha256 do DMG conferido)
- [ ] Página de downloads no site consumindo `latest.json` real
- [x] Aviso de atualização in-app: mini card dispensável no shell consultando o `latest.json`, com download por clique
- [ ] Runbook + CHANGELOG iniciados; uma release de ponta a ponta concluída pelo runbook

## Próximos planos (fora de escopo aqui)

- **Nome interno do pacote rpm** — hoje sai como `cockpit` (vem do pubspec),
  que **colide com o pacote `cockpit` do Fedora** (UI de admin de servidor).
  Dar nome próprio (`remote-pi-cockpit`) no make_config do rpm.
- **Recalibrar `installed_size`** do deb (150000 KB é estimativa) com
  `du -sk` do bundle real do CI.
- **Cachear o DMG notarizado entre re-runs** — cada iteração do workflow
  re-notariza (~5 min); cache por sha do commit economizaria nas próximas.
- **Bump actions pra Node 24** (`checkout`/`upload-artifact` avisam
  deprecation do Node 20 a partir de 2026-06-16).

- **Repositórios APT/DNF na VPS** — com `.deb`/`.rpm` já existindo, um repo
  apt/dnf dá updates de graça via `apt upgrade`/`dnf upgrade` (o caminho
  natural de "auto-update" no Linux).
- **Assinatura Windows** — se o aviso do SmartScreen virar atrito real
  (certificado OV ou Azure Trusted Signing).
- **Auto-update in-app** — Sparkle (macOS) / instalador silencioso (Windows),
  só se a descoberta via Site se mostrar insuficiente.
- **Windows arm64** — runner `windows-11-arm` existe; adicionar à matrix se
  houver demanda.
