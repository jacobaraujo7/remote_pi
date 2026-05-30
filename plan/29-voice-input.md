# Plano 29 — Entrada por voz (STT nativo → texto)

**Objetivo**: dar ao app uma entrada por voz com *ergonomia estilo WhatsApp*
(segurar pra falar, waveform, soltar) cujo **conteúdo é texto** — transcrição
on-device que cai no campo de input pra o usuário revisar e enviar. É uma
feature **100% do app**: zero mudança em protocolo, relay ou pi-extension.

Resultado esperado: com o campo vazio, o usuário segura o mic → vê faixa de
gravação (ponto vermelho + timer + waveform) → solta → o transcript popula o
`TextField` → revisa/corrige → toca enviar. Arrastar pra cancelar descarta.

## Por que essa direção (e o que ela NÃO é)

O loop do agente Pi é **text-in** (`AgentSession.send(text)`); o SDK não ingere
áudio (confirmado no scout do plan/28). E o relay é plaintext, sem E2E
(plan/06) — qualquer byte que cruze o relay é visível ao operador. Logo:

- **Não** existe "mandar o áudio pro agente ouvir". Áudio precisa virar texto
  antes de chegar no agente. A pergunta é *onde* — e a resposta aqui é **no
  device**.
- Esta feature visa o *feeling* de mandar áudio no WhatsApp, mas o artefato é
  **texto**. Não há bolha de voz reproduzível, não há player, não há waveform
  no histórico. O áudio é **descartado** após a transcrição e **nunca sai do
  celular** (on-device only).

### Não-objetivos (cortados explicitamente)

- ❌ Enviar/armazenar arquivo de áudio (isso é a **Trilha 2** — ver "Próximos
  planos"). Sem bolha de voz, sem replay.
- ❌ Qualquer mudança em protocolo / relay / pi-extension.
- ❌ STT na nuvem (Apple/Google servers). On-device only.
- ❌ Transcript ao vivo durante a fala. Durante a gravação só waveform + timer;
  o texto materializa no fim.
- ❌ Auto-envio ao soltar. Sempre cai no campo pra revisão + envio manual.
- ❌ Concatenar/substituir texto preexistente. O mic só aparece com o campo
  **vazio** (lógica `_ComposerMode` já garante isso), então o transcript
  sempre popula um campo vazio.

---

## Decisões fixadas (entrevista de 2026-05-30)

| # | Decisão | Valor |
|---|---|---|
| 1 | Abordagem | STT **on-device → texto**, app-only |
| 2 | Conteúdo | Texto; áudio descartado pós-transcrição |
| 3 | Momento do envio | **Não** auto-envia. Release **ou** cap-60s populam o `TextField`; usuário envia manualmente |
| 4 | Gesto | **Hold-to-talk + slide-to-cancel**, sem trava. Soltar encerra; arrastar pra esquerda cancela e descarta |
| 5 | Limite | **~60s** (limite do `SFSpeechRecognizer`/`SpeechRecognizer`). Ao estourar: corta, transcreve, popula o campo (não descarta) |
| 6 | Feedback visual na fala | **Waveform + timer** (estilo WhatsApp), **sem** texto ao vivo |
| 7 | Privacidade | **On-device only** (`requiresOnDeviceRecognition`). Áudio nunca sai do celular; funciona offline |
| 8 | Idioma | Segue o **`Locale` do Flutter** (`Localizations.localeOf` / `PlatformDispatcher.locale`); i18n futura formaliza |
| 9 | Fallback de locale | Sem modelo on-device pro locale → **cai pra en-US on-device** (continua local). Sem nem en-US on-device → mic some (edge raro) |
| 10 | Permissão negada | Mic **continua visível**; 1º toque dispara prompt nativo; se negado, aviso com botão **pros Ajustes do sistema** |
| 11 | Apresentação da UI | **Faixa que substitui a input bar** (WhatsApp fiel): ponto vermelho pulsando + timer + waveform + hint "‹ arraste para cancelar" |
| 12 | Edge: transcript vazio | Silêncio/ruído → string vazia → campo permanece vazio, no-op, mic reaparece |

> **Consciência de risco (registrada)**: o pi-ext **não tem gate de approval**
> (decisão 2026-05-19 — tool calls executam direto). A escolha #3 (review no
> campo antes de enviar) é o que mitiga isso: o transcript só vira ação depois
> que o usuário lê e toca enviar.

---

## Stack / dependência nova

