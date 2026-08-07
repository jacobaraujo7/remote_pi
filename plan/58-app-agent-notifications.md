# 58 — App: notificações de agente

## Contexto

Notificação nativa local quando um agente termina um turno. Usa
`flutter_local_notifications` no Android/iOS, sem dependência externa (sem
FCM, sem central de push). O i18n foi separado no plano 59.

## Estrutura

```
app/
├── lib/
│   ├── domain/contracts/notifier.dart       # abstração
│   ├── data/notifications/local_notifier.dart # impl
│   ├── data/sync/sync_service.dart          # _checkAllRoomsForAgentFinish
│   └── config/dependencies.dart             # DI
└── android/app/build.gradle.kts             # coreLibraryDesugaring
```

## Passos

1. **Notifier abstraction + LocalNotifier** — `flutter_local_notifications`,
   permissão Android 13+, canal `agent_turn`.
2. **_checkAllRoomsForAgentFinish** — detecta `working → idle` para todas as
   salas via `roomsStream`, dispara `_notifier.agentFinished(nickname, workspace)`.
3. **Testes** — 3 testes unitários (FakeNotifier).

## DoD

- [x] 1 — Notifier + LocalNotifier (com permissão Android 13+)
- [x] 2 — _checkAllRoomsForAgentFinish (qualquer sala, não só a ativa)
- [x] 3 — Testes passando + zero regressões (553/554)
