# Remote Pi — Pi Extension (Node + TypeScript)

Extensão para o [Pi coding agent](https://github.com/earendil-works/pi) que
adiciona o slash command `/remote-pi`. Embarca o SDK do Pi
(`@mariozechner/pi-coding-agent`) e expõe via WebSocket pro relay.

Faz parte da **mesh de agentes coding cross-PC** do Remote Pi: cada PC
roda esta extensão (Node daemon) com uma Pi-key Ed25519 no keyring do
sistema; o celular é autenticador inicial via QR; entre PCs irmãos do
mesmo Owner, broker UDS local + relay forward Pi-to-Pi via WS roteiam
envelopes com prefixo `<pc>:<peer>`.

Protocolo, identidades, ACK, roteamento cross-PC e trust model: ver
[`../PROTOCOL.md`](../PROTOCOL.md) (doc canônica do repo).

## Stack

- Node 20+ / TypeScript 6
- **Module system**: ESM only (NodeNext). Imports com extensão `.js` mesmo em `.ts`
- Package manager: **pnpm** (não usar npm/yarn)
- Crypto: libsodium-wrappers (Curve25519 + ChaCha20-Poly1305)
- Pi-secret storage: `@napi-rs/keyring` (Keychain macOS / libsecret Linux desktop / Credential Manager Windows). Headless Linux sem D-Bus cai pra `~/.pi/remote/identity.json` (`chmod 0600`) com warning — instale GNOME Keyring/KWallet pra hardening real.

## Comandos

- `pnpm install` — instala deps
- `pnpm typecheck` — `tsc --noEmit`, deve passar zero erros
- `pnpm build` — `tsc`, gera `dist/`
- `pnpm dev` — `tsx src/index.ts`, executa direto sem build

## Configuração do relay

Ordem de resolução (precedência):

1. `process.env.REMOTE_PI_RELAY` — escape hatch pra CI/ops
2. `~/.pi/remote/config.json` (`{ "relay": "..." }`) — persistido via
   `/remote-pi set-relay <url>`
3. `kDefaultRelayUrl` (`https://relay-rp1.jacobmoura.work`) — produção

Slash commands:

- `/remote-pi set-relay <http://… | https://…>` — grava URL em
  `~/.pi/remote/config.json`. Validação rejeita `ws://`, `wss://`,
  string vazia e URLs malformadas (a extensão converte http(s)→ws(s)
  internamente ao abrir o WebSocket).
- `/remote-pi config` — mostra a URL efetiva atual + de qual fonte vem
  (`env`/`config`/`default`).

`_cmdStart` chama `resolveRelayUrl()` e exibe o `source` no notify
("Connecting to relay <url> (source: …)") pra QA validar.

## Dependências importantes

- `@mariozechner/pi-coding-agent` — SDK do Pi (`AgentSession`, `SessionManager`, `ModelRegistry`)
- `ws` — WebSocket client

## Convenções

- **Strict TS**: `"strict": true`, sem `any` exceto onde inevitável (use `unknown` + narrow)
- **Imports**: `import { foo } from "./bar.js"` (extensão obrigatória em ESM)
- **Top-level await** ok (ESM permite)
- **Erros**: `class XxxError extends Error` para classes nomeadas, throw cedo no boundary
- **Logging**: `console.log` ok no MVP; depois migrar pra `pino` ou similar

## NÃO fazer

- Não escrever CommonJS (`require`, `module.exports`)
- Não comitar `dist/` (já no .gitignore raiz)
- Não criptografar/descriptografar de forma custom — usar libsodium
- Não introduzir dependência que não seja ESM-friendly

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
