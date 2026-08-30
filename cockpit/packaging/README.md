# Empacotamento & Release — Cockpit

Runbook de build/empacotamento das 3 plataformas. Base pro job de CI
(`.github/workflows/cockpit-release.yml`, plano 43 passo 3). Plano de
referência: [`../../plan/43-cockpit-packaging.md`](../../plan/43-cockpit-packaging.md).

## Identidade (passo 1 — feito)

| Item | Valor |
|---|---|
| App ID (macOS bundle id / Linux app id) | `work.jacobmoura.cockpit` |
| Nome de exibição | **Remote Pi Cockpit** |
| Binário | `cockpit` (Linux/Windows) / `Cockpit` (macOS) — **não** renomeado |
| Team ID (Apple) | `U843T2P7A2` |
| Versão (SSOT) | `version:` do `pubspec.yaml` (`x.y.z+n`) |

- macOS: `PRODUCT_BUNDLE_IDENTIFIER` em `macos/Runner/Configs/AppInfo.xcconfig`;
  `CFBundleDisplayName` em `Info.plist`; **Hardened Runtime** ligado no Release
  (`ENABLE_HARDENED_RUNTIME = YES`, exigência da notarização) com
  `Release.entitlements` (sandbox off — compatível com Developer ID).
- Windows: `CompanyName`/`ProductName`/`LegalCopyright` em
  `windows/runner/Runner.rc`; versão vem dos defines `FLUTTER_VERSION_*`
  (injetados em build; o `#else "1.0.0"` é só fallback).
- Linux: `.desktop` + ícones hicolor + `work.jacobmoura.cockpit.metainfo.xml`
  (AppStream), instalados via `linux/CMakeLists.txt`.

## Ferramenta

[Fastforge](https://pub.dev/packages/fastforge) (sucessor do `flutter_distributor`,
descontinuado):

```bash
dart pub global activate fastforge
```

Config: `distribute_options.yaml` (raiz do cockpit) + um `make_config.yaml` por
formato. **Atenção à convenção de path do Fastforge**: os configs ficam em
`<plataforma>/packaging/<formato>/make_config.yaml` (hardcoded no loader), **não**
em `packaging/<plataforma>/...` como o diagrama do plano sugeria:

```
macos/packaging/dmg/make_config.yaml
windows/packaging/exe/make_config.yaml
linux/packaging/deb/make_config.yaml
linux/packaging/rpm/make_config.yaml
```

## macOS — build + sign + DMG + notarize + staple (ponta a ponta)

Validado localmente em 2026-06-12 (DMG aceito pelo Gatekeeper). Pré-requisitos:
identidade **"Developer ID Application: Jacob Moura (U843T2P7A2)"** no Keychain e
a API key do App Store Connect.

```bash
cd cockpit

# 1. Build universal (x86_64 + arm64 — default do Flutter macOS release).
flutter build macos --release
APP="build/macos/Build/Products/Release/Cockpit.app"

# 2. Assina o .app com Developer ID + Hardened Runtime + entitlements de Release.
codesign --force --deep --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "Developer ID Application: Jacob Moura (U843T2P7A2)" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"   # checagem

# 3. Monta o DMG (hdiutil — sem dependências; o maker do Fastforge usa `appdmg`
#    via npm, alternativa pra CI). Layout: app + atalho /Applications.
mkdir -p dist
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="dist/RemotePiCockpit-1.0.0-macos-universal.dmg"
hdiutil create -volname "Remote Pi Cockpit" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# 4. Assina o DMG.
codesign --force --timestamp \
  --sign "Developer ID Application: Jacob Moura (U843T2P7A2)" "$DMG"

# 5. Notariza (App Store Connect API key) e aguarda.
xcrun notarytool submit "$DMG" \
  --key "/Users/jacob/Library/Mobile Documents/com~apple~CloudDocs/Flutterando/RemotePi/CockpitApp/AuthKey_3Y2J8MA3M4.p8" \
  --key-id 3Y2J8MA3M4 \
  --issuer a76c76e6-a413-449e-926c-f2c30d5645c4 \
  --wait

# 6. Grampeia o ticket e valida.
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"   # → "accepted / Notarized Developer ID"
```

