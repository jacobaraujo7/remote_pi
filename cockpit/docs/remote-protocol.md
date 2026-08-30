# Protocolo Cockpit Remote (v1, rascunho da Wave 0)

Protocolo cliente ↔ `cockpit-server` do plano 58. Nesta wave cobre o
**handshake** e o **domínio Terminais**; arquivos, git e databases entram nas
waves seguintes com o mesmo envelope.

As mensagens são classes Dart em `packages/cockpit_protocol` — a mesma classe
serializa e desserializa nos dois lados do fio. Este documento descreve o
formato no fio para debugging e para futuros clientes.

## Transporte

- **Framing**: JSONL — um objeto JSON por linha (`\n`), UTF-8. O despacho é
  por linha, nunca por `onDone` (lição do socket da CLI interna: esperar
  `onDone` deadlocka request/response).
- **Canal**: socket local. No POSIX é um UDS no caminho anunciado; **no Windows
  é TCP no loopback**, porque o `dart:io` não implementa socket UNIX lá — o
  bind estourava e o app caía no PTY in-process. O caminho anunciado passa a
  guardar um **arquivo de rendezvous** JSON (`{"v":1,"port":…,"token":…}`), que
  faz o papel do inode: é por ele que um cliente descobre um servidor já de pé
  e o adota. Remoto = o MESMO socket tunelado por SSH (Wave 2); o protocolo não
  muda. O servidor nunca escuta em porta de rede roteável.
- **Bytes de PTY**: base64 no campo `d`. (Candidato a otimização em wave
  futura: frame binário; só se o benchmark pedir.)
- **Autenticação**: nenhuma no canal onde alcançá-lo já é credencial
  (permissão de filesystem no UDS; login SSH no túnel) — decisões G/H do plano
  58. No loopback TCP isso não vale: qualquer processo da máquina conecta,
  então o `hello` leva um **token** (`tok`) que só quem lê o arquivo de
  rendezvous conhece, e o servidor recusa o handshake sem ele.

## Envelope

```json
{"t": "<tipo>", ...campos}
```

Campos comuns: `id` = id de sessão PTY; `d` = payload base64; `off` = offset
absoluto em bytes do stream da sessão desde o spawn.

## Handshake

O cliente abre a conexão e envia `hello`; o servidor responde `hello.ack` ou
`err{code: version_mismatch}` e fecha. Toda mensagem antes do `hello` é
rejeitada com `err{code: handshake_required}`.

| Direção | Mensagem | Campos |
|---|---|---|
| C→S | `hello` | `v` (int, versão do protocolo), `client` (nome/versão), `tok` (opcional), `loc` (opcional) |
| S→C | `hello.ack` | `v`, `server` (versão do binário) |

`tok` é o token do arquivo de rendezvous, obrigatório onde o transporte é TCP
de loopback (Windows) e ausente sobre UDS/túnel SSH; token errado responde
`err{code: invalid_token}` e fecha.

`loc: true` diz "estou na mesma máquina que você" (sidecar), e não é derivável
do transporte — a ponta de um `ssh -L` também é um socket local, e ali o
servidor é remoto. Ele muda uma coisa: as PTYs de um cliente local mantêm o
`COCKPIT_STATUS_SOCK` que o cliente injetou, porque aquele socket é a via da
CLI interna (`cockpit send`, `list-tabs`, `db`) além do status de turno. Para
um cliente remoto o servidor troca esse endereço pelo do seu próprio receptor
(o socket do cliente é inalcançável do host), removendo junto as chaves do
outro transporte — o hook lê `COCKPIT_STATUS_SOCK` antes de porta+token, e uma
sobra do cliente venceria o endereço certo.

`v` é comparado por igualdade nesta fase. Incompatível → o cliente oferece
"Update server" (bootstrap pelo túnel, Wave 2).

## Domínio Terminais

Modelo: **sessões pertencem ao servidor**, não à conexão. Detach (ou queda da
conexão) não mata a sessão; reattach recupera o scrollback retido (ring
buffer de bytes crus, default 4 MiB por sessão) e continua live. O emulador
(Ghostty) vive no cliente; o servidor não interpreta os bytes.

| Direção | Mensagem | Campos | Resposta |
|---|---|---|---|
| C→S | `pty.open` | `cmd`, `args[]`, `cwd?`, `env{}?`, `rows`, `cols` | `pty.opened{id, pid}` ou `err` |
| C→S | `pty.list` | — | `pty.sessions{sessions[]}` (`{id,pid,cmd,rows,cols,len,exit?}`) |
| C→S | `pty.attach` | `id`, `from` (offset; 0 = replay do retido) | stream de `pty.output` + `pty.exited` |
| C→S | `pty.detach` | `id` | (nada; sessão segue viva) |
| C→S | `pty.input` | `id`, `d` | — |
| C→S | `pty.resize` | `id`, `rows`, `cols` | — |
| C→S | `pty.kill` | `id` | — (mata processo E descarta a sessão) |
| S→C | `pty.output` | `id`, `off`, `d` | — |
| S→C | `pty.exited` | `id`, `code` | — (scrollback segue anexável até `pty.kill`) |

Semântica do offset: `off` é a posição absoluta do primeiro byte do chunk no
stream total da sessão. No attach com `from` anterior ao retido, o primeiro
chunk chega com `off` maior que o pedido — o cliente sabe que perdeu o início.
O replay nunca duplica nem perde bytes em relação ao live (o servidor filtra
por offset na costura replay→live).

