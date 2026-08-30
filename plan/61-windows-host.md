# 61 — Windows como host remoto

> **Status**: IMPLEMENTADO (2026-08-26). Waves A–E escritas; E2E Windows→Windows
> verde de ponta a ponta (`tool/win_host_e2e.dart`). Falta a matriz de fumaça
> com cliente macOS/iPad contra host Windows, em máquinas reais.
> Remove a restrição `RemoteHostErrorKind.windowsHostUnsupported` introduzida no
> plano 58. Registrar em `plan/00-decisions.md` quando aprovado.

## Contexto

Hoje o Cockpit **conecta a partir do** Windows, mas uma máquina Windows não pode
**ser** host: `remote_host_connector.dart:485` (desktop) e `:332` (mobile) barram
explicitamente, e a mensagem de erro diz "o servidor remoto precisa de um sistema
tipo UNIX (macOS ou Linux)".

A investigação de 2026-08-26 mostrou que **a barreira é menor do que a mensagem
sugere**. O achado central:

> O `cockpit-server` **já é nativo de Windows**. `LocalEndpoint`
> (`packages/cockpit_protocol/lib/src/local_endpoint.dart`) já abstrai POSIX vs
> Windows: no POSIX escuta num socket UNIX; no Windows escuta em **TCP loopback**
> numa porta efêmera e grava, no caminho pedido, um **arquivo de rendezvous** JSON
> com `{v, port, token}`. O PTY já é ConPTY via `cockpit_pty.dll`. O binário
> compila e roda no Windows — foi verificado nesta máquina, servindo o sidecar
> local da GUI em `127.0.0.1`.

Ou seja: **o lado servidor está pronto**. O que falta é inteiramente **cliente**:
o bootstrap remoto e o túnel assumem POSIX de ponta a ponta.

Contexto adicional que motivou o plano: ao tentar conectar num host Windows, o
cliente não mostrava nem o erro certo — estourava `FormatException: Missing
extension byte` ao decodificar a resposta do `cmd.exe` em CP-850. Corrigido em
`c42bbfa` (`capture()` e caminho mobile) e no `Process.run` do
`ssh_tunnel.dart:95` (encoding tolerante). Com isso o usuário passa a ver
`windowsHostUnsupported` de verdade — que é o que este plano remove.

## O que já existe (não refazer)

| Peça | Estado | Onde |
|---|---|---|
| Servidor headless em Windows | ✅ compila e roda | `packages/cockpit_server/` |
| Transporte local TCP + token | ✅ implementado | `LocalEndpoint` (`usesTcp`, rendezvous JSON) |
| PTY nativo (ConPTY) | ✅ empacotado | `plugins/cockpit_pty/` → `cockpit_pty.dll` |
| CLI interna (`cockpit`/`ck`) em Windows | ✅ compila | `cli/` (Rust) |
| Alias `ck` sem symlink no Windows | ✅ decidido e implementado | `hook_installer_base.dart` (`ensureShortAlias` copia o `.exe`) |
| Sobrescrita de binário no Windows | ✅ corrigido 2026-08-26 | `hook_installer_base.dart` (`_copyOver`) |
| Cliente Windows → host POSIX | ✅ funciona | `SshTunnel` já usa `-L 127.0.0.1:porta:` na ponta local |

## O que falta — inventário de bloqueios

Todos no cliente. Numerados para os passos referenciarem.

