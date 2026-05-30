#!/usr/bin/env bash
set -euo pipefail

# Envia /clear pros panes de agente (App, Relay, Extension, Site) do workspace
# cmux atual — começa uma sessão limpa em cada um SEM matar o processo claude
# nem recriar panes. Ideal pra iniciar uma feature nova: o agente esquece o
# contexto anterior mas continua vivo na mesma pasta, mesmo modelo, mesma
# .claude/ própria. Mais leve que close+bootstrap; oposto de `claude --resume`
# (que carregaria o contexto VELHO).
#
# /clear é comando SOLO (built-in do claude), não dispatch orquestrado — por
# isso NÃO usa o marker [ORCH:]. Manda o texto literal + Enter (separado, igual
# ao caminho solo documentado no CLAUDE.md raiz).
#
# Uso:
#   scripts/cmux-clear-agents.sh                  # limpa os 4
#   scripts/cmux-clear-agents.sh Extension Site   # limpa só esses
#   scripts/cmux-clear-agents.sh --help           # esta mensagem
#
# Pré-requisitos:
#   - cmux no PATH
#   - rodar de dentro de um terminal cmux do workspace alvo
#     (deriva o workspace via `cmux identify`)
#
# IMPORTANTE: só rode com os agentes OCIOSOS. Se um agente está no meio de uma
# task, o /clear vira texto no buffer ou interrompe o trabalho — espere ele
# gravar o result file (ou use o --wait do dispatch) antes de limpar.
#
# Idempotente: títulos ausentes geram aviso, não erro. Surfaces com outros
# nomes (Orquestrador, "✳ Review...", worktrees) não são tocadas.

usage() {
  awk '
    /^# Envia/ { on = 1 }
    on {
      if (!/^#/) exit
      sub(/^# /, "")
      sub(/^#$/, "")
      print
    }
  ' "$0"
}

valid_panes=(App Relay Extension Site)
is_valid_pane() {
  case " ${valid_panes[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Parse args: flags + lista opcional de panes. Sem panes = todos os 4.
targets=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -*)        echo "erro: flag desconhecida: $arg" >&2; usage >&2; exit 2 ;;
    *)
      if is_valid_pane "$arg"; then
        targets+=("$arg")
      else
        echo "erro: pane '$arg' inválido. Use: ${valid_panes[*]}" >&2
        exit 2
      fi
      ;;
  esac
done
[ ${#targets[@]} -gt 0 ] || targets=("${valid_panes[@]}")

command -v cmux >/dev/null || { echo "erro: cmux não encontrado no PATH" >&2; exit 1; }

# `cmux tree` usa short refs (workspace:N). $CMUX_WORKSPACE_ID pode ser UUID;
# derive o short ref via `cmux identify` pra casar com o tree.
WS_REF=$(cmux identify 2>/dev/null \
  | awk -F'"' '/"workspace_ref"/ {print $4; exit}')
[ -n "$WS_REF" ] || { echo "erro: workspace cmux não identificado" >&2; exit 1; }

# emite "Título<TAB>surface:NN" pra cada surface do workspace alvo
surfaces_in_workspace() {
  cmux tree 2>/dev/null | awk -v target="$WS_REF" '
    /workspace workspace:/ {
      in_ws = 0
      for (i = 1; i <= NF; i++) if ($i == target) in_ws = 1
      next
    }
    in_ws && /surface surface:/ {
      sid = ""
      for (i = 1; i <= NF; i++) if ($i ~ /^surface:/) sid = $i
      if (sid != "" && match($0, /"[^"]+"/)) {
        title = substr($0, RSTART + 1, RLENGTH - 2)
        print title "\t" sid
      }
    }
  '
}

mapping=$(surfaces_in_workspace)

cleared=0
missing=0
failed=0
for name in "${targets[@]}"; do
  sid=$(awk -F'\t' -v n="$name" '$1 == n {print $2; exit}' <<<"$mapping")
  if [ -z "$sid" ]; then
    echo "  -   $name: não encontrado, pulando"
    missing=$((missing + 1))
    continue
  fi

  # Caminho solo: manda "/clear" e o Enter separado. A pausa evita o race do
  # bracketed-paste (Enter virando newline no buffer em vez de submit), mesmo
  # motivo do sleep no cmux-dispatch.sh.
  if cmux send --surface "$sid" -- "/clear" >/dev/null 2>&1; then
    sleep 0.4
    if cmux send-key --surface "$sid" enter >/dev/null 2>&1; then
      printf "  ok  %-10s %s /clear enviado\n" "$name" "$sid"
      cleared=$((cleared + 1))
    else
      echo "  !!  $name ($sid): /clear digitado mas Enter falhou" >&2
      failed=$((failed + 1))
    fi
  else
    echo "  !!  $name ($sid): falhou ao enviar /clear" >&2
    failed=$((failed + 1))
  fi
done

echo "pronto. limpos=$cleared, ausentes=$missing, falhas=$failed."
echo "dica: confira visualmente que cada pane mostrou o contexto zerado."
[ "$failed" -eq 0 ] || exit 4
