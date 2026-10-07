#!/bin/bash
# Confirmación por voz antes de acciones delicadas (hook PreToolUse).
# Solo actúa en sesiones de voz (CLAUDE_SIN_AVISO o CLAUDE_VOZ). Si la herramienta va a borrar, enviar
# o cambiar algo difícil de deshacer, lo dice en voz alta, abre el micrófono unos segundos y solo deja
# seguir si oye un sí. Si la última frase del usuario ya era una confirmación, no vuelve a preguntar.
[ -z "$CLAUDE_SIN_AVISO" ] && [ -z "$CLAUDE_VOZ" ] && exit 0
VOZ="Mónica"
DICTAR="$HOME/.local/bin/dictar"
ESTADO="$HOME/.local/state/siri-claude/estado"
LOG="$HOME/.local/state/siri-claude/conversa.log"

entrada=$(cat)
tool=$(printf '%s' "$entrada" | jq -r '.tool_name // empty')
que=""
case "$tool" in
  Bash)
    cmd=$(printf '%s' "$entrada" | jq -r '.tool_input.command // empty')
    # Quitar el contenido de los heredocs (cat > archivo <<'EOF' ... EOF): es texto, no comandos.
    cmd=$(printf '%s\n' "$cmd" | awk '
      fin != "" { if ($0 == fin) fin = ""; next }
      match($0, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?/) {
        m = substr($0, RSTART, RLENGTH); sub(/^<<-?[[:space:]]*/, "", m); gsub(/["'"'"']/, "", m); fin = m }
      { print }')
    # Patrones de comandos que borran, envían o rompen cosas.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(rm|rmdir|trash|shred)[[:space:]]|[[:space:]]delete[[:space:]]|git[[:space:]]+(push|reset[[:space:]]+--hard|clean|checkout[[:space:]]+\.)|(^|[;&|[:space:]])(kill|killall|pkill|sudo|diskutil|mkfs|dd)[[:space:]]|>[[:space:]]*/(etc|usr|System|Library)/|launchctl[[:space:]]+(unload|remove|bootout)'; then
      # Describir la acción en una frase corta en vez de leer el comando entero.
      plano=$(printf '%s' "$cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')
      app=$(printf '%s' "$plano" | grep -oE 'tell application "[^"]+"' | head -1 | sed -E 's/tell application "([^"]+)"/\1/')
      case "$app" in Reminders) app="Recordatorios" ;; Notes) app="Notas" ;; Mail) app="Correo" ;; Calendar) app="Calendario" ;; Finder) app="el Finder" ;; esac
      if [ -n "$app" ]; then que="borrar algo en $app"
      elif printf '%s' "$plano" | grep -Eq '(^|[;&| ])(rm|rmdir|trash|shred) '; then
        que="borrar $(printf '%s' "$plano" | grep -oE '(^|[;&| ])(rm|rmdir|trash|shred) [^;&|]*' | head -1 | sed -E 's/^[;&| ]*(rm|rmdir|trash|shred) //; s/ -[a-zA-Z]+//g' | cut -c1-60)"
      elif printf '%s' "$plano" | grep -Eq 'git +push'; then que="hacer git push"
      elif printf '%s' "$plano" | grep -Eq 'git +(reset|clean|checkout)'; then que="descartar cambios en git"
      elif printf '%s' "$plano" | grep -Eq '(^|[;&| ])(kill|killall|pkill) '; then que="cerrar procesos"
      elif printf '%s' "$plano" | grep -Eq '(^|[;&| ])sudo '; then que="ejecutar un comando como administrador"
      else que="ejecutar un comando que borra o modifica cosas del sistema"
      fi
    fi ;;
  mcp__*send_message*|mcp__*__reply|mcp__*__forward) que="enviar un correo" ;;
  mcp__*trash*|mcp__*delete*) que="borrar algo en $(printf '%s' "$tool" | sed -E 's/^mcp__[^_]+_?[^_]*__//; s/_.*//')" ;;
  mcp__*spam*) que="marcar correo como spam" ;;
esac
[ -z "$que" ] && exit 0

# ¿La última frase del usuario ya era una confirmación explícita? Entonces no preguntar dos veces.
tp=$(printf '%s' "$entrada" | jq -r '.transcript_path // empty')
if [ -f "$tp" ]; then
  ultima=$(jq -rs '[.[] | select(.type=="user") | .message.content | if type=="string" then . else (.[]? | select(.type=="text") | .text) end] | last // empty' "$tp" 2>/dev/null | tr 'A-ZÁÉÍÓÚ' 'a-záéíóú')
  if printf '%s' "$ultima" | grep -Eq '^[[:space:]]*(s[ií]|vale|ok|claro|confirmo|confirmado|adelante|dale|hazlo|b[oó]rral[oa]s?|env[ií]al[oa]|por supuesto|am[eé]n|venga|de acuerdo|afirmativo)\b'; then
    exit 0
  fi
fi

anterior=$(cat "$ESTADO" 2>/dev/null)
respuesta=""
for intento in 1 2; do
  if [ "$intento" = 1 ]; then say -v "$VOZ" -- "Voy a $que. Di confirmo o cancela."
  else say -v "$VOZ" -- "No te he oído. ¿Confirmo o cancelo?"; fi
  echo escuchando > "$ESTADO"
  afplay /System/Library/Sounds/Tink.aiff 2>/dev/null
  respuesta=$("$DICTAR" --debug --pausa 1.5 --max 12 2>>"$HOME/.local/state/siri-claude/dictar.log" | tr 'A-ZÁÉÍÓÚ' 'a-záéíóú')
  [ -n "$anterior" ] && echo "$anterior" > "$ESTADO"
  [ -n "$respuesta" ] && break
done
printf '%s %s\n' "$(date +%H:%M:%S)" "CONFIRMACIÓN ($que): ${respuesta:-nada oído}" >> "$LOG"
if printf '%s' "$respuesta" | grep -Eq '^[[:space:]]*(s[ií]|vale|ok|claro|confirmo|confirmado|adelante|dale|hazlo|por supuesto|venga|de acuerdo|afirmativo)\b'; then
  exit 0
fi
say -v "$VOZ" -- "Cancelado."
jq -n --arg r "El usuario no lo ha confirmado por voz (dijo: ${respuesta:-nada}). No lo hagas y pregúntale qué quiere." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
