# Plano 49 — Preview de imagem recebida no CLI

**Objetivo**: quando o Android enviar uma foto em `user_message.images`, o Pi
CLI/TUI também mostra a foto recebida. Hoje o modelo recebe a imagem, e o app
renderiza o balão, mas a TUI do Pi só mostra a legenda/texto.

## Contexto

Fluxo atual (plano 30):

`Android` → `user_message.images[]` → relay opaco → `pi-extension/src/index.ts`
→ `_contentFromUserMessage()` converte para `ImageContent` do SDK →
`_wakeAgent()` entrega ao modelo → `_echoUserMessage()` rebroadcast para owners.

O ponto principal é o `case "user_message"` em `pi-extension/src/index.ts`, mas
há dois caminhos de entrega que precisam do mesmo preview: mensagem direta e
mensagem enfileirada durante compaction, drenada por `_drainCompactionQueue()`.
Não tocar no relay: ele só encaminha `ct`. Não tocar no app: ele já envia e
renderiza.

## Decisão

Usar **preview inline + caminho de fallback**:

1. Ao receber imagem do Android, o `pi-extension` valida/decodifica o base64 e
   salva os bytes em um cache temporário privado (`/tmp/pi-app-*` ou equivalente
   de `os.tmpdir()`), com nome `<message-id>-<index>.<ext>`.
2. O diretório temporário deve ser privado (`0700` best-effort) e cada arquivo
   salvo deve ficar privado (`0600` best-effort), porque fotos são dados do
   usuário e não devem inflar `~/.pi`.
3. Para preview inline, JPEG/WebP/GIF podem gerar um arquivo temporário
   `<message-id>-<index>.preview.png` via o helper público `convertToPng` do Pi.
   A saída PNG convertida também respeita o limite de 10 MiB. O renderer só
   entrega PNG ao componente `Image`; se a conversão falhar, fica só no fallback
   textual com o caminho salvo.
4. Emite um `pi.sendMessage({ customType: "remote-pi:received-image", content:
   "", details, display: true })` **sem** `{ triggerTurn: true }`; no caminho
   idle, o preview é anexado antes do `sendUserMessage` para não virar steer do
   mesmo turn. Se a mensagem recebida já é steering de um turn ativo, o preview
   é adiado até `agent_end`.
5. `details` carrega só metadados pequenos: caminho, `previewPath` opcional,
   mime, tamanho, índice, `messageId`, legenda/texto. Nunca guardar `data`,
   base64 ou bytes da imagem em `content`/`details` para não inflar histórico.
   Além disso, os hooks `context` e `session_before_compact` removem
   `remote-pi:received-image` antes de provider requests e sumarização de
   compaction para manter esses previews fora do contexto do modelo.
6. Registra um renderer customizado para esse `customType`.
7. O renderer tenta renderizar inline com `@earendil-works/pi-tui` `Image`
   somente a partir de PNG (`path` quando a imagem original já é PNG, ou
   `previewPath` gerado). O `Image` fica fora de `Box`/padding para preservar as
   linhas reservadas do Kitty; terminais sem suporte ou conversão indisponível
   caem no fallback textual + caminho do arquivo salvo.

A imagem real continua vindo do `user_message` original para o modelo; a
mensagem customizada existe só para exibição local na TUI.

## Não-objetivos

- Não mudar protocolo (`WireImage` fica igual).
- Não mudar app Android/iOS.
- Não mudar relay.
- Não implementar galeria/zoom/gerenciador de anexos no desktop.
- Não tentar renderizar via `process.stderr`/escape direto fora da TUI.

## Estrutura esperada

```text
pi-extension/
├── package.json                     # declarar @earendil-works/pi-tui direto
└── src/
    └── index.ts                     # hook no user_message + registro renderer
```

## Passos com critério de aceite

### 1. Persistir imagem recebida

- Adicionar helper pequeno para:
  - aceitar só `image/jpeg`, `image/png`, `image/webp`, `image/gif`;
  - mapear mime para extensão segura;
  - rejeitar `data:` URI, whitespace e caracteres/padding fora de base64 padrão;
  - estimar tamanho antes do decode e rejeitar payloads que possam passar de
    10 MiB;
  - decodificar e confirmar `buffer.length > 0 && buffer.length <= 10 MiB`;
  - criar um diretório temporário privado via `mkdtempSync(join(tmpdir(), "pi-app-"))`
    com `mode: 0o700`/`chmodSync(..., 0o700)` best-effort;
  - escrever arquivo com nome derivado de `msg.id` + índice sanitizados,
    extensão segura, `mode: 0o600` + `chmodSync(..., 0o600)` best-effort;
  - para mime não-PNG, tentar gerar `*.preview.png` com `convertToPng`; se
    falhar ou a saída PNG passar de 10 MiB, remover parcial e manter só o arquivo
    original temporário.
