# Plano 51 — Roteamento mesh cross-PC canônico

**Status:** correções do review upstream validadas e aprovadas; rollout, publicação e deployment permanecem fora de escopo
**Subprojetos:** `pi-extension/` e `relay/`

## Contexto

O roteamento cross-PC usava nickname/prefixo como se fosse identidade técnica.
Isso tornava a visão assimétrica entre máquinas: cada receptor podia conhecer um
nickname diferente para a mesma Pi-key, causando destinos não roteáveis, spoofing
de apresentação e timeouts sem diagnóstico confiável.

A correção separa duas coisas:

- **identidade técnica:** chave pública Ed25519 canônica de 32 bytes;
- **apresentação:** alias local calculado pelo receptor.

O Relay continua mediando o tráfego; não há P2P direto nem E2E. TLS protege o
trânsito, mas o operador do Relay pode observar o conteúdo atual.

## Escopo

- Canonicalizar identidade Pi/PC no Relay e na Extension.
- Permitir a rota somente quando um blob corretamente assinado por um Owner
  listar diretamente as duas Pi-keys; isso não prova que o Owner pareou ou
  controla qualquer uma delas.
- Gerar aliases locais determinísticos e não ambíguos.
- Impedir que registro local forjado sombreie alias remoto conhecido, preservando
  endereços Windows absolutos exatamente registrados como locais.
- Entregar erros confiáveis do Relay sem alterar os status públicos.
- Tornar leitura de topologia, SelfRevoke e deadlines fail-closed.
- Fazer rollout Relay `0.3` primeiro e Extension `0.6` depois.
- Manter por uma release o label wire legado aceito pelo upstream para reduzir a
  janela mixed-version sem transformar label em identidade.

## Fora de escopo

