#!/bin/zsh
# Instala los scripts en ~/.local/bin, compila dictar y semaforo, copia los hooks y los registra en
# ~/.claude/settings.json (fusionando con lo que ya haya). Se puede ejecutar varias veces.
set -e
cd "$(dirname "$0")"
mkdir -p ~/.local/bin ~/.local/src ~/.local/state/siri-claude ~/.claude/hooks
cp bin/* ~/.local/bin/ && chmod +x ~/.local/bin/*
cp -R src/dictar src/semaforo ~/.local/src/
# El SDK más nuevo no siempre casa con el compilador instalado: se prueba del más nuevo al más viejo.
ok=""
for SDK in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV) "$(xcrun --show-sdk-path 2>/dev/null)"; do
  [[ -d "$SDK" ]] || continue
  if swiftc -O -sdk "$SDK" -framework AVFoundation -framework Speech -o ~/.local/bin/dictar src/dictar/dictar.swift 2>/dev/null \
     && swiftc -O -sdk "$SDK" -framework AppKit -o ~/.local/bin/semaforo src/semaforo/semaforo.swift 2>/dev/null; then
    ok="$SDK"; break
  fi
done
[[ -n "$ok" ]] || { echo "No he podido compilar dictar/semaforo con ningún SDK de /Library/Developer/CommandLineTools/SDKs" >&2; exit 1; }
echo "dictar y semaforo compilados con $ok"
cp hooks/*.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/*.sh
if [[ -f ~/.claude/settings.json ]]; then
  jq -s '.[0] * .[1]' ~/.claude/settings.json hooks/settings.hooks.json > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
else
  cp hooks/settings.hooks.json ~/.claude/settings.json
fi
echo "Listo. Añade ~/.local/bin al PATH si no lo está y sigue con atajos/README.md para crear los atajos."
