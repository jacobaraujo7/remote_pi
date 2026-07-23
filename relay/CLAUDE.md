# Remote Pi — Relay (Rust)

Servidor WebSocket que autentica conexões por `peer_id`, roteia tráfego App↔Pi,
autoriza e encaminha envelopes Pi→Pi e mantém metadados de membership assinados
pelo Owner em SQLite.

## Stack

- Rust 1.94+ (edição 2024)
- Runtime: `tokio` (full features)
- WebSocket: `tokio-tungstenite`
- Serialização: `serde` + `serde_json`
- Logging: `tracing` + `tracing-subscriber` (NÃO usar `println!`)

## Comandos

- `cargo build` — build dev
- `cargo build --release` — build otimizado
- `cargo run` — roda local
- `RUST_LOG=info cargo run` — com logs visíveis
- `cargo clippy -- -D warnings` — lint estrito (deve passar antes de commit)
- `cargo fmt` — formata
- `cargo test` — testes

## Convenções

- **Erros**: `anyhow::Result<()>` no `main`, `thiserror::Error` em libs internas
- **Async**: tudo via `tokio::spawn` / `tokio::select!`, nada de `std::thread`
- **Logging**: spans com `tracing::info_span!` em handlers, `info!`/`warn!`/`error!`
- **Sem `unwrap()`** em código de produção. Use `?` e propague
- **Sem `clone()` desnecessário** — passe `&` quando possível

## Política de segurança e conteúdo

- No tráfego App↔Pi, o `ct` externo permanece opaco e nunca é decodificado.
- `pi_envelope` Pi→Pi e membership assinado são parseados em memória somente
  conforme necessário para routing e autorização.
- Nenhum body de envelope, material de chave ou assinatura pode ser logado ou
  persistido como payload de mensagem.
- A persistência SQLite é limitada a metadados de autorização de membership
  assinados pelo Owner; tráfego de mensagens nunca é persistido.
- Uma rota é elegível quando qualquer blob Owner corretamente assinado lista
  diretamente as duas chaves Pi canônicas. Isso não prova que o Owner pareou ou
  controla qualquer Pi, nem oferece uma garantia de confiança mais forte. Não
  há transitividade entre blobs sobrepostos.
- O cache positivo de autorização pode reter uma permissão revogada por no
  máximo 60 segundos; misses negativos de remetente são cacheados por 1 segundo
  e o cache é limitado.
- Rate limit por `peer_id` e por IP de origem.

## Upgrade

- Implante primeiro o Relay 0.3: Extensions antigas consomem seus erros UUID.
  Depois coordene a Extension 0.6 e minimize Extensions mistas, pois labels de
  wire mistos continuam adiados. O shim da 0.6 cobre Relay antigo ou rollback,
  não é a razão de Relay-first ser seguro.
- Os procedimentos de rollout ficam centralizados no
  [Plano 51](../plan/51-cross-pc-mesh-routing-hardening.md).

## NÃO fazer

- Não usar `println!` (use `tracing`)
- Não usar `.unwrap()` ou `.expect()` em paths de produção
- Não logar conteúdo de mensagens, chaves completas ou assinaturas
- Não adicionar persistência de tráfego/payload; apenas metadata de membership
  assinada pelo Owner pertence ao SQLite
- Não comitar `target/` (já no .gitignore raiz)

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