> **CI**: os 5 secrets Apple já estão no repo (`MACOS_CERT_P12`,
> `MACOS_CERT_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY`).
> No runner, importar o `.p12` num keychain temporário e escrever a `.p8` num
> arquivo antes de rodar os passos acima.

## Windows — Inno Setup (`.exe`)

**Não buildável no Mac.** Job `windows` do CI (`windows-latest`):

```bash
flutter build windows --release
fastforge package --platform windows --targets exe   # usa windows/packaging/exe/make_config.yaml
```

Sem assinatura nesta fase (aviso do SmartScreen documentado no site). Artefato:
`RemotePiCockpit-Setup-<v>-windows-x64.exe`.

## Linux — `.deb` + `.rpm` (x86_64 e arm64)

**Não buildável no Mac.** Jobs `linux-x64` (`ubuntu-24.04`) e `linux-arm64`
(`ubuntu-24.04-arm`) do CI:

```bash
sudo apt-get install -y rpm   # rpmbuild, pra gerar .rpm em runner Ubuntu
flutter build linux --release
fastforge package --platform linux --targets deb
fastforge package --platform linux --targets rpm
```

### Buildando numa máquina Linux de verdade (não o runner)

O runner do GitHub já traz os `-dev` que os plugins nativos exigem no CMake; uma
estação limpa não. Sem eles o `flutter build linux` morre no **configure**, uma
dependência por vez:

```bash
sudo apt-get install -y libsecret-1-dev libasound2-dev libmpv-dev libjsoncpp-dev
```

| pacote | quem exige |
|---|---|
| `libsecret-1-dev` | `flutter_secure_storage_linux` |
| `libasound2-dev` (ALSA) | `volume_controller` |
| `libmpv-dev` | `media_kit_video` |
| `libjsoncpp-dev` | bundle Flutter Linux |

São deps de **build**, não de runtime — as de runtime estão no
`linux/packaging/deb/make_config.yaml`. Para conferir a lista depois de mexer em
plugins: `grep -rh "pkg_check_modules\|find_package" linux/flutter/ephemeral/.plugin_symlinks/*/linux/CMakeLists.txt`.

**Armadilha do CMake:** um configure que aborta deixa `CMAKE_INSTALL_PREFIX` em
`/usr/local` no `CMakeCache.txt`, e o `linux/CMakeLists.txt` só o aponta pro
bundle quando o prefixo ainda está no default inicial. A partir daí todo build
falha em `file INSTALL cannot copy ... to /usr/local/cockpit: Permission
denied`, mesmo com as libs já instaladas. Conserto:

```bash
rm -f build/linux/x64/release/CMakeCache.txt
rm -rf build/linux/x64/release/CMakeFiles
```

O `fastforge` (`dart pub global activate fastforge`) sai em
`dist/<versão>/cockpit-<versão>-linux.deb`; instalar com `sudo dpkg -i`, **com o
app fechado** — senão os binários trocam embaixo do processo vivo.

Deps de runtime declaradas nos `make_config.yaml` (GTK3 + libs base). **Pendência
de CI** (passo 3): rodar `ldd` no bundle gerado pra confirmar/expandir as deps, e
validar instalação em containers `ubuntu:24.04` (deb) e `fedora:40` (rpm) — não
foi possível neste Mac (sem build Linux; Docker presente mas parado).

## Self-update (plano 47 — Sparkle/WinSparkle)

macOS e Windows se auto-atualizam via o pacote `auto_updater` (Sparkle/WinSparkle);
Linux segue no notify+download manual. O app lê um **appcast** (a URL é cravada
em runtime via `setFeedURL`) e baixa o artefato de update assinado **EdDSA**.

### Artefatos de update (≠ instalador de primeira vez)

