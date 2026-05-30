# Plano 14 — Onboarding + relay configurável

## Contexto

Pós-estabilização de presence/chat (planos 12-13 + normalização), 3
problemas de UX/produto identificados:

1. **QR code muito grande** — campo `r` (relay URL) ocupa 30-50 chars do
   QR. Densidade alta → scan difícil.
2. **Sem relay configurável** — pi-ext usa `REMOTE_PI_RELAY` env var; app
   usa whatever vier no QR. Sem padronização, sem UI.
3. **Boot manda pra câmera quando sem peer** — `_BootState.load` redireciona
   pra `/pair` automaticamente. UX agressiva.
4. **Sem onboarding** — primeiro uso despeja user direto no scanner sem
   contexto.

Decisão: simplificar QR removendo `r` + adicionar config de relay nos 2
lados + criar onboarding stepper de 3 passos pro primeiro uso.

## Decisões fixadas (2026-05-21)

| Decisão | Valor / razão |
|---|---|
| **Default público hardcoded** | `kDefaultRelayUrl = 'https://relay-rp1.jacobmoura.work'` em ambos lados. Plano 07 (relay deploy) ativa essa URL |
| **Pi-ext config order** | `env REMOTE_PI_RELAY` > `~/.pi/remote/config.json` > `kDefaultRelayUrl` |
| **App config order** | `Preferences.relayUrl` > `kDefaultRelayUrl` |
| **QR sem `r`** | Pi-ext sempre gera QR sem campo `r`. App usa Settings/Preferences |
| **Conflito de QR legacy (com `r`)** | Avisar + perguntar (Q2A): "Pi está em <X>, diferente do seu (<Y>). Trocar?" |
| **Onboarding obrigatório primeira vez** | Sem skip. Marker `Preferences.onboardingCompleted` |
| **Step 2 cards verticais** | Visual, dois cards (comunidade vs custom) |
| **Welcome conservador** | Texto neutro, sem animações elaboradas |
| **Boot sem peer** | Vai pra `/home` (HomeNoPeer state com botão "Scan QR"). Apenas onboarding manda pra câmera |
| **Pi-ext novo comando** | `/remote-pi set-relay <url>` — escreve config persistente + valida URL |
| **Pi-ext `/remote-pi config`** | Mostra valor ativo + source (env / config / default) |
| **Pareamento "1 por Mac, várias sessões"** | Adiado pro plano 15+ (mudança grande de modelo) |

## Estrutura esperada

### Pi-extension

- `src/config.ts` (NOVO): lê/escreve `~/.pi/remote/config.json`
  ```typescript
  type RemotePiConfig = { relay?: string };
  function loadConfig(): RemotePiConfig
  function saveConfig(cfg: Partial<RemotePiConfig>): void
  function resolveRelayUrl(): { url: string; source: 'env' | 'config' | 'default' }
  ```
- `src/index.ts`:
  - `DEFAULT_RELAY_URL` vira `kDefaultRelayUrl = 'https://relay-rp1.jacobmoura.work'` (constante)
  - Resolução de relay usa `resolveRelayUrl()` em `_cmdStart`
  - Novo comando: `/remote-pi set-relay <url>`
    - Valida URL (deve começar com `http://` ou `https://`, hostname não vazio)
    - Chama `saveConfig({ relay: url })`
    - Notifica: "Relay updated: <url>"
  - Novo comando: `/remote-pi config`
    - Mostra: `Relay: <url> (source: env|config|default)`
  - `_cmdPair`: gera QR via `buildQRUri` mas SEM passar `relay` (assinatura nova)
- `src/pairing/qr.ts`:
  - `buildQRUri(token, edPk, sessionName)` — remove parâmetro `relayUrl`
  - URI gerado: `remotepi://pair?t=<>&epk=<>&n=<>` (sem `r`)
  - Tests atualizados pra contar campos
- Tests: 4-5 novos pra config + set-relay + URL validation + QR sem `r`

### App

- `lib/data/preferences/preferences.dart`:
  - Adicionar `String? get relayUrl` e `setRelayUrl(String?)`
  - Adicionar `bool get onboardingCompleted` e `setOnboardingCompleted(bool)`
  - Hidratar ambos em `load()`
- `lib/data/transport/relay_config.dart` (NOVO ou helper):
  - `String resolveRelayUrl(Preferences prefs) => prefs.relayUrl ?? kDefaultRelayUrl;`
  - `bool isValidRelayUrl(String url)` — regex ws/wss + hostname
- `lib/data/transport/ws_transport.dart`:
  - `connect()` agora recebe relay URL como parâmetro (ou ConnectionManager passa)
  - Fallback removido se URL vinha do peer.relayUrl — agora vem do app
- `lib/data/transport/connection_manager.dart`:
  - Construtor recebe `Preferences prefs` (ou getter de relay URL)
  - `_connect(peer)` usa `resolveRelayUrl(prefs)` em vez de `peer.relayUrl`
  - Legacy: peer com `relayUrl != null && relayUrl != current` triggers conflito (ver pairing flow)
