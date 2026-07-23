#!/usr/bin/env bash
set -euo pipefail

# Despacha uma tarefa orquestrada pra um pane do Cockpit (via a CLI interna
# `cockpit`). Espelha scripts/cmux-dispatch.sh, mas usa o transporte do
# Cockpit em vez do cmux. Sempre prefixa o prompt com [ORCH:<task-id>] —
# esse é o gatilho que faz os CLAUDE.md de subprojeto lerem
# .orchestration/INSTRUCTIONS.md e aplicarem o modo orquestrado
# (cwd-only, sem commit, grava result file no fim).
#
# Uso:
#   scripts/cockpit-dispatch.sh [--wait [--timeout <s>]] <Pane|tab-id> <task-id> <prompt>
#
# Exemplos:
#   scripts/cockpit-dispatch.sh Extension 03-ts-codec "Implemente passo 3 do plan/03-protocol.md"
#   scripts/cockpit-dispatch.sh --wait Extension 03-ts-codec "Implemente..."
#   scripts/cockpit-dispatch.sh t319 quick-check "roda os testes"   # tab-id direto
#
# Argumentos:
#   --wait              (opcional) bloqueia até o agente concluir. Detecção
#                       primária: mtime de .orchestration/results/<task-id>.md
#                       muda + linha **Status**: presente (contrato do
#                       INSTRUCTIONS.md). Reforço: se o pane virar
#                       working=false depois de ter ficado working=true, também
#                       encerra (sinal nativo do Cockpit, cobre agente que
#                       esqueceu o result file).
#   --timeout <s>       (opcional, default 1800) timeout do --wait
#   --poll-interval <s> (opcional, default 2) intervalo entre checagens
#   <Label|tab-id>      Label manual do pane (match exato, case-insensitive) OU
#                       um tab-id literal do Cockpit (ex: t319). O label é o
#                       campo estável app-managed (`label` no `list-panes
#                       --json`), setado por duplo-clique / botão-direito na tab
#                       e imune à sobrescrita do OSC-title do claude. NÃO usamos
#                       title (dinâmico), workspaceId (raiz igual pra todos) nem
#                       cwd (volátil). Labels devem ser únicos; colisão = erro.
#   <task-id>           ID curto (kebab/snake: a-z A-Z 0-9 . _ -)
#   <prompt>            texto do prompt (aspas se tiver espaços)
#
# Pra conversa fora do protocolo (perguntas, debug, retomar claude), use
# `cockpit send` direto. Esse script existe pra não esquecer o marker.

usage() {
  awk '
    /^# Despacha/ { on = 1 }
    on {
      if (!/^#/) exit
      sub(/^# /, "")
      sub(/^#$/, "")
      print
    }
  ' "$0"
}

wait_flag=0
wait_timeout=1800
poll_interval=2

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --wait)           wait_flag=1; shift ;;
    --timeout)        wait_timeout="${2:-}"; shift 2 || { echo "erro: --timeout precisa de valor" >&2; exit 2; } ;;
    --poll-interval)  poll_interval="${2:-}"; shift 2 || { echo "erro: --poll-interval precisa de valor" >&2; exit 2; } ;;
    --)               shift; break ;;
    -*)               echo "erro: flag desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *)                break ;;
  esac
done

if [ $# -lt 3 ]; then
  usage >&2
  echo >&2
  echo "erro: argumentos insuficientes (esperado 3 posicionais, recebido $#)" >&2
  exit 2
fi

target="$1"
task_id="$2"
shift 2
prompt="$*"

if [[ ! "$task_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "erro: task-id '$task_id' inválido (use a-z A-Z 0-9 . _ -)" >&2
  exit 2
fi

if [ -z "$prompt" ]; then
  echo "erro: prompt vazio" >&2
  exit 2
fi

command -v cockpit >/dev/null || {
  echo "erro: 'cockpit' não encontrado no PATH — você está dentro de um pane do Cockpit?" >&2
  exit 1
}

panes_json=$(cockpit list-panes --json 2>/dev/null) || {
  echo "erro: falha ao listar panes (COCKPIT_STATUS_SOCK unset? fora de pane Cockpit?)" >&2
  exit 1
}

# Resolve o tab-id alvo. Se <target> já é um tab-id literal (t<N>), usa direto.
# Senão, trata como nome de subprojeto e casa pelo sufixo do workspaceId.
if [[ "$target" =~ ^t[0-9]+$ ]]; then
  tab_id="$target"
  # valida que o pane existe e é terminal
  ok=$(printf '%s' "$panes_json" | python3 -c '
import json,sys
tid=sys.argv[1]
for p in json.load(sys.stdin):
    if p.get("id")==tid:
        print("term" if p.get("kind")=="terminal" else "notterm"); sys.exit(0)
print("missing")
' "$tab_id")
  case "$ok" in
    term)    ;;
    notterm) echo "erro: pane '$tab_id' não é terminal" >&2; exit 3 ;;
    *)       echo "erro: pane '$tab_id' não existe (id defasado? app reiniciou)" >&2; exit 3 ;;
  esac
else
  # nome -> label manual do pane (match EXATO, case-insensitive). O label é o
  # campo estável app-managed setado pelo usuário (duplo-clique / botão-direito
  # na tab), imune à sobrescrita do OSC-title do claude. NÃO usamos title
  # (dinâmico, o claude reescreve) nem workspaceId (raiz do workspace, igual pra
  # todos num monorepo) nem cwd (volátil, o usuário faz cd).
  tab_id=$(printf '%s' "$panes_json" | python3 -c '
import json,sys
want=sys.argv[1].lower()
matches=[p for p in json.load(sys.stdin)
         if p.get("kind")=="terminal"
         and p.get("label") and str(p["label"]).lower()==want]
if len(matches)==1:
    print(matches[0]["id"])
elif len(matches)==0:
    print("NONE")
else:
    print("MULTI:"+",".join(m["id"] for m in matches))
' "$target")
  case "$tab_id" in
    NONE)
      echo "erro: nenhum pane terminal com label '$target'." >&2
      echo "      panes atuais (id | label | title dinâmico):" >&2
      printf '%s' "$panes_json" | python3 -c 'import json,sys;[print("       ",p["id"],"|",p.get("label"),"|",p.get("title")) for p in json.load(sys.stdin) if p.get("kind")=="terminal"]' >&2
      echo "      dica: dê um nome ao pane (duplo-clique na tab) ou passe o tab-id direto (ex: t319)." >&2
      echo "      obs: se o campo 'label' não aparece, o Cockpit em execução ainda não tem a feature — rebuild/relançar." >&2
      exit 3 ;;
    MULTI:*)
      echo "erro: múltiplos panes com label '$target': ${tab_id#MULTI:} — labels devem ser únicos; renomeie ou use tab-id direto." >&2
      exit 3 ;;
  esac