| Plataforma | Primeira instalação | Update (appcast) |
|---|---|---|
| macOS | `.dmg` notarizado | **`Cockpit-<v>-macos.zip`** = `ditto` do `.app` notarizado+**stapled** |
| Windows | `.exe` Inno | o **mesmo `.exe`** rodado silencioso (`sparkle:installerArguments`) |
| Linux | `.deb`/`.rpm` | — |

### Chave EdDSA (uma só pros dois)

Sparkle e WinSparkle usam **ed25519**, que é determinístico — a mesma chave serve
aos dois (verificado: `sign_update` do Sparkle e PyNaCl geram assinatura idêntica).
Por isso há **um par** de chaves, não dois.

- **Pública** (commitada): `WoJTWryr48pWiAnDPqqt/Iu9f6gAsU7A1zBb5mBLruI=`
  - macOS: `SUPublicEDKey` em `macos/Runner/Info.plist`.
  - Windows: recurso `EdDSAPub EDDSA {...}` em `windows/runner/Runner.rc`.
- **Privada** (NUNCA commitar): backup em
  `…/CloudDocs/Flutterando/RemotePi/CockpitApp/sparkle_ed25519_private_key.txt`
  (iCloud, junto dos certs Apple) **e** no secret do GitHub `SPARKLE_PRIVATE_KEY`.
  Gerada via Sparkle na conta de keychain `remote-pi-cockpit`.

Regenerar / rotacionar (⚠️ trocar a chave **trava a base instalada**: os apps
antigos só confiam na pública embutida neles — só faça se a privada vazar, e
saiba que os usuários atuais terão que reinstalar manualmente):

```bash
cd cockpit
# (re)gera; imprime a SUPublicEDKey; privada vai pro Keychain (conta dedicada)
./macos/Pods/Sparkle/bin/generate_keys --account remote-pi-cockpit
# exporta a privada pro iCloud (pede "Allow" no Keychain)
./macos/Pods/Sparkle/bin/generate_keys --account remote-pi-cockpit -x \
  "/Users/jacob/Library/Mobile Documents/com~apple~CloudDocs/Flutterando/RemotePi/CockpitApp/sparkle_ed25519_private_key.txt"
# atualizar: SUPublicEDKey (Info.plist), EdDSAPub (Runner.rc) e o secret SPARKLE_PRIVATE_KEY
```

### Assinatura + appcasts (no CI, job `publish`)

Tudo num lugar só, em ubuntu, com **uma** chave e **sem** ferramenta nativa: o
job assina `Cockpit-<v>-macos.zip` e o `.exe` com PyNaCl (a `SPARKLE_PRIVATE_KEY`)
e gera `appcast-macos.xml` + `appcast-windows.xml`. macOS usa
`sparkle:version` = **build number** (`+n`); Windows usa a versão marketing.

### Publicação (gate manual)

Junto do `latest.json`, suba `appcast-macos.xml` e `appcast-windows.xml` pro rp-s3
(`/Users/flutterando/cockpit/data/`). Até subir, ninguém se auto-atualiza. As feed
URLs são `https://rp-s3.jacobmoura.work/downloads/cockpit/appcast-{macos,windows}.xml`.

### Pendências (não testáveis neste Mac)

- Adicionar o secret `SPARKLE_PRIVATE_KEY` no repo (conteúdo do arquivo do iCloud).
- Validar no **Windows real**: recurso `EdDSAPub`, install silencioso sem UAC,
  relaunch (Restart Manager) sem duplo-launch.
- Validar o **codesign do Sparkle** na notarização (framework + Autoupdate +
  Updater.app + XPCServices — confirmados presentes no bundle; `--deep` deve cobrir).
- E2E real: subir um appcast apontando pra v(N+1) e ver um cockpit v(N) se atualizar.

## Próximos passos (plano 43)

- Passo 3: `.github/workflows/cockpit-release.yml` (trigger `cockpit-v*`). **Feito**
  (+ self-update do plano 47: `.app.zip` + appcasts assinados).
- Passo 4: layout/`latest.json` na VPS.
- Passo 5: página de downloads no `site/`.
- Passo 6: runbook de release (bump `version:` → tag → CI → smoke test).