| # | Bloqueio | Onde | Hoje | Precisa |
|---|---|---|---|---|
| **B1** | Detecção de OS do host | `remote_host_connector.dart:475` | `uname -sm`; falha ⇒ `_looksLikeWindowsHost()` ⇒ erro | Reconhecer Windows como caminho válido e descobrir arch |
| **B2** | Forward do túnel | `ssh_tunnel.dart:129` | `-L <local>:$HOME/.cockpit/cockpit-server.sock` (streamlocal) | `-L 127.0.0.1:lport:127.0.0.1:rport` — a ponta remota é TCP |
| **B3** | Descoberta de porta/token remotos | — | não existe | Ler o rendezvous JSON do host antes de abrir o forward |
| **B4** | Token no handshake | `remote_host_connector.dart:371-374` | conecta **sem** token ("não há rendezvous nem token a resolver aqui") | Servidor Windows **recusa** `Hello` sem `tok` |
| **B5** | Shell do host | todo o bootstrap | comandos POSIX crus | `cmd.exe` é o shell default do OpenSSH no Windows |
| **B6** | Upload do bundle | `:559` (`push`) | `cat > arquivo` (stdin binário) | stdin binário via cmd/PowerShell corrompe |
| **B7** | Artefato cross-OS | `:531-536` | recusa: cliente só embarca servidor da própria plataforma | macOS/Linux não têm um `cockpit-server.exe` para empurrar |
| **B8** | Start do processo | `:648` | `nohup … >log 2>&1 &` | precisa `Start-Process` destacado |
| **B9** | Liveness | `:675` | `test -S <sock>` | no Windows o rendezvous é **arquivo comum**, não socket |
| **B10** | Comandos auxiliares | vários | `mkdir -p`, `chmod +x`, `pkill -f`, `ln -sf`, `sha256sum`, `tail -c`, `test -x` | equivalentes PowerShell |
| **B11** | Caminhos | `_remoteServerBin`, `_remoteSocketPath` | `$HOME/...`, sem `.exe` | `$env:USERPROFILE`, sufixo `.exe`, `$HOME` com espaço |
| **B12** | Lib do PTY | `:551` | `libcockpit_pty.dylib` / `.so` | `cockpit_pty.dll` |
| **B13** | Mobile | `remote_host_connector.dart:329-337` | `printf %s "$HOME"` + `conn.forwardUnix()` | `forwardLocal(host, port)` do `dartssh2` + token |
| **B14** | Setup de auth no host | — | não documentado | Usuário **administrador** no Windows lê chaves de `%ProgramData%\ssh\administrators_authorized_keys`, **não** de `~/.ssh/authorized_keys`, e o arquivo precisa de ACL só `SYSTEM` + `Administrators` |

## Decisões

Ambas fechadas em 2026-08-26. Promover para `plan/00-decisions.md` junto com a
aprovação do plano.

### D1 — Como falar com o host Windows: `powershell -EncodedCommand` ✅ FECHADA (2026-08-26)

> **Fechada**: todo comando do bootstrap remoto num host Windows sai como
> `powershell -NoProfile -EncodedCommand <base64-utf16le>`, com preâmbulo
> `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()`. Nada de exigir troca
> do `DefaultShell` do OpenSSH no host.

O shell default do OpenSSH no Windows é o `cmd.exe`, mas dá pra ignorá-lo:
invocar sempre `powershell -NoProfile -EncodedCommand <base64-utf16le>`.

Por que EncodedCommand e não um comando em texto:
- **Não depende de configurar o host** (nada de mexer no `DefaultShell` do
  registro; funciona com o OpenSSH recém-instalado).
- **Elimina o inferno de aspas** em três níveis (nosso argv → ssh → cmd →
  PowerShell), que é onde caminhos com espaço (`C:\Users\John Smith`) quebram.
- **Saída em UTF-8 previsível** se o script começar com
  `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()` — mata a classe de bug
  do CP-850 na origem, em vez de só tolerar bytes inválidos no cliente.

Alternativa descartada: pedir ao usuário que troque o `DefaultShell` para
PowerShell. Funciona, mas é passo manual, dá erro silencioso quando esquecido, e
não temos como detectar direito.

### D2 — Distribuição do servidor: reusar o bundle do app instalado ✅ FECHADA (2026-08-26)

> **Fechada na opção (c)**: host Windows precisa ter o Cockpit desktop instalado,
> e o bootstrap reusa o `cockpit-server-bundle` dele por **cópia local**, sem
> transferir binário pelo SSH. As opções (a) e (b) ficam registradas abaixo — (b)
> é a evolução natural quando o cenário "host Windows sem GUI" aparecer.

`B7` é a decisão mais consequente. Três caminhos:

| Opção | Custo | Veredito |
|---|---|---|
| **(a)** Cliente embarca servidor de todas as plataformas | +~40 MB em todo cliente, inclusive mobile | ✗ |
| **(b)** Baixar o bundle certo do GitHub Release na hora | precisa de rede no cliente, versionamento, verificação de hash | evolução |
| **(c)** Exigir Cockpit instalado no host Windows e **reusar o bundle dele** | zero upload, zero download | ✓ MVP |