fi

# Push de conclusão (worker → orquestrador): se estamos dentro de um pane do
# Cockpit, COCKPIT_PANE_ID é o nosso próprio tab-id — embuta-o num segundo
# marker. O INSTRUCTIONS.md instrui o worker a mandar `cockpit send --tab-id
# <id> "[ORCH:<task-id>] <status> — <resumo>"` ao terminar, além do result
# file (que continua sendo o contrato; o --wait segue funcionando como
# fallback pra worker que esquecer o push).
reply_marker=""
if [ -n "${COCKPIT_PANE_ID:-}" ]; then
  reply_marker="[ORCH-REPLY:${COCKPIT_PANE_ID}] "
fi

full_prompt="[ORCH:${task_id}] ${reply_marker}${prompt}"

# Snapshot do mtime do result file ANTES do dispatch. Detecta conclusão por
# mudança vs snapshot, então re-dispatch do mesmo task-id também é esperado.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
result_file="$REPO_ROOT/.orchestration/results/${task_id}.md"
before_mtime=$(stat -f %m "$result_file" 2>/dev/null || stat -c %Y "$result_file" 2>/dev/null || echo 0)

cockpit send --tab-id "$tab_id" "$full_prompt" >/dev/null

# Pausa pro TUI do claude terminar de processar o paste antes do Enter — sem
# isso, prompts grandes racing com o bracketed-paste fazem o Enter virar
# newline no buffer em vez de submit.
sleep 0.4

cockpit send-key --tab-id "$tab_id" Enter >/dev/null

printf "ok  %-10s %s\n     [ORCH:%s] %s\n" "$target" "$tab_id" "$task_id" "$prompt"

if [ "$wait_flag" -eq 1 ]; then
  echo "aguardando $result_file OU pane $tab_id ficar ocioso (poll ${poll_interval}s, timeout ${wait_timeout}s)..." >&2

  start_ts=$(date +%s)
  saw_working=0
  while :; do
    # 1) primário: result file mudou + tem Status:
    cur_mtime=$(stat -f %m "$result_file" 2>/dev/null || stat -c %Y "$result_file" 2>/dev/null || echo 0)
    if [ "$cur_mtime" -gt "$before_mtime" ] \
       && grep -qE '^\*?\*?Status\*?\*?:' "$result_file" 2>/dev/null; then
      elapsed=$(( $(date +%s) - start_ts ))
      echo "ok  $target completou em ${elapsed}s (result file: $result_file)" >&2
      exit 0
    fi

    # 2) reforço nativo Cockpit: working true -> false. Só conta como fim
    # depois de ter visto working=true ao menos uma vez (evita disparar no
    # arranque, antes do claude começar a processar).
    working=$(cockpit list-panes --json 2>/dev/null | python3 -c '
import json,sys
tid=sys.argv[1]
for p in json.load(sys.stdin):
    if p.get("id")==tid:
        print("1" if p.get("working") else "0"); sys.exit(0)
print("gone")
' "$tab_id" 2>/dev/null || echo "err")
    case "$working" in
      1) saw_working=1 ;;
      0) if [ "$saw_working" -eq 1 ]; then
           elapsed=$(( $(date +%s) - start_ts ))
           echo "ok  $target ficou ocioso em ${elapsed}s (working=false; sem result file — confira manualmente)" >&2
           exit 0
         fi ;;
      gone) echo "aviso: pane $tab_id sumiu durante o wait" >&2; exit 5 ;;
    esac

    elapsed=$(( $(date +%s) - start_ts ))
    if [ "$elapsed" -ge "$wait_timeout" ]; then
      echo "timeout (${wait_timeout}s) sem conclusão de $target" >&2
      exit 4
    fi
    sleep "$poll_interval"
  done
fi
