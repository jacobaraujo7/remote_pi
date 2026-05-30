# Plano 30 — Anexar imagem (Trilha 2, sub-feature 1)

**Objetivo**: deixar o app enviar **uma imagem** (câmera ou galeria) junto com
uma legenda opcional, que o pi-extension entrega ao agente como conteúdo
**multimodal** (`ImageContent`). É a primeira fatia da "Trilha 2" (envio de
arquivos). **Vídeo e arquivo genérico ficam fora** — sem consumidor no agente.

Resultado esperado: com o campo vazio, o usuário toca o anexo → escolhe câmera
ou galeria → a imagem (comprimida no device) vira um **preview no composer** com
legenda opcional → toca enviar → o modelo enxerga a imagem + legenda. No chat
fica um **balão com thumbnail + legenda**.

## Por que essa direção

O `AgentSession.sendUserMessage` aceita `string | (TextContent | ImageContent)[]`,
e `ImageContent = { type:"image"; data:base64; mimeType }` vai **direto pro modelo
multimodal** (Claude). Imagem é o **único** tipo não-texto com caminho de 1ª classe
no SDK:

- **Imagem** → `ImageContent` (multimodal). ✅ esta feature.
- **Arquivo genérico** (log, código, PDF) → o agente lê do disco via tool `Read`;
  não é message content. Fica pra uma fatia futura (precisa pousar bytes no Mac).
- **Áudio** → sem caminho; vira texto (plano 29). **Vídeo** → Claude não ingere. ❌

Transporte: imagem vai **inline** na `user_message` (base64), dentro do `ct`
opaco que já existe — o **relay não muda**. Sem canal binário no relay nesta
fatia (só se paga quando entrarem arquivos grandes — ver "Próximos planos").

## Não-objetivos (cortados explicitamente)