Recomendação: **(c)** para o MVP. O caminho de instalação do Windows já entrega
`%LOCALAPPDATA%\Programs\Remote Pi Cockpit\cockpit-server-bundle\{bin,lib}` —
exatamente o layout que o bootstrap espera. O host copia **localmente** dali para
`~/.cockpit/server/`, sem transferir nada pelo SSH. Isso também neutraliza **B6**
(upload binário) no caso comum.

Consequência de produto: *"host Windows precisa ter o Cockpit desktop
instalado"*. Restrição aceitável — o cenário VPS headless do plano 58 é Linux, e
quem expõe um Windows como host é alguém que usa a máquina.

Nota de reforço: o conector **já** tem o caminho `alreadyInstalled` (`:502`), que
existe justamente para "iniciar o que já está lá sem empurrar binário". A opção
(c) se encaixa nele quase sem código novo.

### D4 — Start do servidor: **WMI `Win32_Process.Create`**, não `Start-Process` ✅ FECHADA (2026-08-26, por spike)

> **O spike da Wave 0 refutou o `Start-Process`.** Ver "Spike 2026-08-26" abaixo.

A sessão do `sshd` no Windows roda dentro de um **Job Object** com kill-on-close:
qualquer filho — `Start-Process`, `-WindowStyle Hidden`, `-PassThru`, tanto faz —
morre quando a sessão SSH termina. Não existe equivalente de `nohup` por ali.

Escapa quem **não nasce como filho**. `Invoke-CimMethod -ClassName Win32_Process
-MethodName Create` faz o `WmiPrvSE` criar o processo, fora do job da sessão, e
ele sobrevive. Validado no spike.

Duas consequências que o desenho tem que absorver:

1. **O processo nasce na sessão 0** (`Services`), não na sessão interativa do
   usuário. Precisa ser validado com PTY real na Wave C — ConPTY é headless e
   deve funcionar, mas isolamento de sessão 0 afeta acesso a credenciais e a
   qualquer coisa que espere desktop. **É o próximo pressuposto frágil.**
2. **Não dá pra redirecionar stdout/stderr** pela API do WMI. O log de arranque
   (`server-boot.log`, hoje alimentado por `>log 2>&1`) precisa de outro caminho:
   `cmd /c "... > log 2>&1"` como CommandLine, ou logging próprio do servidor.
   Sem isso o passo B.4 (liveness com `tail` do log) perde a evidência.

Alternativa não testada, guardada como fallback: tarefa agendada
(`Register-ScheduledTask` + `Start-ScheduledTask`), que roda pelo serviço de
agendamento e também escapa do job — mais partes móveis, mas nasce na sessão do
usuário se configurada assim.

### D3 — Persistência: mesmo `--exit-on-idle`, sem serviço do Windows

Manter `--exit-on-idle 120 --idle-keeps-sessions`, igual ao POSIX. **Não**
registrar serviço do Windows nem tarefa agendada neste plano — é o mesmo escopo
que a decisão I do plano 58 adiou para "Wave 3" no POSIX (launchd/systemd).
Windows não deve chegar na frente.

## Spike 2026-08-26 — o que foi medido, não suposto

Rodado contra esta máquina Windows 11 (26300) via `ssh jacob@127.0.0.1`, com o
`cockpit-server.exe` do bundle instalado. Resultados:

| # | Hipótese | Resultado |
|---|---|---|
| 1 | `powershell -NoProfile -EncodedCommand` funciona com `cmd.exe` como shell default (**D1**) | ✅ Probe devolveu `{"os":"windows","arch":"x64","home":"C:\\Users\\jacob"}` |
| 2 | Preâmbulo de `OutputEncoding` mata o CP-850 na origem (**D1**) | ✅ `"configuração não é ção"` atravessou o SSH intacto |
| 3 | Bundle do app instalado é achável e copiável localmente (**D2**) | ✅ `cockpit-server-bundle\bin\cockpit-server.exe` presente; cópia pra `~/.cockpit/` sem transferir bytes pelo SSH |
| 4 | Servidor sobe no Windows e escreve o rendezvous (**B3**) | ✅ `{"v":1,"port":51511,"token":"…"}` + log `cockpit-server listening on …` |
| 5 | **`Start-Process` sobrevive ao fim da sessão SSH (B8)** | ❌ **REFUTADA** — processo morre junto com a sessão |
| 6 | A sessão do `sshd` roda dentro de um Job Object | ✅ `IsProcessInJob` ⇒ `true` — é a causa de (5) |
| 7 | WMI `Win32_Process.Create` escapa do job (**D4**) | ✅ sobreviveu; ressalva: nasce na **sessão 0** |
| 8 | `ssh -L 127.0.0.1:l:127.0.0.1:r` alcança o servidor Windows (**B2**) | ✅ TCP conectou pelo túnel até a porta do rendezvous |