- **`speech_to_text`** (pacote Flutter de-facto): expõe `initialize()`,
  `listen(onResult, localeId, listenFor, onSoundLevelChange, onDevice)`,
  `locales()`, `hasPermission`, `stop()`, `cancel()`.
  - `onDevice: true` → força reconhecimento local.
  - `onSoundLevelChange` → amplitude pra alimentar a waveform.
  - `listenFor: Duration(seconds: 60)` → cap; no timeout, usar o último
    resultado (parcial/final) acumulado.
  - Ignoramos os resultados **parciais** visualmente (decisão #6); só o
    resultado final popula o campo.
- **Sem `record`/arquivo**: o `speech_to_text` capta o mic e transcreve em
  fluxo — **nenhum arquivo de áudio é criado**. Coerente com #2/#7.

### Config de plataforma

- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription` +
  `NSSpeechRecognitionUsageDescription` (copy honesta: "para ditar mensagens
  por voz; o áudio é processado no aparelho e não é enviado a servidores").
  Min iOS 18 já cobre on-device speech.
- **Android** (`AndroidManifest.xml`): `RECORD_AUDIO`. Verificar serviço de
  reconhecimento on-device disponível; senão aplicar fallback #9.

---

## Estrutura esperada após o plano

```
app/lib/
├── data/
│   └── voice/
│       └── speech_service.dart        ← wrapper do speech_to_text (passo 2)
└── ui/chat/
    ├── voice/
    │   ├── states/
    │   │   └── voice_input_state.dart  ← sealed: idle/recording/transcribing/error (passo 3)
    │   ├── viewmodels/
    │   │   └── voice_input_viewmodel.dart  ← orquestra o service (passo 3)
    │   └── widgets/
    │       └── recording_strip.dart    ← faixa WhatsApp (passo 4)
    ├── widgets/input_bar.dart          ← já tem onStartAudio; integra a faixa (passo 5)
    └── chat_page.dart                  ← passa onStartAudio + wiring de estado (passo 5)
```

---

## Passo 1 — dependência + permissões + config de plataforma

**Função**: deixar o terreno pronto (sem UI ainda).

- Adicionar `speech_to_text` ao `pubspec.yaml`.
- `Info.plist`: as duas usage descriptions.
- `AndroidManifest.xml`: `RECORD_AUDIO`.

**Aceite**:
- `flutter pub get` ok; `flutter analyze` 0 issues.
- Build iOS (`flutter build ios --no-codesign`) e Android debug passam com as
  permissões declaradas.

---

## Passo 2 — `data/voice/speech_service.dart`

**Função**: encapsular o `speech_to_text` atrás de uma interface testável,
resolvendo locale + fallback + on-device + cap.

**API sugerida**:
```dart
abstract class SpeechService {
  Future<SpeechAvailability> init();        // permissão + on-device + locale
  Stream<double> get soundLevel;            // 0..1 pra waveform
  Future<void> start({required String localeId, Duration maxDuration});
  Future<String> stop();                    // retorna transcript final
  Future<void> cancel();                    // descarta
}
```

**Comportamento**:
- Resolução de locale: pega o `Locale` do Flutter → `localeId` (`pt_BR`,
  `en_US`, ...). Checa em `locales()` se há suporte on-device; se não, usa
  `en_US`. Se nem `en_US` on-device → reporta `SpeechAvailability.unsupported`.
- `start` chama `listen(onDevice: true, listenFor: maxDuration, ...)`.
- Aos 60s (timeout do `listenFor`) **ou** `stop()`: resolve com o transcript
  acumulado (string vazia se nada).

**Aceite** (test com fake do plugin):
- locale sem on-device → cai pra `en_US`.
- timeout de 60s resolve com o transcript parcial até ali.
- `cancel()` resolve sem texto e sem efeito no estado externo.
- permissão negada → `SpeechAvailability.permissionDenied`.

---

## Passo 3 — ViewModel + states

**Arquivos**: `voice/states/voice_input_state.dart`,
`voice/viewmodels/voice_input_viewmodel.dart`.

**States** (sealed, com `==`/`hashCode`):
- `VoiceIdle` — mic disponível, pronto.
- `VoiceRecording(elapsed, level)` — gravando; alimenta a faixa.
- `VoiceTranscribing` — soltou, finalizando (estado curto; on-device é rápido,
  mas cobre o gap).
- `VoiceUnavailable(reason)` — `permissionDenied` | `unsupported`.

**ViewModel**: `startRecording()`, `stopAndTranscribe()` (emite o texto via
callback pra página popular o campo), `cancel()`. Registrar em
`config/dependencies.dart` (`addViewModel`) e bindar no router conforme
convenção da camada `ui/`.

**Aceite**:
- start → `VoiceRecording`; level/elapsed atualizam.
- stop → `VoiceTranscribing` → texto entregue ao callback → volta a `VoiceIdle`.
- cancel → volta a `VoiceIdle` sem texto.
- init com permissão negada → `VoiceUnavailable(permissionDenied)`.

---

## Passo 4 — `recording_strip.dart` (faixa WhatsApp)

**Função**: a faixa que **substitui** a input bar durante a gravação.

**Conteúdo**: ponto vermelho pulsando + timer `MM:SS` correndo + waveform
animada (do `soundLevel`) + hint "‹ arraste para cancelar". Próximo dos 60s,
countdown/realce visual (decisão #5 — sem precisar de aviso sonoro, mas o timer
deixa claro). Soltar = encerra; arrastar além do threshold = cancela.

**Aceite** (widget test):
- waveform reage ao stream de level.
- timer incrementa.
- gesto de arrastar além do threshold dispara `cancel`.

---

## Passo 5 — wiring no `InputBar` + `chat_page`

**Função**: ligar o mic morto.

- `chat_page._buildInput`: passar `onStartAudio` (hoje ausente — ver
  `chat_page.dart:341-352`). Desabilitado nas mesmas condições do `disabled`
  atual (offline/revoked/streaming).
- `InputBar`: ao detentor segurar o mic (`onStartAudio` → press), trocar a Row
  inteira pela `RecordingStrip`; ao soltar, transcrever e `_controller.text =
  transcript` (campo estava vazio por construção) — o botão já vira "enviar"
  sozinho (`_ComposerMode.sendText`).
- Permissão negada (#10): mic visível; toque dispara prompt; se já negado,
  `SnackBar`/dialog com ação "Abrir Ajustes" (`app_settings`/`openAppSettings`).
- Locale sem on-device (#9): service já resolve pra en-US; nenhuma UI especial.
- Sem nenhum on-device (edge): `VoiceUnavailable(unsupported)` → esconder o mic
  (campo vazio mostra só o placeholder de anexo; usuário dita pelo teclado).

**Aceite**:
- hold no mic → faixa aparece; soltar → texto no campo, botão vira send.
- slide-to-cancel → campo segue vazio, mic volta.
- 60s → corta, popula o campo.
- permissão negada → guia pros Ajustes; mic permanece.
- `flutter test` cobre o fluxo via fake do `SpeechService`.

---

## Riscos / spikes

1. **Detecção de on-device por locale**: `SFSpeechRecognizer.supportsOnDevice`
   é por-locale; confirmar como o `speech_to_text` expõe isso (talvez só dê pra
   inferir tentando `listen(onDevice:true)` e tratando falha). **Spike curto**
   no início do passo 2.
2. **Comportamento exato no timeout de 60s** (resultado parcial vs final) varia
   entre iOS/Android — validar em device real.
3. **Gesto hold + slide** sobre um botão pressionado: usar `GestureDetector`
   com `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd` ou pointer
   events; cuidar do threshold de cancelamento.
4. **Waveform a partir de amplitude** (`soundLevel`) — não é FFT real; é
   envelope de volume. Suficiente pro feeling, registrar que não é espectro.

---

## Definition of Done

- [ ] `speech_to_text` no `pubspec.yaml`; permissões iOS/Android declaradas (passo 1)
- [ ] `data/voice/speech_service.dart` + testes (passo 2)
- [ ] `voice/states/*` + `voice/viewmodels/*` registrados em `config/` e router (passo 3)
- [ ] `voice/widgets/recording_strip.dart` + widget test (passo 4)
- [ ] `chat_page` passa `onStartAudio`; `InputBar` integra a faixa; fallbacks de permissão/locale (passo 5)
- [ ] Spike de detecção on-device por locale resolvido (risco 1)
- [ ] `flutter analyze` 0 issues; `flutter test` verde
- [ ] Smoke manual em device real: ditar pt-BR popula o campo; soltar/cancelar/60s; permissão negada guia pros Ajustes
- [ ] Verificação: nenhum arquivo de áudio criado; nada cruza o relay (só `user_message{text}` no envio manual)
- [ ] Commit: `feat(plan-29): voice input (native STT → text)`

---

## Próximos planos

- **`30-file-transfer.md` (Trilha 2)** — envio de **arquivos** genérico, que de
  quebra habilita áudio-como-arquivo (bolha de voz real, replay). Decisão de
  transporte em aberto: **(a)** upload pro relay + download por link, vs **(b)**
  WebRTC P2P pra maior privacidade. Estudar como o **`pi-telegram`** envia
  arquivos antes de fechar. Provavelmente exige mudança de protocolo (novo tipo
  carregando referência/binário) e revisita o perfil de carga do relay. **Não
  faz parte do plano 29.**