- ❌ Vídeo, áudio-arquivo, arquivo genérico, PDF.
- ❌ Múltiplas imagens por mensagem (uma só).
- ❌ Visualizador full-screen / zoom no balão (thumbnail estático).
- ❌ Canal binário no relay / chunked / upload out-of-band (Trilha 2 futura).
- ❌ Placeholder de imagem no histórico (decisão #8 manda bytes sempre).
- ❌ Enviar na hora (sempre passa por preview + envio manual).

---

## Decisões fixadas (entrevista de 2026-05-30)

| # | Decisão | Valor |
|---|---|---|
| 1 | Escopo | **Só imagem**. Toca `app` + `pi-extension` + protocolo; **relay inalterado** |
| 2 | Entrada | Botão de anexo (hoje morto: `attach_file_rounded` em `input_bar.dart:84`) → menu **Câmera / Galeria** |
| 3 | Fluxo de envio | Pick → **preview no composer + legenda opcional** (texto+imagem juntos) → **envio manual** (review antes) |
| 4 | Quantidade | **Uma imagem** por mensagem |
| 5 | Compressão | **JPEG**, lado maior **~1568px**, qualidade **~80%** (~150–400 KB), feita no app |
| 6 | Protocolo | **Estende `user_message`** com `images?: [{ data, mime }]` (array, manda uma). Espelha `(TextContent\|ImageContent)[]` do SDK. Opcional = retrocompatível |
| 7 | Balão | **Thumbnail estático** + legenda. **Sem** full-screen |
| 8 | Histórico/recovery | **Sempre carrega a base64** no replay (fidelidade total; aceita re-tráfego no `session_sync` + crescimento do mirror cache) |
| 9 | Modelo não-multimodal | App **desabilita** (não esconde) o anexo quando o modelo ativo não aceita imagem. Viável via `model.input.includes("image")` → flag `vision` no `WireModel` |

### Defaults assumidos (vetar se discordar)

- **Permissões**: o photo picker do sistema (`image_picker` → PHPicker no iOS /
  Photo Picker no Android 13+) **não exige permissão de galeria**. Só o caminho
  **câmera** pede `NSCameraUsageDescription` / Android `CAMERA`. Negada → guia
  pros Ajustes (mesmo padrão do plano 29, reusa `app_settings`).
- **Menu** (#2): interpretado como **bottom sheet / action sheet** (idioma
  mobile, consistente com o quick-actions sheet existente) — não dropdown literal.
- **Teto de segurança**: se pós-compressão ainda > ~1,5 MB (raro), reduz
  dimensão/qualidade iterativamente. Praticamente nunca dispara.
- **Remover antes de enviar**: "X" no thumbnail do composer descarta a imagem
  anexada sem enviar.
- **Send-mode**: com imagem anexada o botão vira **enviar** mesmo com legenda
  vazia (`_ComposerMode`: `hasImage || hasText` → send; senão mic).
- **Gating**: anexo desabilitado offline/streaming (igual ao texto).
- **Broadcast**: o echo de `user_message` pra outros owners passa a incluir `images`.
- **Libs**: `image_picker` + `flutter_image_compress`.

---

## Estrutura esperada

```
app/lib/
├── data/
│   └── images/
│       └── image_picker_service.dart   ← pick (câmera/galeria) + compress (passo C1)
└── ui/chat/
    ├── widgets/
    │   ├── input_bar.dart              ← +preview/+attach menu/+send-mode (passo C2)
    │   ├── attach_sheet.dart           ← bottom sheet Câmera/Galeria (passo C2)
    │   └── image_bubble.dart           ← thumbnail estático + legenda (passo C3)
    └── viewmodels/chat_viewmodel.dart  ← sendMessage(text, image?) (passo C2)
pi-extension/src/
├── protocol/types.ts                   ← user_message.images + WireModel.vision (passo A)
└── index.ts                            ← ingest images→sendUserMessage; echo; vision flag (passo B)
app/lib/protocol/protocol.dart          ← idem app-side (passo A)
```

---

## Wave A — Protocolo (app + pi-extension)

**pi-extension** (`src/protocol/types.ts`):
```ts
| { type: "user_message"; id: string; text: string; images?: WireImage[] }
export interface WireImage { data: string /* base64 */; mime: string }
// WireModel ganha:
export interface WireModel { /* ...existente... */ vision: boolean }
```
**app** (`lib/protocol/protocol.dart`): campo `images` opcional no
`ClientUserMessage` (e no parse de `user_message` server-side, já que o echo
volta), `WireModel.vision`.

**Aceite**: `pnpm typecheck` + `flutter analyze` verdes; codec roundtrip com e
sem `images`; `PROTOCOL.md` atualizado (seção "Imagens").

---

## Wave B — pi-extension

1. **Ingest** (`_routeClientMessageFrom`, case `user_message`): se `msg.images`
   presente, montar `content: (TextContent|ImageContent)[]` =
   `[...images.map(i => ({type:"image", data:i.data, mimeType:i.mime})), {type:"text", text: msg.text}]`
   e chamar `sendUserMessage(content)`. Sem imagens → caminho atual (string).
2. **Echo/broadcast** (`_broadcastToActive` do `user_message`): incluir `images`
   pra outros owners renderizarem o balão.
3. **Vision flag** (`_handleListModels` / `wireFromModel`):
   `vision: m.input?.includes("image") ?? false`. Idem no evento `model_select`
   que o app usa pra rastrear o modelo atual (se carregar `WireModel`).

**Aceite**: vitest cobrindo (a) `user_message` com 1 imagem → `sendUserMessage`
recebe `ImageContent`+`TextContent`; (b) sem imagem → comportamento atual; (c)
`models_list` carrega `vision` correto pra modelo com/sem `"image"` no `input`.
`pnpm typecheck && pnpm test` verdes, sem regressão.

> **Check rápido (não-spike)**: confirmar que o `Model<Api>` resolvido por
> `reg.getAvailable()` expõe `.input` em runtime (não só o `ProviderConfigInput`).
> Se o nome do campo divergir, ajustar o acesso — a capacidade existe.

---

## Wave C — app

**C1 — `image_picker_service.dart`**: `pickFromCamera()` / `pickFromGallery()`
via `image_picker`; comprime com `flutter_image_compress` (lado maior 1568px,
JPEG q80); retorna `{ bytes, mime, width, height }`. Teto de segurança iterativo.

**C2 — composer** (`input_bar.dart` + `attach_sheet.dart` + VM):
- Anexo morto vira botão → abre `attach_sheet` (Câmera/Galeria). Desabilitado
  quando offline/streaming **ou modelo ativo sem `vision`** (#9).
- Após pick: thumbnail-preview acima/dentro da barra + "X" pra remover; campo de
  legenda ativo; botão vira **enviar** (mesmo legenda vazia).
- `chat_viewmodel.sendMessage(text, image?)` → `ClientUserMessage(images: [...])`;
  base64 da imagem comprimida.

**C3 — balão** (`image_bubble.dart`): thumbnail estático (altura limitada) +
legenda embaixo, no balão do usuário. Renderiza da base64 (local pro enviado;
do histórico no replay — #8). Sem tap/zoom.

**Permissões**: câmera → `NSCameraUsageDescription` / Android `CAMERA`; negada →
snackbar com "Ajustes" (`app_settings`, já no projeto pós-29). Galeria via picker
do sistema = sem permissão.

**Rastreio de `vision`**: o app já escuta `model_select`/`models_list` (plano 28);
guardar `currentModelVision` no estado e desabilitar o anexo quando `false`.

**Aceite**: widget tests — pick mockado popula preview; remover-X limpa; enviar
despacha `user_message` com `images`; balão renderiza thumbnail+legenda; anexo
**disabled** quando `vision=false`. `flutter analyze` 0 issues; `flutter test`
verde; builds iOS+Android passam.

---

## Wave D — integração + docs

- **Histórico** (#8): garantir que `session_sync`/mirror cache (planos 13/16)
  trafegam e persistem `images`. Ponto de integração — verificar que o replay
  reconstrói o balão.
- **Smoke manual** (device): câmera→preview→enviar→modelo responde citando a
  imagem; galeria idem; modelo text-only → anexo cinza; permissão de câmera
  negada → guia pros Ajustes.
- **Docs**: `PROTOCOL.md` (seção Imagens), `pi-extension/README.md` (Mobile app
  actions ganha "Imagens"), `site/` copy (sem screenshot — regra do site).

---

## Riscos

1. **Tamanho × broadcast**: imagem inline + decisão #8 (histórico sempre com
   bytes) inflam `session_sync` e o mirror cache local. Mitigado pela compressão
   agressiva (~150–400 KB) e 1 imagem/msg. Monitorar; se doer, fatiar pra canal
   binário (Trilha 2 futura).
2. **Double-base64**: `ct = base64(JSON com base64 da imagem)` ≈ +77% no fio.
   Aceito nesta fatia (imagem pequena). É o argumento que justifica o canal
   binário quando arquivos grandes entrarem.
3. **`.input` em runtime** (Wave B check): confirmar o nome do campo no `Model`
   resolvido.

---

## Definition of Done

- [ ] Wave A: `user_message.images` + `WireModel.vision` nos 2 lados; `PROTOCOL.md`; typecheck+analyze verdes
- [ ] Wave B: ingest→`sendUserMessage` multimodal + echo com images + vision flag; vitest; `pnpm test` sem regressão
- [ ] Wave C1: `image_picker_service` (pick+compress 1568px/q80) + testes
- [ ] Wave C2: attach sheet + preview/remover + send-mode + gating por vision/offline/streaming
- [ ] Wave C3: `image_bubble` thumbnail estático + legenda
- [ ] Permissões câmera (iOS/Android) + guia pros Ajustes na negativa
- [ ] `flutter analyze` 0 issues; `flutter test` verde; builds iOS+Android
- [ ] Wave D: histórico/mirror cache trafega images; smoke manual; docs
- [ ] Verificação: relay inalterado (forward opaco); modelo text-only desabilita anexo
- [ ] Commit: `feat(plan-30): image attachments (camera/gallery → multimodal)`

---

## Próximos planos

- **Trilha 2 — arquivos grandes / genéricos**: quando passar de imagem pequena
  (vídeo fora; logs/código/PDF pro agente `Read` no disco do Mac), introduzir o
  **canal binário no relay** (`Message::Binary` com header de roteamento — hoje o
  relay descarta binário em `peer.rs:162`) e/ou **chunked** (`file_begin`/
  `file_chunk`/`file_end`), eliminando o imposto base64. Estudar `pi-telegram`
  pra mecânica de recepção. Decisão de transporte (relay stateful vs WebRTC) fica
  pra esse plano.