- `lib/pairing/qr_scanner.dart`:
  - `QrPairPayload` torna `relayUrl` opcional (`String?`)
  - Parsing aceita QR sem `r` (campo opcional)
- `lib/pairing/pair_request_flow.dart`:
  - Usa `resolveRelayUrl(prefs)` se `qr.relayUrl == null`
  - Se `qr.relayUrl != null && qr.relayUrl != prefs.relayUrl`: throw `PairingError(code: 'relay_mismatch', ...)` com info pra UI decidir
- `lib/ui/onboarding/` (NOVO feature):
  ```
  lib/ui/onboarding/
  ├── onboarding_page.dart           # PageView controller + indicator + nav
  ├── states/
  │   └── onboarding_state.dart      # OnboardingStep enum + selected relay
  ├── viewmodels/
  │   └── onboarding_viewmodel.dart  # current step, selectRelay(community|custom), setCustomRelayUrl, scan QR, complete
  └── widgets/
      ├── widgets.dart
      ├── welcome_step.dart          # logo + título + descrição + botão "Começar"
      ├── relay_step.dart            # 2 cards verticais (community/custom)
      └── pair_step.dart             # QR scanner + texto explicativo
  ```
- `lib/ui/settings/`:
  - `SettingsPage` ganha seção "Relay" no topo
  - TextField + placeholder "Default Relay (https://relay-rp1.jacobmoura.work)"
  - Botão "Salvar" → valida URL → `prefs.setRelayUrl(url)`. Vazio = volta pro default
- `lib/ui/home/`:
  - `HomeNoPeer` ganha botão "Scan QR" mais visível → navega pra `/pair` (não `/onboarding`)
- `lib/routing/app_router.dart`:
  - `_BootState.load` lógica nova:
    ```dart
    final hasPeer = peers.isNotEmpty;
    final onboarded = prefs.onboardingCompleted;
    _ready = true;
    _redirectTo = hasPeer ? '/home'
        : onboarded ? '/home'  // mostra HomeNoPeer
        : '/onboarding';
    notifyListeners();
    if (hasPeer) conn.boot(preferredEpk: selected);
    ```
  - Rota nova `/onboarding` com `ViewmodelProvider<OnboardingViewModel>()`
  - Boot redirect já não vai mais pra `/pair` automático
- `lib/main.dart`:
  - `Preferences.load()` antes de buildRouter

### Relay

- **Zero mudança.**

### Contracts

- `.orchestration/contracts/pairing.md`:
  - Remover `r` (relay URL) do QR payload
  - Documentar: "Relay URL é configurado no app/pi-ext via Settings/config — não trafega no QR"
  - Adicionar nota sobre legacy QR com `r` (compatibilidade — app pode aceitar mas avisa conflito)

## Passos com critério de aceite

### Wave 0 — Contratos (orquestrador-only)
- [ ] Atualizar `.orchestration/contracts/pairing.md` — QR sem `r`, doc do legacy
- [ ] Adicionar `kDefaultRelayUrl` no contrato (constante compartilhada conceitualmente)

### Wave 1 — Subprojetos em paralelo

#### W1.A — pi-extension
- [ ] `src/config.ts` (NOVO): load/save/resolve config
- [ ] `kDefaultRelayUrl = 'https://relay-rp1.jacobmoura.work'` constante
- [ ] `/remote-pi set-relay <url>` com validação
- [ ] `/remote-pi config` mostra source
- [ ] `_cmdStart` usa `resolveRelayUrl()`
- [ ] `buildQRUri` perde param `relayUrl`, QR gerado sem `r`
- [ ] Testes: config persiste, set-relay valida URL, QR sem `r`, resolve por ordem
- [ ] `pnpm typecheck && pnpm build && pnpm test` verde

#### W1.B — app
- [ ] `Preferences.relayUrl` + `onboardingCompleted`
- [ ] `kDefaultRelayUrl` constante (mesmo valor que pi-ext)
- [ ] `resolveRelayUrl(prefs)` helper
- [ ] `isValidRelayUrl(url)` validator
- [ ] `QrPairPayload` aceita QR com ou sem `r` (legacy)
- [ ] `pair_request_flow.performPairing`: detecta `relay_mismatch` quando QR tem `r` ≠ prefs
- [ ] `ConnectionManager` usa relay do prefs (não do peer)
- [ ] `lib/ui/onboarding/` feature completa (3 steps + PageView + indicator)
- [ ] `SettingsPage`: seção Relay editável
- [ ] `HomeNoPeer`: botão "Scan QR" → `/pair`
- [ ] `app_router.dart`: redirect novo (`/home` empty state, não `/pair`)
- [ ] `main.dart`: `prefs.load()` antes de buildRouter
- [ ] Tests: onboarding stepper, relay validation, redirect logic, settings save
- [ ] `flutter analyze && flutter test` verde