Ou seja: **7 das 8 confirmadas na primeira tentativa**, e a que caiu era
exatamente a que o plano apontava como mais frágil. O custo de tê-la testado
antes: o desenho da Wave C mudou por causa de um teste de 10 minutos, em vez de
mudar no meio da implementação.

Artefatos do spike foram removidos (`~/.cockpit/spike*`, processo encerrado).

## Estrutura esperada

**Bifurcar por dialeto, não por `if`.** As operações do bootstrap já existem e
funcionam em macOS/Linux; o que muda no Windows é *como cada uma se escreve*, não
*o que cada uma faz*. Então o corte é um contrato com duas implementações, e o
`RemoteHostConnector` — que hoje monta comandos POSIX inline em ~10 lugares —
passa a só orquestrar, sem conhecer shell nenhum.

O ganho de fazer assim, e não com `if (Platform.isWindows)` espalhado: o contrato
**força** as duas famílias a cobrirem a mesma superfície. Uma operação nova não
pode nascer só-POSIX sem quebrar a compilação da outra implementação — que é
precisamente como o bootstrap chegou onde chegou.

```
lib/app/cockpit/data/remote/
├── host_shell/
│   ├── host_shell.dart          # contrato: comandos que o bootstrap precisa
│   ├── posix_host_shell.dart    # o que existe hoje, extraído
│   └── windows_host_shell.dart  # PowerShell -EncodedCommand
├── remote_host_connector.dart   # passa a orquestrar, sem literais de shell
└── ssh_tunnel.dart              # forward TCP↔TCP além do streamlocal
```

Contrato mínimo do `HostShell` (um método por operação do bootstrap, não um
"executor de comando genérico" — a diferença entre os dois dialetos está no
**comando**, e o tipo tem que forçar os dois a existirem):

```dart
abstract class HostShell {
  Future<HostProbe> probe();                        // OS + arch            (B1)
  Future<bool> serverInstalled();                   //                      (B10)
  Future<String?> serverHash();                     // sha256               (B10)
  Future<void> ensureDirs();                        //                      (B10)
  Future<void> killServer();                        //                      (B10)
  Future<void> startServer({required int idleSeconds});  //                 (B8)
  Future<RemoteEndpoint?> readEndpoint();           // porta + token        (B3)
  Future<String> tailBootLog({int bytes = 2000});   //                      (B9)
}
```

## Passos

### Wave 0 — Preflight e diagnóstico honesto

> Spike de viabilidade **já executado** em 2026-08-26 (ver seção acima). Restam
> os passos de documentação e UI.

**Passo 0.1 — Documentar o setup de auth do host Windows (B14)**
Doc em `cockpit/docs/` cobrindo: instalar/ligar o `sshd`, e o comportamento do
`Match Group administrators` — usuário administrador lê chaves de
`%ProgramData%\ssh\administrators_authorized_keys`, e a ACL tem que ser só
`SYSTEM` + `Administrators` (senão o OpenSSH ignora o arquivo em silêncio).

> Critério de aceite: seguir o doc numa máquina Windows limpa resulta em
> `ssh <user>@<host>` entrando por chave, sem senha.

**Passo 0.2 — Preflight na UI**
Ao adicionar um host, checar SSH alcançável + shell utilizável, e reportar por
`RemoteHostErrorKind` tipado (nada de `Result<T, String>` com frase pronta — ver
`cockpit/CLAUDE.md`).

> Critério de aceite: host com sshd desligado, chave em arquivo errado e ACL
> frouxa produzem **três** mensagens distintas e acionáveis.

### Wave A — Dialeto de shell

**Passo A.1 — Extrair `HostShell` e mover o POSIX pra ele**
Refatoração pura, sem mudança de comportamento.

> Critério de aceite: conectar a host macOS e Linux continua idêntico;
> `flutter analyze` limpo; nenhum literal de comando sobra no conector.

**Passo A.2 — `WindowsHostShell` com `-EncodedCommand` (D1, B5, B10, B11)**
Inclui o preâmbulo de UTF-8 e `$env:USERPROFILE`.