- Em erro de decode/mime, não derrubar o turn: registrar `console.error`, emitir
  preview textual de falha, e continuar entregando a imagem ao modelo como hoje.

**Aceite**: teste unitário cobre nome/extensão, mime recusado, `data:` URI,
caracteres/padding inválidos, payload vazio, payload acima de 10 MiB e permissões
POSIX quando a plataforma expõe mode bits.

### 2. Surfacing no TUI

- Criar um helper compartilhado, por exemplo `_showReceivedImagesInCli(msg)`.
- Chamar esse helper em **dois lugares**:
  1. caminho direto do `case "user_message"`: em idle, emitir antes de
     `_wakeAgent()`; em steering ativo, enfileirar e só emitir no `agent_end`;
  2. `_drainCompactionQueue()`, quando a compaction já terminou, antes do wake
     bem-sucedido da mensagem que foi enfileirada durante compaction.
- Esse helper emite `remote-pi:received-image` com `content: ""`, `display: true`
  e metadados dos arquivos salvos em `details`; hooks de contexto/compaction
  filtram esse `customType` antes de chamadas ao provider ou sumarização.
- Não mudar o caminho sem imagem.

**Aceite**: teste existente de `user_message` com imagem passa; novo teste vê
`pi.sendMessage` chamado com `customType: "remote-pi:received-image"`,
`display: true`, sem `triggerTurn`, e sem `data`/base64 em `content` ou `details`;
teste sem imagem prova que nada novo é emitido; teste de imagem durante compaction
prova que o preview aparece após a drenagem; teste de steering ativo prova que o
preview local só é emitido após `agent_end`; teste de contexto prova que o
`customType` não vai para provider requests nem sumarização de compaction.

### 3. Renderer inline + fallback

- Declarar `@earendil-works/pi-tui` como dependência direta do `pi-extension`
  (já é dependência transitiva do Pi, mas import direto deve ser explícito).
- Registrar `pi.registerMessageRenderer("remote-pi:received-image", renderer)`
  no setup da extensão.
- Renderer monta um componente simples:
  - título curto: `📷 Photo from Android`;
  - legenda se existir;
  - linha `Saved: <path>` sempre visível;
  - escolhe caminho renderizável: `previewPath` quando presente, senão `path`
    apenas se `mime === "image/png"`;
  - lê esse PNG e passa `readFileSync(...).toString("base64")` para
    `new Image(base64Data, "image/png", theme, ...)`, fora de qualquer `Box`
    que adicione padding/background às linhas da imagem.
- Se arquivo sumiu, conversão não existir, ou terminal não suportar imagem,
  renderizar fallback textual com mime/tamanho + caminho, sem throw e sem tentar
  renderizar JPEG cru (evita linhas em branco no Kitty).

**Aceite**: typecheck passa; teste automatizado captura o renderer registrado,
invoca com arquivo ausente e/ou terminal sem imagem e confirma título +
`Saved: <path>` sem throw; smoke manual em terminal com suporte mostra a foto;
terminal sem suporte mostra fallback + path.

### 4. Verificação

Rodar no `pi-extension/`:

```bash
pnpm typecheck
pnpm test
```

Smoke manual:

1. Rebuild/instalar extensão local se necessário.
2. `/remote-pi pair` e enviar foto do Android.
3. Confirmar que:
   - a TUI mostra preview ou fallback + caminho temporário `/tmp/pi-app-*`;
   - o modelo continua recebendo a imagem;
   - Android continua vendo o balão com imagem;
   - mensagem sem imagem permanece igual;
   - foto enviada durante compaction aparece quando a fila drena.

## Definition of Done

- [x] Foto Android aparece no Pi CLI/TUI com inline preview quando suportado.
- [x] Fallback mostra caminho salvo quando inline não é suportado.
- [x] Arquivo é salvo em cache temporário privado (`/tmp/pi-app-*`/`os.tmpdir()`) com extensão segura e permissões privadas best-effort.
- [x] Sem mudança em relay/protocolo/app.
- [x] Preview cobre caminho direto e caminho enfileirado durante compaction.
- [x] `remote-pi:received-image` não guarda base64/bytes em `content` nem `details`, e é filtrado do contexto do provider.
- [x] `pnpm typecheck` verde em `pi-extension/`.
- [x] `pnpm test` verde em `pi-extension/`.
- [x] Smoke manual Android → Pi feito.

## Próximos planos

Se o cache crescer demais, adicionar limpeza simples por idade/tamanho em um plano
futuro. Não bloquear este plano com política de retenção agora.
