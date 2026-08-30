# Host Windows — preparar a máquina

Como deixar uma máquina Windows pronta para ser **host** do Cockpit (plano 61).
Do outro lado, o cliente pode ser macOS, Linux, Windows ou iPad.

Pré-requisito de produto: **o Cockpit desktop precisa estar instalado no host**.
O servidor remoto é instalado copiando o `cockpit-server-bundle` que o app já
deixa na máquina (decisão D2) — nenhum binário viaja pelo SSH. Sem o Cockpit
instalado lá, o cliente falha com "Windows mas não tem o Cockpit instalado".

## 1. Ligar o servidor SSH

O OpenSSH Server é um recurso opcional do Windows. Num PowerShell **como
administrador**:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
```

Conferir:

```powershell
Get-Service sshd            # deve estar Running
Get-NetTCPConnection -LocalPort 22 -State Listen
```

> Não é preciso trocar o `DefaultShell` para PowerShell. O Cockpit invoca
> `powershell -NoProfile -EncodedCommand` explicitamente (decisão D1), então o
> `cmd.exe` default serve — e funciona numa instalação recém-feita.

## 2. Instalar a chave pública — a pegadinha

Aqui mora o erro mais comum, e ele **falha em silêncio**.

O `sshd_config` do Windows termina com:

```
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

Ou seja: se a conta usada for **administradora** — o caso normal de uma máquina
pessoal — o OpenSSH **ignora** o `~/.ssh/authorized_keys` e lê apenas
`C:\ProgramData\ssh\administrators_authorized_keys`. Uma chave posta no lugar
"óbvio" simplesmente nunca é considerada, e o erro que aparece do outro lado é
um `Permission denied (publickey)` genérico.

Descobrir a que grupo a conta pertence:

```powershell
net localgroup Administradores   # ou "Administrators", conforme o idioma
```

### Conta administradora

```powershell
# num PowerShell COMO ADMINISTRADOR
$key = 'ssh-ed25519 AAAA... comentario'
Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value $key
```

### Conta comum

```powershell
Add-Content -Path "$env:USERPROFILE\.ssh\authorized_keys" -Value $key
```

## 3. Corrigir a ACL — o segundo silêncio

O OpenSSH **recusa** o arquivo de chaves se ele for legível por mais gente que
`SYSTEM` e `Administrators`, e também não diz isso ao cliente: a autenticação
apenas falha como se a chave não existisse. O default de herança do
`C:\ProgramData` costuma incluir `Usuários Autenticados`, então a correção quase
sempre é necessária:

```powershell
# num PowerShell COMO ADMINISTRADOR — SIDs, não nomes: os nomes são traduzidos
icacls C:\ProgramData\ssh\administrators_authorized_keys `
  /inheritance:r /grant "*S-1-5-18:(F)" /grant "*S-1-5-32-544:(F)"
```

Conferir — a lista deve ter **só** essas duas entradas:

```powershell
icacls C:\ProgramData\ssh\administrators_authorized_keys
```

> Os SIDs literais (`*S-1-5-18` = SYSTEM, `*S-1-5-32-544` = Administrators)
> evitam o problema de o `icacls` não reconhecer `BUILTIN\Administradores` num
> Windows em português.

## 4. Verificar de ponta a ponta

Da máquina cliente:

```bash
ssh -o BatchMode=yes usuario@host "echo OK"
```

`BatchMode=yes` é o mesmo modo que o Cockpit usa: ele proíbe qualquer pergunta
interativa, então se cair em pedido de senha é porque a chave **não** está sendo
aceita — volte aos passos 2 e 3.

## 5. Diagnóstico quando não funciona

| Sintoma | Causa provável |
|---|---|
| `Permission denied (publickey)` | Chave no arquivo errado (passo 2) ou ACL frouxa (passo 3) |
| `Connection refused` | `sshd` parado, ou firewall bloqueando a 22 |
| Pede senha mesmo com chave | Mesma coisa do primeiro caso — a chave está sendo ignorada |
| Conecta, mas o Cockpit diz que não achou o Cockpit no host | O app não está instalado no host (ver pré-requisito no topo) |

Log do servidor, quando nada mais explicar:

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 30 |
  Format-List TimeCreated, Message
```

## Notas de arquitetura (por que é assim)

- **O servidor escuta em loopback, nunca na rede.** No Windows o `dart:io` não
  tem socket UNIX, então o `cockpit-server` escuta numa porta TCP de loopback
  efêmera e anuncia porta + token num arquivo de rendezvous
  (`~/.cockpit/cockpit-server.sock`, que ali é um JSON, não um socket). O acesso
  de fora é sempre pelo túnel SSH — a porta não é exposta.
- **O token existe porque loopback não protege.** Uma porta de loopback aceita
  conexão de qualquer processo da máquina, enquanto um socket UNIX já nasce
  protegido pelas permissões do `~/.cockpit`. O token viaja no handshake e o
  servidor recusa sem ele.
- **O servidor é iniciado por WMI, não por `Start-Process`.** A sessão do `sshd`
  no Windows roda dentro de um Job Object com kill-on-close: todo processo filho
  morre quando a sessão SSH termina — não existe `nohup` por ali. O
  `Win32_Process.Create` faz o `WmiPrvSE` criar o processo fora desse job, e por
  isso ele sobrevive. Efeito colateral: o servidor roda na **sessão 0**.