## Erros

```json
{"t": "err", "code": "<código estável>", "detail": "<texto cru>", "id": "<sessão>?"}
```

Códigos atuais: `handshake_required`, `version_mismatch`, `bad_message`,
`session_not_found`, `spawn_failed`, `internal`. `code` é contrato (a UI
traduz por enum); `detail` é texto de terceiros (errno etc.), exibido cru.

## Domínio Bancos de dados — segredos (plano 62)

Query, schema e comandos NoSQL executam **no host** (`db.query`, `db.redis`,
`db.redisMany`, `db.mongo`), e o descritor de conexão viaja em `params.conn`.

A senha **não** viaja junto. O cofre de senhas é do host — arquivo `0600` em
`~/.cockpit/db-secrets.json`, chaveado por `(raiz do workspace, nome da
conexão)` — e o cliente o alimenta por dois métodos **write-only**:

| Método | `params` | Efeito |
|---|---|---|
| `db.secretSet` | `root`, `conn`, `value` | grava/substitui a senha da conexão |
| `db.secretDelete` | `root`, `conn` | apaga a senha da conexão |
| `db.secretRename` | `root`, `from`, `to` | move a senha para o nome novo |
| `db.hostKeyTrust` | `endpoint`, `fingerprint` | confia numa host key de bastion |

`db.secretSet`/`db.secretDelete` aceitam `kind`: `password` (default) ou
`sshPassphrase` — a passphrase da chave do túnel é segredo distinto da senha do
banco, e a conexão pode ter um sem o outro.

`db.secretRename` existe porque o cliente não pode ler o segredo para regravá-lo
sob outro nome: sem ele, renomear uma conexão apagava a senha e o usuário só
descobria na query seguinte.

O conteúdo é cifrado com AES-GCM e chave fixa do produto (modelo do DBeaver).
É **ofuscação deliberada**: tira o segredo do texto claro em disco, cobrindo
vazamento acidental (backup, pasta sincronizada, `grep`, print de tela). Não
defende de quem executa como o dono da conta — a chave está no binário, e não
poderia ser diferente num servidor que sobe por SSH sem humano presente. Cofre
em claro (formato anterior) continua sendo lido; a escrita seguinte o regrava
cifrado, então não há passo de migração.

**Um cofre por máquina.** O mesmo arquivo é usado pelo app quando o workspace é
LOCAL: a chave é derivada da raiz do workspace (nunca do `workspaceId`, que é
gerado por máquina), então digitar a senha sentado no host ou a partir de um
cliente remoto grava na MESMA entrada. Era o contrário antes, e a senha
digitada no host não valia para cliente nenhum — o `cockpit-server` é headless
e nunca teve como ler o cofre do SO. O que ficou lá migra sozinho na primeira
leitura.


**Não existe `db.secretGet`, e isso é contrato, não omissão**: o cliente grava
e apaga, nunca relê. Quem lê é o servidor, ao montar a conexão.

Campos do descritor que fecham o desenho:

| Campo | Significado |
|---|---|
| `workspaceRoot` | raiz do workspace no host — primeira metade da chave do segredo |
| `connName` | nome da conexão — segunda metade |
| `storedSecret` | `true` = a senha está no cofre do host; `password` vai ausente e o servidor resolve |
| `password` | só quando `storedSecret` é `false` (conexão que optou por não guardar segredo) |

Com `storedSecret: true` e nada no cofre do host, o servidor responde
`password_required` em vez de tentar conectar sem senha — o erro do banco
("authentication failed") mandaria o usuário investigar a coisa errada. O caso
típico é conexão cadastrada antes deste plano, cuja senha ficou no cofre do
cliente que a criou.

### Túnel SSH da conexão (plano 62, onda 2)

O descritor carrega o bloco `ssh` da conexão e **quem abre o túnel é o host** —
ele é quem alcança o bastion e quem tem a chave privada. Antes o bloco não
viajava, o host recebia `host:porta` cru e discava direto: conexão com bastion
não funcionava a partir de cliente remoto.

- **Chave e passphrase são as do host.** `keyPath` resolve contra o `~` de lá; a
  passphrase sai do mesmo cofre da senha, sob `kind: sshPassphrase`.
- **Mongo vai por SOCKS**, os demais por port-forward — num replica set o driver
  descobre os membros e passa a discar os hostnames reais, furando porta fixa.
- **Host key**: o servidor não pergunta nada. Chave desconhecida vira
  `ssh_tunnel_failed` com detail `<kind>|<mensagem>`, e a mensagem traz o
  fingerprint. O cliente mostra o diálogo que já tem e confia via
  `db.hostKeyTrust` — decisão do humano no cliente, estado no host, o mesmo
  idioma do cofre. Consequência aceita: a primeira conexão a um bastion novo
  falha uma vez, de propósito.

## Aberto (para as próximas waves)

- Backpressure/coalescing de output no fio (integrar com o
  `pty_output_scheduler` de `docs/terminal-output-flow-control.md`).
- Resize com N clientes attached (política tmux a decidir).
- Frame binário para `pty.output` se o benchmark apontar o base64.
- Envelopes dos domínios Arquivos, Git e Databases.
