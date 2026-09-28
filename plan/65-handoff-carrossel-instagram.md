# 65: Handoff para o Claude Design, carrossel de Instagram do Cockpit 2.0

Documento de entrega para quem vai desenhar. Traz formato, identidade, copy
final por slide e o que não pode aparecer. A lista de highlights vem do
[plano 64](./64-cockpit-2.0-anuncio.md).

## O produto, em uma frase

**Cockpit é um terminal que criou uma IDE em volta dos seus agentes.** Claude
Code, Codex, Pi ou qualquer outro harness rodando em terminais de verdade, na
sua máquina ou em qualquer host via SSH, com viewer, diagnostics, git,
worktrees e bancos de dados ao lado.

Público: quem já usa agentes de código no terminal todo dia e sente falta de
ver o que eles estão fazendo.

## Formato

- **Proporção 3:4** (retrato do feed do Instagram), **1080 x 1440 px**, RGB.
- **9 slides**: capa, os 7 highlights, e um de fechamento.
- Exportar PNG por slide, numerados na ordem (`01.png` a `09.png`).
- **Zona segura**: 90 px de margem em todos os lados. O Instagram corta as
  bordas na pré-visualização do feed, e o canto inferior direito é onde fica o
  indicador de carrossel, então nada essencial ali.
- Texto legível em tela de telefone: título mínimo 56 px, corpo mínimo 32 px.
  Se um slide precisa de fonte menor que isso, o texto está longo demais.

## Identidade

Vem do site (`site/src/app/globals.css`), para o carrossel e a página falarem
a mesma língua.

| Token | Valor | Uso |
|---|---|---|
| Fundo | `#000000` | base de todos os slides |
| Superfície | `#0a0a0a`, cartões em branco 2,5% a 4,5% | blocos e cartões |
| Texto | `#ffffff`, secundário `#d4d4d4`, fraco `#6b6b6b` | hierarquia |
| Acento | `#4fc3f7` (azul céu) | destaque, nunca mais que um por slide |
| Linhas | branco 10% a 16% | bordas de cartão |
| Verde ok | `#5fd38a` | só para estado positivo, se precisar |

Tipografia: **Space Grotesk** (títulos), **Hanken Grotesk** (corpo),
**JetBrains Mono** (código, caminhos de arquivo, nomes de extensão). Raios de
canto entre 12 e 34 px, como no site.

Tom visual: fundo preto de terminal, muito respiro, um único ponto de acento
por slide. Nada de gradiente colorido, nada de ilustração genérica de robô.
Quando um slide mostrar código ou saída de terminal, use mono de verdade, não
imagem falsa de código.

## Assets disponíveis

Em `site/public/`: `cockpit-hero.png`, `logo.svg`, `logo-foreground.svg`.
Em `site/public/cockpit/`: `hero-terminals.png`, `code-viewer.png`,
`database-panel.png`, `agent-diff-diagnostics.png`.

**Não existe captura de**: workspace remoto conectado, cliente Android, Galeria
e painel de bancos com o browser de Mongo/Redis. Se o slide precisar, prefira
composição tipográfica ou diagrama a inventar uma tela que não existe. O que
faltar de captura fica anotado como pendência para o Jacob fotografar.

## Os slides

Cada slide tem um título curto (o que aparece grande), uma linha de apoio e uma
sugestão visual. A sugestão é ponto de partida, não amarra.

### 01, capa
**Título**: Cockpit 2.0
**Apoio**: O terminal que criou uma IDE em volta dos seus agentes.
**Visual**: logo, fundo preto, um terminal ao fundo com opacidade baixa.
Precisa funcionar como miniatura no feed, então o título domina.

### 02, highlight 1
**Título**: Seu workspace, em qualquer máquina
**Apoio**: Abra uma pasta em outro computador e trabalhe nela como se fosse
local. Terminais, arquivos, git e bancos rodam no host. Feche o laptop, o
agente continua.
**Visual**: duas máquinas ligadas por SSH, a de cá fechada e a de lá
trabalhando. Um curl de uma linha pode aparecer em mono como selo:
`curl -fsSL .../cockpit-server.sh | bash`.

