#!/bin/zsh
# Instala los scripts en ~/.local/bin, compila dictar y semaforo, copia los hooks y los registra en
# ~/.claude/settings.json (fusionando con lo que ya haya). Se puede ejecutar varias veces.
set -e
cd "$(dirname "$0")"
mkdir -p ~/.local/bin ~/.local/src ~/.local/state/siri-claude ~/.claude/hooks
cp bin/* ~/.local/bin/ && chmod +x ~/.local/bin/*
cp -R src/dictar src/semaforo ~/.local/src/
SDK="$(xcrun --show-sdk-path 2>/dev/null || ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk | tail -1)"
echo "Compilando dictar y semaforo con $SDK ..."
swiftc -O -sdk "$SDK" -framework AVFoundation -framework Speech -o ~/.local/bin/dictar src/dictar/dictar.swift
swiftc -O -sdk "$SDK" -framework AppKit -o ~/.local/bin/semaforo src/semaforo/semaforo.swift
cp hooks/*.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/*.sh
if [[ -f ~/.claude/settings.json ]]; then
  jq -s '.[0] * .[1]' ~/.claude/settings.json hooks/settings.hooks.json > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
else
  cp hooks/settings.hooks.json ~/.claude/settings.json
fi
echo "Listo. Añade ~/.local/bin al PATH si no lo está y sigue con atajos/README.md para crear los atajos."
