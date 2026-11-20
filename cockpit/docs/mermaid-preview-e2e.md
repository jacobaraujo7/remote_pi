# Mermaid no preview — documento de teste (plano 72)

Abra este arquivo no Cockpit (macOS/Windows) em modo Preview. Checklist:

- [ ] Todos os diagramas abaixo renderizam, exceto o **inválido**, que mostra a
      caixa "Erro no diagrama" (localizada) + mensagem da lib + o código
- [ ] Editar este parágrafo (Código ↔ Preview, ou split) não faz nenhum
      diagrama piscar
- [ ] Editar um diagrama atualiza só ele
- [ ] O flowchart LR largo rola de lado dentro do próprio bloco, sem estourar o pane
- [ ] Trocar tema claro ↔ escuro redesenha os diagramas com as cores novas
- [ ] O `click` do flowchart "segurança" não faz nada
- [ ] Um `.md` sem diagrama: Web Inspector → `typeof window.mermaid === 'undefined'`

## Flowchart LR com subgraph e `<br/>`

```mermaid
flowchart LR
  subgraph ciclo[Ciclo de 5 min]
    A[Coleta<br/>SCS] --> B{Válido?}
    B -->|sim| C[Grava no banco]
    B -->|não| D[Descarta e loga]
  end
  C --> E[Agrega] --> F[Publica] --> G[Notifica] --> H[Arquiva] --> I[Fim]
```

## stateDiagram-v2

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Running: start
  Running --> Paused: pause
  Paused --> Running: resume
  Running --> [*]: done
```

## sequenceDiagram

```mermaid
sequenceDiagram
  participant App
  participant Server
  App->>Server: fs.read
  Server-->>App: bytes
  Note over App,Server: SSH + cockpit-server
```

## gantt

```mermaid
gantt
  title Plano 72
  dateFormat YYYY-MM-DD
  section Preview
  Vendorizar   :a1, 2026-11-18, 1d
  Render       :a2, after a1, 2d
```

## erDiagram

```mermaid
erDiagram
  WORKSPACE ||--o{ PANE : has
  PANE ||--o{ TAB : holds
```

## Segurança (`securityLevel: strict`)

```mermaid
flowchart TD
  A[Clique aqui] --> B[Nada acontece]
  click A call alert("não deveria rodar")
```

## Inválido

```mermaid
flowchart TD
  A -->
  isto não é mermaid ((((
```