### 03, highlight 2
**Título**: O mesmo workspace, do tablet
**Apoio**: Cockpit no Android, disponível hoje. Cliente remoto puro: os agentes
rodam numa máquina de verdade enquanto você dirige do sofá.
**Visual**: tablet em paisagem com a barra de teclas (ESC, Tab, Ctrl+C, setas).
Não existe captura real ainda, então vale representação estilizada.
**Cuidado**: nunca desenhar um iPad nem escrever iOS. É Android.

### 04, highlight 3 (o slide mais importante)
**Título**: O agente faz. Você vê.
**Apoio**: A Galeria abre documentos que dão forma visual ao que o agente está
fazendo: caderno de notas, quadro kanban, diagrama Mermaid, visual HTML,
consulta de banco, requests HTTP, tarefas e layout de panes.
**Visual**: o terminal de um lado e, do outro, a aba mostrando o resultado.
É o slide que merece mais capricho e o que melhor explica o produto.
Se o carrossel puder ter um slide duplo, é este.

### 05, highlight 4
**Título**: Confie, mas verifique
**Apoio**: O agente mexeu em vinte arquivos. Leia o diff, faça stage do que
presta, descarte o resto e commite, sem sair do app. O editor mostra os erros
do language server antes de você rodar.
**Visual**: `agent-diff-diagnostics.png` existe e serve aqui.

### 06, highlight 5
**Título**: Tudo é arquivo, no seu repositório
**Apoio**: Kanban é markdown. Caderno é uma pasta de notas. Layout, tasks e
queries são texto. Versiona no git e abre em qualquer editor. Sem conta, sem
nuvem, sem lock-in.
**Visual**: os nomes de extensão em mono como protagonistas: `.kanban`,
`.notebook`, `.ckp`, `.dbq`, `.http`, `.md`.

### 07, highlight 6
**Título**: Seu agente consulta o banco, sem poder derrubá-lo
**Apoio**: Postgres, MySQL, SQL Server, SQLite, MongoDB e Redis como abas.
Read-only por padrão, e a conexão que você não quiser expor fica invisível
para a CLI.
**Visual**: `database-panel.png` existe. O conceito de permissão pode virar um
selo "read-only".

### 08, highlight 7
**Título**: Seu agente já sabe usar o Cockpit. É só pedir.
**Apoio**: Claude Code, Codex ou qualquer harness: de dentro de uma aba eles
usam a CLI interna. "Roda os testes e me mostra a saída", "anota isso no
caderno", "abre três panes, um por serviço".
**Visual**: uma frase em linguagem natural virando ação na interface. Pedidos
em português como no apoio funcionam bem aqui.

### 09, fechamento
**Título**: Baixe o Cockpit 2.0
**Apoio**: macOS, Windows, Linux e Android. Gratuito, sem conta.
**Visual**: os quatro sistemas e o endereço do site. Chamada para o link da bio.

## O que não pode aparecer

- **iPad e iOS**: não existe build distribuído. Nem no texto, nem no desenho.
- **App Store e Play Store**: as listagens ainda não saíram. É APK direto.
- **Qualquer promessa de assinatura no Windows**: segue sem code signing.
- **A aba de agente nativa, pareamento por QR, daemons, schedules ou mesh**:
  tudo isso saiu do Cockpit na 2.0 e pertence ao Remote Pi, que é outro
  produto. Se precisar citar o Remote Pi, é como projeto irmão.
- **"Remoto" no Cockpit é SSH mais `cockpit-server`**, nunca o relay do
  Remote Pi. Não misturar.
- Tela inventada: sem captura, prefira tipografia ou diagrama.

## Legenda sugerida para o post

> Cockpit 2.0 saiu.
>
> Abra uma pasta em outra máquina por SSH e trabalhe nela como se fosse local:
> terminais, arquivos, git e bancos rodam no host. Feche o laptop, o agente
> continua trabalhando lá.
>
> E o que ele faz para de ser texto correndo na tela: caderno, kanban,
> diagrama, visual HTML, tudo como aba ao lado do terminal.
>
> macOS, Windows, Linux e Android. Link na bio.

## Pendências de captura para o Jacob

Em ordem de impacto, todas precisam de máquina real:

1. Workspace remoto conectado (rail com o host, terminal rodando nele, árvore
   de arquivos do host). É a manchete da versão e não tem imagem nenhuma.
2. Cockpit no Android, em paisagem, com a barra de teclas visível.
3. A Galeria aberta, com os cards de documento.
4. Um agente escrevendo no caderno com a aba de notas ao lado, que é a prova
   visual do slide 04.