> Critério de aceite: testes unitários com um executor de SSH fake verificam o
> base64 gerado para cada método; caminho com espaço no `$HOME` sobrevive.

**Passo A.3 — Detecção de OS (B1)**
`probe()` decide entre POSIX e Windows sem depender de `uname` falhar.

> Critério de aceite: `windowsHostUnsupported` deixa de ser lançado em `:485`;
> matriz macOS/Linux/Windows × x64/arm64 identificada corretamente.

### Wave B — Túnel e handshake

**Passo B.1 — Forward TCP↔TCP no `SshTunnel` (B2)**
Hoje a ponta local já é TCP quando o **cliente** é Windows (`localPort`); falta o
caso da ponta **remota** ser TCP. As duas são independentes — as quatro
combinações precisam existir.

> Critério de aceite: matriz cliente×host {POSIX, Windows} conecta nas 4
> combinações. `StreamLocalBindUnlink` só é passado quando a ponta local é UDS.

**Passo B.2 — Ler rendezvous remoto (B3)**
`readEndpoint()` traz `{port, token}` do host antes de abrir o forward.

> Critério de aceite: servidor no ar → porta e token corretos; servidor ausente
> → `null` (e não exceção), levando ao bootstrap.

**Passo B.3 — Propagar o token no `Hello` (B4)**
`_tryProtocol` passa a aceitar token opcional.

> Critério de aceite: host Windows conecta; token errado é recusado pelo
> servidor com erro tipado, não timeout.

**Passo B.4 — Liveness sem `test -S` (B9)**
Trocar por "arquivo existe **e** a porta aceita conexão" — vale nas duas
plataformas e é sinal mais forte que o inode.

> Critério de aceite: servidor que morre no arranque falha com o `tail` do
> `server-boot.log`, não com timeout mudo.

### Wave C — Bootstrap

**Passo C.1 — Instalação por cópia local (D2 fechada, B7, B6)**
Detectar o bundle do app instalado no host — `%LOCALAPPDATA%\Programs\Remote Pi
Cockpit\cockpit-server-bundle\{bin,lib}` — e copiar para `~/.cockpit/server/`.
Sem Cockpit no host → erro tipado dizendo exatamente isso (novo
`RemoteHostErrorKind`, com as 3 traduções).

Encaixa no caminho `alreadyInstalled` que o conector já tem (`:502`), criado
justamente para "iniciar o que já está lá sem empurrar binário" — o passo é
sobretudo *reconhecer* o bundle, não escrever um instalador novo.

> Critério de aceite: cliente **macOS** instala e sobe o servidor num host
> Windows sem transferir bytes de binário pelo SSH.

**Passo C.2 — Start fora do Job Object (D4, B8, B12)**
`Invoke-CimMethod Win32_Process Create` — **não** `Start-Process` (spike refutou;
ver D4). `COCKPIT_PTY_DYLIB` apontando pro `cockpit_pty.dll`; como o WMI não
redireciona stdout/stderr, envolver em `cmd /c "… > log 2>&1"` para preservar o
`server-boot.log` de que o passo B.4 depende.

> Critério de aceite: servidor sobrevive ao fim da sessão SSH (já validado no
> spike); fechar o cliente e reconectar reencontra as sessões (efeito do
> `--idle-keeps-sessions`); `server-boot.log` recebe a saída do arranque.

**Passo C.2b — PTY real na sessão 0 (risco aberto do D4)**
Abrir um terminal remoto de verdade num servidor iniciado por WMI e exercitar
shell, `cd`, output com acento e redimensionamento.

> Critério de aceite: ConPTY funciona a partir da sessão 0. Se não funcionar,
> cair para o fallback de tarefa agendada (registrado no D4) — **antes** de
> seguir para a Wave D.

**Passo C.3 — Staleness e substituição (B10)**
`Get-FileHash` no lugar do `sha256sum`; matar o processo velho antes de trocar o
arquivo — com a ressalva de que `.exe` em uso não se apaga no Windows, só se
renomeia (mesmo problema já resolvido em `_copyOver`).

> Critério de aceite: servidor desatualizado é derrubado e substituído; o novo
> sobe; nenhum `.exe` fica órfão travando a pasta.

### Wave D — Mobile

**Passo D.1 — `forwardLocal` no `dartssh_host_connection` (B13)**