- Alterações no app Android/iOS, Cockpit ou Site.
- Mudança de pareamento, short IDs, room IDs ou formato de `peers.json`.
- Migração ou mudança de schema do SQLite do Relay.
- Floor anti-rollback persistente entre reinícios ou coordenação SelfRevoke
  persistente entre processos; acompanhado em
  [#73](https://github.com/jacobaraujo7/remote_pi/issues/73).
- Negociação de capabilities ou compatibilidade de labels além do shim limitado
  de uma release aceito para este PR.
- E2E encryption ou transporte P2P.
- Publicação de imagem/pacote ou deployment automático.

## Estrutura esperada

### Relay

- Um decoder compartilhado aceita somente chave Ed25519 de 32 bytes e produz
  Base64 RFC 4648 padrão com padding.
- O `pi_forward` usa a chave autenticada da conexão como `from_pc` e uma chave
  canônica como `to_pc`.
- A checagem de autorização considera a rota elegível quando um único blob
  corretamente assinado lista diretamente origem e destino; isso não é prova de
  pareamento ou controle pelo Owner.
- Um membro malformado invalida a contribuição inteira daquele Owner.
- Cache por remetente é limitado a 1.024 entradas, compartilha conjuntos
  positivos, mantém single-flight e recupera locks envenenados sem panic.
- Grants positivos expiram em até 60 segundos e misses negativos em 1 segundo.
- Leituras SQLite completas saem do runtime assíncrono via `spawn_blocking`.
- Erros reservados usam apenas `offline`, `not_authorized` ou `bad_envelope`.

### Extension

- Pi-key e Owner-key são normalizadas somente depois das verificações
  criptográficas necessárias.
- A topologia contém apenas irmãos de Owners válidos que incluem a Pi local.
- Aliases são calculados localmente pelo receptor e nunca usados como prova de
  identidade ou autorização.
- O broker oferece alias remoto conhecido antes do fallback local; endereço
  absoluto Windows exatamente registrado continua local mesmo com `:` de drive.
- Registro exige `cwd` vazio legado ou path absoluto POSIX/Windows/UNC limitado e
  sem NUL, CR ou LF.
- Frames recebidos usam `from_pc` autenticado e renderizam `envelope.from` com o
  alias local do receptor.
- Apenas erros `_relay` com outer e grammar exatos liquidam operações pendentes.
- Erros forjados continuam conteúdo comum e não ganham autoridade.
- Leituras de topologia têm deadline finito e distinguem ausência autoritativa,
  dado inválido e indisponibilidade.
- SelfRevoke remove o registro bruto correto e desanexa o canal canônico ativo;
  seu floor anti-rollback atual vale apenas durante a vida da instância.

## Contrato final

### Identidade canônica

A identidade é Base64 padrão com padding dos 32 bytes crus da chave Ed25519.
Entradas URL-safe ou sem padding podem ser aceitas para normalização, mas toda
comparação e saída técnica usa a forma canônica.

Nicknames, aliases e prefixes nunca substituem a chave técnica.

### Aliases locais

- Bytes UTF-8 fora de `[A-Za-z0-9._-]` são codificados como `%HH` maiúsculo.
- `~<prefixo-base64url-da-chave>` resolve colisões.
- O prefixo cresce de forma adaptativa até ficar único.
- Ausência de nickname usa `pc-<prefixo-da-chave>`.
- Cada receptor pode renderizar aliases diferentes para a mesma chave.

### Autorização

A implementação permite `A → B` somente quando encontra um blob corretamente
assinado por um Owner que lista A e B diretamente. Isso verifica assinatura e
conteúdo, mas não prova que o Owner pareou ou controla qualquer Pi. Blobs `{A,B}`
e `{B,C}` não autorizam `A → C`. Uma contribuição com qualquer membro inválido
não concede autorização.

### Cache

- TTL positivo máximo: 60 segundos.
- Miss negativo por remetente: 1 segundo para coalescer bursts sem revarrer toda
  a tabela a cada alvo inexistente.
- Máximo de 1.024 remetentes, com prune por expiração e eviction do mais antigo.
- Falhas e storage indisponível nunca viram grant positivo cacheado.

### Endereçamento

O endereço público é `[<alias-local>:]<cwd>@<agent>`. Chamadores devem copiar o
valor completo de `list_peers` sem parsear, reconstruir, decodificar ou alterar
case. Alias remoto conhecido vence registro local forjado; endereço absoluto
Windows exatamente registrado permanece local.

### Erros e ACK

Status públicos permanecem:

- `received` para entrega aceita;
- `denied` para `not_authorized` ou `bad_envelope` confiável;
- `timeout` para `offline` confiável ou silêncio real;
- `sent` para broadcast sem ACK.

Apenas um outer autenticado de `_relay`, com envelope reservado válido, reason
fechado e UUID correlacionável, pode liquidar pending state. O sender do ACK deve
corresponder ao destino registrado e settlement ocorre no máximo uma vez. Somente
nesse caminho confiável, a Extension nova normaliza o ID legado lowercase de 32
hex do Relay antigo; envelopes comuns continuam exigindo UUID estrito.

### Topologia e SelfRevoke

- Leitura estrita bem-sucedida é a única evidência autoritativa.
- Storage indisponível nunca significa conjunto vazio.
- Ausência autoritativa remove confiança; dados inválidos são isolados.
- Reconciliação de Owners ativos desanexa canais privados revogados.
- Uma re-pair concorrente válida não pode ser apagada por remoção obsoleta.
- O floor anti-rollback em memória reinicia com o processo; `issued_at` é
  informativo e membership não expira. Assim, membership anterior à revogação
  pode ser repetida após restart. Persistência segura fica fora deste plano e é
  acompanhada em [#73](https://github.com/jacobaraujo7/remote_pi/issues/73).

## Passos e critérios de aceite

### 1. Relay canônico

- Validar hello, membership e forwarding na mesma fronteira de 32 bytes.
- Cobrir Base64 padrão/URL-safe, padding, comprimento e caracteres inválidos.
- Provar autorização direta, não transitiva e independente da ordem dos Owners.
- Provar invalidade completa da contribuição com membro malformado.
- Provar TTL, refresh em miss e grammar exata de erros.

**Aceite:** testes unitários e integração do Relay passam; fmt, clippy e release
build passam; nenhum payload, chave ou assinatura é logado.

### 2. Extension canônica

- Implementar aliases determinísticos e bijetivos por chave.
- Dar precedência a alias remoto conhecido sem quebrar endereço local absoluto
  Windows exatamente registrado.
- Normalizar inbound pelo `from_pc` autenticado.
- Implementar deadline finito e classificação estrita de leitura.
- Preservar status públicos e settlement confiável de erros.

**Aceite:** testes de encoding, topology, broker remoto, envelope, tools, MCP e
round trip passam sem alterar pareamento, room ID ou storage schema.

### 3. Revogação e reconciliação

- Remover o registro bruto correspondente sem normalizar o arquivo inteiro.
- Desanexar o canal pela identidade canônica.
- Reconciliar Owners ativos somente após snapshot estrito autoritativo.
- Preservar estado em outage/invalidade não autoritativa.

**Aceite:** ausência, malformed isolation, outage retention e re-pair race têm
regressões públicas/duráveis.

### 4. Compatibilidade e rollout

- Atualizar primeiro o Relay para `0.3`; Extensions antigas podem consumir os
  erros UUID do Relay novo. Depois coordenar a atualização dos participantes
  Extension/MCP capazes de liderar para `0.6` e minimizar Extensions antigas e
  novas misturadas.
- A Extension nova aceita o ID legado apenas no erro `_relay` confiável para Relay
  antigo ou rollback do Relay; isso não é a razão de Relay-first ser seguro.
- Por uma release, o wire usa o nickname assinado bruto selecionado ou, ausente,
  os primeiros 8 caracteres da Pi-key canônica Base64 padrão com padding. O shim
  cobre mixed-version com visões iguais, únicas e sem `:`; delimitadores,
  colisões ou visões divergentes podem ser descartados silenciosamente pela
  Extension antiga. Atualizar todos os participantes Extension/MCP na mesma
  janela de manutenção.
- Rollout, rollback e qualquer validação física/de hardware são ações operacionais
  separadas, sem alegação de entrega neste plano.

**Aceite:** validações automatizadas nova↔nova e os casos cobertos nova↔antiga
passam; não há alegação de implantação, hardware ou interoperabilidade completa
de labels mistos.

### 5. Limpeza de escopo

- Remover contratos e planos duplicados.
- Restaurar short IDs públicos de pareamento ao prefixo EPK existente.
- Manter somente testes de comportamento público, regressões reais e contratos
  de segurança; remover matrizes de estado privado, wording e callback order.
- Centralizar detalhes técnicos em `PROTOCOL.md` e manter READMEs concisos.

**Aceite:** diff final não contém mudança mobile/schema/pairing, testes
exploratórios ou documentação operacional duplicada.

## Definition of Done

- [x] Identidade técnica canônica implementada e validada nos dois lados.
- [x] Aliases receiver-local e precedência segura implementados e validados.
- [x] Autorização direta, invalidade da contribuição e cache limitado validados.
- [x] Erros confiáveis, ACK vinculado ao destino e roster limitado validados.
- [x] Topologia estrita, SelfRevoke e floor em memória validados sem alegar
  persistência entre reinícios.
- [x] Extension `0.6.0` passa testes, typecheck e build.
- [x] Relay `0.3.0` passa fmt, testes, Clippy estrito e release build.
- [x] Documentação estabelece Relay-first e descreve o trust model sem provar
  pareamento pelo simples conteúdo do blob.
- [x] Testes alterados são regressões duráveis e não gates de implementação.
- [x] Duas revisões independentes não encontram blocker/high/medium.
- [x] Correções são aprovadas antes de commit e push.

## Próximos passos

O shim mixed-version limitado foi aceito pelo upstream e incorporado neste plano.
Validação final, revisões independentes e aprovação para commit/push foram
concluídas. Floor persistente continua adiado e acompanhado em
[#73](https://github.com/jacobaraujo7/remote_pi/issues/73); capability negotiation
permanece trabalho separado. Publicação, deployment, rollback e hardening do
verificador de artefatos continuam ações separadas.
