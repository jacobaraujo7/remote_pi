# 64: Anúncio do Cockpit 2.0 (highlights)

Material de anúncio derivado de `.orchestration/results/cockpit-2.0-novidades.md`
e do plano [63](./63-site-cockpit-2.0.md). Serve para post de lançamento,
release notes, README e redes.

Regra de precisão: no Cockpit, "remoto" é SSH mais `cockpit-server`, nunca o
relay do Remote Pi. Não misturar os dois produtos.

## Pitch em uma frase

> **A terminal that grew an IDE around your agents.**
> Run Claude Code, Codex, Pi or anything else in real terminals, local or on any
> machine over SSH, with the viewer, diagnostics, git, worktrees and databases
> they need to work.

Alternativas curtas:
- *The multiplexed terminal your coding agents deserve, on your machine or on any host over SSH.*
- *Cockpit runs your agents where they belong: in a real terminal, with an IDE around it.*

Versão PT (para redes em português):
- *O terminal que criou uma IDE em volta dos seus agentes. Claude Code, Codex ou Pi rodando de verdade, na sua máquina ou em qualquer host via SSH.*

## Os sete highlights

Ordem sugerida de comunicação. O primeiro é a manchete.

### 1. Seu workspace, em qualquer máquina
Abra uma pasta em outro computador e trabalhe nela como se fosse local:
terminais, arquivos, editor, source control e bancos de dados rodam no host.
Linux x86_64 e ARM64, macOS e Windows são hosts de primeira classe.

> *Open a folder on another machine and work in it exactly like a local one.*

### 2. Suas sessões sobrevivem ao cliente
Feche o laptop e o agente continua rodando no host. Reconecte e o terminal
retoma de onde parou. Queda de conexão mostra um banner e tenta de novo: os
terminais congelam em vez de morrer.

> *Close the laptop, the agent keeps working. Reconnect and the terminal picks up where it stopped.*

### 3. Uma VPS vira host com um curl
```
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash
```
Sem desktop, sem sudo, sem systemd obrigatório. A flag `--service` registra uma
unit `systemd --user` para manter o host de pé. Validado em VPS real, x86_64 e
arm64.

> *One curl turns a headless Linux box into a Cockpit host.*

### 4. Cockpit no iPad
O mesmo workspace a partir de um tablet: painéis viram gavetas, abas rolam e
reordenam por toque, e uma barra de teclas entrega o que o teclado do tablet não
tem (ESC, Tab, Ctrl+C, setas, F1 a F12). É um cliente remoto puro: conecta num
host e trabalha.

> *The same workspace, from a tablet.*

Cuidado no anúncio: ainda não está nas lojas. Anunciar com APK direto, sem botão
de loja, até App Store e Play Store saírem.

### 5. Documentos que viram abas
O Cockpit deixou de ser só terminal:
- **Notebook** (`.notebook`): uma pasta de notas markdown com tags,
  `[[wiki links]]` e imagens, que o agente escreve com `cockpit note add` e você
  lê no app. O git e o Obsidian veem os mesmos arquivos.
- **`.http`**: escreva a request na sintaxe do REST Client, ⌘↵, leia a resposta
  como JSON, headers ou texto. O agente dispara a mesma request com
  `cockpit http run`.
- **Kanban** com dependências entre cards, filtro e drag and drop.
- **Mermaid** renderizado no preview de markdown, offline, no seu tema.
- **Janela de documento**: abra qualquer arquivo em janela própria, inclusive
  com duplo clique no Finder, no Explorer e no gerenciador de arquivos do Linux.
- **Gallery**: um clique cria e abre qualquer documento do Cockpit.

> *Your notes, your requests, your boards and your queries are tabs now.*

### 6. Segredos que não vazam para a tela
Um `.env.cockpit` na raiz do workspace alimenta todo terminal que o Cockpit
abre ali, e os valores injetados aparecem como `***` no terminal, no scrollback
salvo e no `cockpit read-tab`. Chaves que mudam quem executa o quê (PATH, SHELL,
HOME, LD_* e DYLD_*) nunca são injetadas.

> *Stop pasting tokens into your agent's prompt.*

### 7. O agente dirige o cockpit
De dentro de uma aba, o comando `cockpit` abre abas e splits, digita em outra
aba, lê a saída dela, roda tasks, consulta os bancos e escreve notas. Local ou
via SSH. As conexões de banco são read-only por padrão e podem ser escondidas
da CLI, então o agente consulta o que você permitir.

> *From inside a tab, your agent opens tabs, reads them, runs tasks and queries your databases.*

## O que saiu, e como contar

A 2.0 remove o agente nativo (`pi --mode rpc`), a aba de agente, o setting
`enableAgent`, as abas de Settings Connectivity, Daemon Agents e Schedules, o
pareamento por QR e o gateway de relay.

**Comunicar como foco, não como perda.** O argumento honesto:

> A aba de agente era um harness, com uma UI própria que nunca ganhou
> `.env.cockpit`, Restart, status de turno nem as UI requests da extensão. O
> caminho do terminal ganhou tudo isso e roda qualquer harness. Sair dela não
> tira capacidade, tira um cidadão de segunda classe.

Em inglês, para o changelog e o post:

> *The agent tab was one harness with a second-class UI. The terminal path runs
> every harness and got everything the agent tab never did. Removing it removes
> a fork in the road, not a capability.*

## O que NÃO entra no anúncio

- Bugs que só existiram dentro do ciclo beta 1.28.x. Quem vem da 1.27 nunca os
  viu. O anúncio conta o estado atual, não a via-crúcis.
- Refactors, higiene de repo, decisões de engenharia (sandbox off, forks de
  dependência, pin de tags).
- iOS: existe projeto, mas não existe CI, TestFlight nem submissão. Não
  prometer.
- Play Store e App Store enquanto k11 e k12 não saírem.
- Assinatura no Windows enquanto o SignPath não aprovar. O aviso de SmartScreen
  continua valendo.

## Formatos prontos

### Post curto (X, Bluesky, LinkedIn)
> Cockpit 2.0 is out.
>
> Open a folder on another machine over SSH and work in it like a local one:
> terminals, files, git and databases run on the host. Close the laptop, the
> agent keeps going.
>
> Claude Code, Codex, Pi. Real terminals, with an IDE around them.

### Abertura do changelog e da página de download
> **Cockpit 2.0** turns any machine into a workspace. Open a folder over SSH and
> the terminals, file tree, editor, source control and databases run on the
> host, while your sessions outlive the client that opened them. A single curl
> turns a headless VPS into a host, an iPad becomes a client, and your notes,
> HTTP requests, boards and SQL queries are tabs next to the terminal where your
> agent works.

## Próximos passos

- Consolidar o CHANGELOG 2.0.0 (card k1) no subprojeto cockpit.
- Publicar o texto no site (plano 63, passo 5).
- Decidir canais e data do anúncio.