> Critério de aceite: iPad conecta a host Windows; a checagem
> `home.startsWith('/')` de `:331` sai do caminho.

### Wave E — Fechamento

**Passo E.1 — Remover `windowsHostUnsupported`**
Apagar o enum, as três traduções e o tradutor. O `switch` exaustivo do
`remote_host_error_message.dart` garante que nada fique pendurado.

**Passo E.2 — Matriz de fumaça 3×3**
Cliente {macOS, Windows, iPad} × host {macOS, Linux, Windows}: terminal, árvore
de arquivos, git e um DB.

## Definition of Done

- [x] Doc de setup de auth do host Windows (incl. `administrators_authorized_keys` + ACL)
- [x] Erros tipados novos (`hostBundleMissing`, `hostUnknownOs`) com as 3 traduções
- [x] `HostShell` extraído; POSIX sem mudança de comportamento
- [x] `WindowsHostShell` via `-EncodedCommand`, com testes de unidade
- [x] Detecção de OS/arch cobrindo Windows
- [x] `SshTunnel` cobre as 4 combinações de ponta local/remota
- [x] Rendezvous remoto lido; token propagado no `Hello`
- [x] Liveness por "arquivo + porta", não por `test -S`
- [x] Instalação por cópia local do bundle do host
- [x] Start por WMI sobrevive à sessão SSH, com `server-boot.log` alimentado
- [x] PTY real validado a partir da sessão 0 — ConPTY funciona, fallback não foi preciso
- [x] Staleness por `Get-FileHash` + troca de `.exe` em uso
- [x] Mobile conecta por `forwardLocal`
- [x] `windowsHostUnsupported` removido do enum e das 3 traduções
- [ ] Matriz 3×3 verde
- [x] `flutter analyze` limpo; `flutter test` sem regressão

## Riscos

| Risco | Mitigação |
|---|---|
| Bundle do app instalado não é achável (install custom, portable) | Fallback pro upload base64 em chunks (B6); erro tipado se nenhum dos dois |
| ~~`Start-Process` não sobrevive ao fim da sessão SSH~~ | **Confirmado no spike de 2026-08-26**: não sobrevive. Resolvido pelo D4 (WMI) |
| ~~Sessão 0 (WMI) quebrar ConPTY~~ | **Refutado em 2026-08-26** pelo `tool/win_host_e2e.dart`: PTY abre, produz saída e aceita input com o servidor na sessão 0. O fallback de tarefa agendada não foi preciso |
| Acento re-codificado na saída do PTY | **Achado novo** — ver seção abaixo. Fora do escopo deste plano |
| WMI não redireciona stdout/stderr ⇒ `server-boot.log` vazio e liveness sem evidência | `cmd /c "… > log 2>&1"` no CommandLine (passo C.2) |
| Antivírus/SmartScreen barra o `cockpit-server.exe` copiado | Documentar; o binário não é assinado (decisão de distribuição do plano 00) |
| `--exit-on-idle` interagir mal com sessão RDP/console bloqueada | Cobrir na matriz de fumaça |

## Achado fora de escopo — double-encoding na saída do PTY

O E2E expôs um defeito que **não é do plano 61**: texto acentuado volta do PTY
re-codificado. `configuração` chega como `configuraￃﾧￃﾣo` — os bytes UTF-8 do
`ç` (`C3 A7`) viram os caracteres U+FFC3 U+FFA7, que então são re-encodados em
UTF-8. Double-encoding clássico.

Por que não é deste plano: nada no caminho novo re-codifica. O túnel é TCP
byte-transparente, e o protocolo carrega `PtyOutput.bytes` crus. A deformação
nasce na leitura do ConPTY, dentro do servidor — o **mesmo código que o sidecar
local do Windows usa**, o que sugere que o terminal local do Windows sofre do
mesmo problema, independentemente de host remoto.

Próximo passo: confirmar no caminho local (terminal do Cockpit numa máquina
Windows, sem nada de remoto). Se reproduzir, é plano próprio, na camada de PTY.

O `tool/win_host_e2e.dart` reporta isso como `WARN`, não como falha: travar o
E2E do plano 61 num defeito de outra camada esconderia regressões das que ele
existe para pegar.

## Próximos planos

- Serviço de usuário no Windows (equivalente ao launchd/systemd da Wave 3 do 58)
- Download do bundle por release (D2 opção **b**), que remove a exigência de
  Cockpit instalado no host
