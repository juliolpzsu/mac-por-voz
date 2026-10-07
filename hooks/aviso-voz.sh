#!/bin/bash
# Voz al terminar un turno de Claude.
#   aviso-voz.sh inicio  -> hook UserPromptSubmit: apunta cuándo empezó el turno (y calla la voz en curso)
#   aviso-voz.sh fin     -> hook Stop:
#        - si la sesión viene del atajo de voz (CLAUDE_VOZ=1, lo exporta claude-terminal), lee la respuesta entera
#        - si no, solo avisa "Listo, he terminado" cuando el turno pasó de UMBRAL segundos
UMBRAL=30
VOZ="Mónica"

# Los scripts de Siri/atajos ya hablan por su cuenta; no duplicar el aviso. (CLAUDE_VOZ manda: una terminal
# abierta desde la conversación de voz hereda el entorno de Terminal.app, que puede traer CLAUDE_SIN_AVISO.)
[ -z "$CLAUDE_VOZ" ] && [ -n "$CLAUDE_SIN_AVISO" ] && exit 0

STATE="$HOME/.claude/hooks/state"
# Estado de la conversación de voz (terminal compartida): fase del turno y última respuesta.
STATE_VOZ="$HOME/.local/state/siri-claude"
TURNO="$STATE_VOZ/terminal-turno"
mkdir -p "$STATE"

entrada=$(cat)
sid=$(printf '%s' "$entrada" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$sid" ] && sid=default
marca="$STATE/$sid.inicio"

# Última respuesta de Claude: la trae el hook en las versiones recientes; si no, se saca de la transcripción.
ultima_respuesta() {
  local t
  t=$(printf '%s' "$entrada" | jq -r '.last_assistant_message // empty' 2>/dev/null)
  if [ -z "$t" ]; then
    local tp
    tp=$(printf '%s' "$entrada" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -f "$tp" ] && t=$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // empty' "$tp" 2>/dev/null)
  fi
  # Quitar lo que no se puede leer en voz alta: bloques de código, marcas de markdown, URLs.
  printf '%s' "$t" | awk '/^```/{c=!c; if(c) print "bloque de código omitido."; next} !c' \
    | sed -E 's/https?:\/\/[^ )]+/enlace/g; s/[*_`#>|]+//g; s/^[-•] +//' | tr -s '\n' ' '
}

case "$1" in
  inicio)
    pkill -x say 2>/dev/null
    date +%s > "$marca"
    # Sesión abierta desde la conversación de voz: avisar al bucle de que hay actividad para que no se retire.
    if [ -n "$CLAUDE_VOZ" ]; then mkdir -p "$STATE_VOZ"; touch "$STATE_VOZ/actividad"; echo inicio > "$TURNO"; fi
    ;;
  fin)
    if [ -n "$CLAUDE_VOZ" ]; then
      rm -f "$marca"
      texto=$(ultima_respuesta)
      mkdir -p "$STATE_VOZ"
      printf "%s\n" "$texto" > "$STATE_VOZ/terminal-respuesta"
      echo hablando > "$TURNO"
      [ -n "$texto" ] && say -v "$VOZ" -- "$texto"
      echo fin > "$TURNO"
      exit 0
    fi
    [ -f "$marca" ] || exit 0
    inicio=$(cat "$marca")
    rm -f "$marca"
    (( $(date +%s) - inicio >= UMBRAL )) || exit 0
    say -v "$VOZ" "Listo, he terminado."
    ;;
esac
exit 0