#### W1.C — relay
- [ ] **Sem mudança.** Confirma smoke test (cargo test).

### Wave 2 — Roundtrip manual

#### Cenário 1 — Onboarding completo (app fresh install)
- [ ] App primeira abertura → vai pra `/onboarding/welcome`
- [ ] Tap "Começar" → step 2
- [ ] Card "Relay da comunidade" pré-selecionado → "Continuar"
- [ ] Step 3 (QR scanner ativo)
- [ ] Escanear QR do Pi → naviga pra `/home` com peer pareado
- [ ] `prefs.onboardingCompleted == true`

#### Cenário 2 — Onboarding com relay custom
- [ ] Fresh install, step 2: tap card "Meu servidor"
- [ ] TextField aparece → digita "http://192.168.1.50:3000" → "Continuar"
- [ ] Step 3: scaneia QR → /home

#### Cenário 3 — Boot com peer revogado (onboarded antes)
- [ ] App com `onboardingCompleted=true` mas zero peers
- [ ] Abre app → vai pra `/home` com `HomeNoPeer` state (NÃO onboarding de novo)
- [ ] Botão "Scan QR" → `/pair`

#### Cenário 4 — Pi-ext config
- [ ] `pi -e ...` → `/remote-pi config` mostra default
- [ ] `/remote-pi set-relay https://meu.relay.com` → salva
- [ ] `/remote-pi config` mostra "Relay: https://meu.relay.com (source: config)"
- [ ] Reiniciar Pi → `set-relay` persistiu

#### Cenário 5 — QR sem `r` end-to-end
- [ ] Pi config diferente do app:
  - Pi: `https://relay-a.com`
  - App prefs: `https://relay-b.com`
- [ ] `/remote-pi pair` → QR gerado SEM `r`
- [ ] App escaneia → usa relay-b (do prefs)
- [ ] Mas Pi está em relay-a → pareamento falha (timeout)
- [ ] **Esperado**: app mostra erro claro "Pi não respondeu — verifique se está no mesmo relay"

#### Cenário 6 — QR legacy com `r` divergente
- [ ] QR antigo (testar via build script) com `r=https://relay-a.com`
- [ ] App prefs: `https://relay-b.com`
- [ ] App escaneia → detecta conflito → modal "Pi está em <a>, diferente do seu (<b>). Trocar?"
- [ ] Tap "Trocar" → atualiza prefs.relayUrl → pareia com relay-a

#### Cenário 7 — Boot sem peer + sem onboarding feito (legacy install)
- [ ] User antigo (já usou app antes do plano 14) → tem peer mas não tem `onboardingCompleted`
- [ ] App lê `peers.isNotEmpty` → vai pra `/home` normal (skipa onboarding)
- [ ] `onboardingCompleted` setado em background pra true (migração silenciosa)

### Wave 3 — Polish
- [ ] Atualizar `00-decisions.md`: registrar default relay público, config persistente, onboarding obrigatório
- [ ] Atualizar `README.md` raiz: mencionar configuração de relay
- [ ] Commit consolidado

---

## Definition of Done

- [x] Wave 0: contratos atualizados (pairing.md sem `r`)
- [x] W1.A: pi-ext config + set-relay + QR sem `r` + tests (101 tests, +6)
- [x] W1.B: app prefs + onboarding 3 steps + settings + redirect novo + tests (175 tests, +26)
- [x] W1.C: relay sem mudança (smoke verde — sem alteração)
- [ ] Wave 2: 7 cenários manuais OK
- [ ] Wave 3: docs + commit

---

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Default `https://relay-rp1.jacobmoura.work` não existe ainda (plano 07 deploy) | Pra dev, user sempre sobrepõe via env ou Settings. Constante documenta intent; commit do plano 07 ativa URL real |
| User configura relay errado e fica preso sem conseguir parear | Settings sempre editável; reset pra default = TextField vazio |
| Onboarding step 2 com URL inválida confunde user | Validação inline com mensagem clara ("URL deve começar com http:// ou https://") |
| Migração de install legacy (sem onboardingCompleted) abre onboarding em quem já usava | Marker silencioso: `if peers.isNotEmpty && !onboardingCompleted → setOnboardingCompleted(true)` no boot |
| QR antigo (com `r`) gera conflito desnecessário | Modal explica + 1 tap pra resolver. Sem regressão |
| Pareamento perde info de "qual cwd" — `n` ainda no QR mas legacy peers podem perder | `n` mantido no QR (não foi removido). Só `r` saiu |

---

## Próximos planos

- **Plano 07** — relay deploy. **Lembrete da memory `project-relay-throttle-env-future`**: incluir vars de env pra throttle/jitter/rate-limit antes de produção
- **Plano 15** — pareamento "1 por Mac, várias sessões" (mudança grande de modelo): pi-ext anuncia `session_announced` ao subir nova sessão; app mantém lista de sessões agrupadas por peer
- **Plano 16+** — features pós-MVP (push notifications, etc)
