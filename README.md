# mac-por-voz

Conversar con una IA desde el Mac con las manos libres: hablas, te responde en voz alta y vuelve a escuchar. Todo con herramientas del sistema (zsh, AppleScript, Atajos, el reconocedor de voz de Apple y `say`), sin servicios externos para la voz. Está montado sobre **Claude Code** (`claude -p`), pero el puente con la IA es un único script y se puede cambiar por cualquier CLI que lea un texto por stdin y devuelva la respuesta por stdout.

## Qué hace

- **Conversación continua por voz** con una tecla global o diciéndoselo a Siri. Tono → hablas → tono → respuesta hablada → vuelve a escuchar. Termina al despedirte ("adiós", "hasta luego", "cierra la conversación") o tras tres minutos de silencio.
- **Semáforo flotante**: un círculo en la esquina que indica si está escuchando (verde), pensando (ámbar) o hablando (azul). Gris en pausa.
- **Pausa por voz**: "pausa" ignora todo lo que oiga (una llamada, otra persona) hasta que digas "sigue".
- **Terminal compartida**: pides "ábrela en terminal" y se abre una Terminal con *la misma* conversación. Lo que dictas aparece allí escrito; lo que tecleas allí también se contesta en voz alta. Al cerrarla, la voz sigue con todo el historial. También puede abrir cualquier conversación anterior (`claude-sesiones` + `claude-terminal <id>`).
- **Actuar sobre el Mac**: la IA puede abrir apps, escribir donde esté el cursor (`claude-escribe`), crear recordatorios (`recordatorio`), lanzar tareas largas en segundo plano que avisan por voz al terminar (`claude-tarea`), etc.
- **Confirmación por voz** antes de acciones delicadas (borrar, enviar correo, forzar cambios en git…): un hook pregunta en voz alta y solo sigue si oye "confirmo".
- **Memoria entre días**: al despedirte se guarda un resumen de la conversación y la siguiente empieza sabiendo dónde lo dejasteis.
- Extras: resumen hablado del día (recordatorios, calendario, correo), explicar el texto seleccionado, preguntar sobre una captura de pantalla.

## Cómo está montado

```
Atajo "Hablar con Claude" (tecla global / Siri)
   └─ claude-conversa        bucle en zsh: tono → dictar → puente → say → repetir
        ├─ dictar            reconocedor de voz (Swift, Speech + AVFoundation), corta la frase por silencio
        ├─ semaforo          círculo flotante (Swift/AppKit) que lee ~/.local/state/siri-claude/estado
        ├─ siri-claude       PUENTE con la IA: stdin → claude -p (sesión persistente 30 min) → stdout
        └─ terminal compartida (claude-terminal): Terminal.app con la misma sesión; el bucle escribe
           lo dictado en esa pestaña y el hook aviso-voz.sh lee las respuestas en voz alta
Hooks de Claude Code (~/.claude/hooks):
   aviso-voz.sh     UserPromptSubmit/Stop: avisa cuando acaba una tarea larga; en la terminal compartida lee la respuesta
   confirma-voz.sh  PreToolUse: confirmación por voz antes de borrar/enviar/forzar
```

Estado y registros en `~/.local/state/siri-claude/`: `session` (id de la conversación en curso), `estado` (para el semáforo), `terminal` y `terminal-turno` (terminal compartida), `conversa.log` (qué se oyó y qué se respondió), `dictar.log` (parciales del reconocedor), `resumenes/` (uno por despedida), `tareas/` (resultados de `claude-tarea`).

### Scripts (`bin/`)

| Script | Para qué |
|---|---|
| `claude-conversa` | El bucle de conversación. Lanzarlo otra vez cierra la conversación abierta. `ECO=1` repite lo entendido antes de responder. |
| `siri-claude` | Puente stdin→IA→stdout. Mantiene la sesión, detecta despedidas, guarda el resumen al cerrar. `--solo-fin` y `--resumen` los usa el bucle. |
| `dictar` | `dictar [--pausa s] [--max s] [--debug]`: escucha y escribe lo dictado; útil también solo. |
| `semaforo` | Indicador flotante; lo lanza el bucle. Se puede arrastrar. |
| `claude-terminal [id]` | Abre la terminal compartida (de la conversación en curso o de otra). |
| `claude-sesiones [n]` | Lista conversaciones recientes: fecha, id, primera frase. |
| `claude-escribe "texto"` | Pega el texto donde esté el cursor de la app activa. |
| `claude-tarea "texto"` | Tarea larga en segundo plano; avisa por voz al terminar. |
| `recordatorio "texto" ["AAAA-MM-DD HH:MM"]` | Crea un recordatorio en Recordatorios. |
| `claude-hoy`, `claude-explica`, `claude-pantalla` | Resumen del día, explicar selección, preguntar a la pantalla. |

## Instalación

Requisitos: macOS 15 o superior, Xcode Command Line Tools (`xcode-select --install`), `jq` (`brew install jq`) y [Claude Code](https://docs.claude.com/en/docs/claude-code) instalado y con sesión iniciada. Para correo y calendario, conectar Gmail y Google Calendar en Claude Code (opcional).

```sh
git clone <este repositorio> && cd mac-por-voz
./install.sh
```

Después:

1. Crear los atajos de la app Atajos siguiendo `atajos/README.md` y asignar una tecla a "Hablar con Claude".
2. Conceder los permisos que macOS pida la primera vez (micrófono, reconocimiento de voz, accesibilidad, automatización).
3. Personalizar: la voz (`VOZ="Mónica"` en los scripts; ver `say -v '?'`), el perfil del usuario en `claude-explica`, `claude-pantalla` y `claude-hoy` (marcado con PERSONALIZA), y las reglas de voz en `siri-claude` (`VOICE_RULES`).

Probar sin atajos: `claude-conversa` desde una terminal, o `echo "hola" | siri-claude`.

## Usarlo con otra IA

Todo lo que habla con el modelo pasa por `bin/siri-claude`, función `ask()`. Sustituye la llamada a `claude -p` por cualquier CLI que acepte el texto por stdin y responda por stdout (un cliente de la API de OpenAI, Ollama en local, etc.). Si la herramienta no mantiene sesión, guarda tú el historial o pásaselo en cada llamada. Los hooks y la terminal compartida son específicos de Claude Code; el resto (bucle, dictado, semáforo, scripts del Mac) es independiente.

## Decisiones y trampas conocidas

- **Los bucles no van en Atajos**: las acciones Repetir/Si fallan al combinarlas con scripts; el atajo solo lanza `claude-conversa`, que vive en zsh y se desacopla para que Siri no se quede esperando.
- **Resultado final vacío**: el reconocedor en dispositivo a veces entrega, al cerrar el audio, un resultado final vacío que pisaría la frase. `dictar` lo ignora. Si se pierden frases, `dictar --debug` muestra los parciales.
- **Habla después del tono**: mientras la IA lee la respuesta el micrófono está cerrado; lo que digas antes del tono se pierde (sin auriculares, escuchar mientras habla haría que se oyera a sí misma).
- **Palabras cortas**: un "sí" suelto se reconoce mal; por eso la confirmación pide "confirmo" (y acepta variantes como "confirma").
- **Los hooks no oyen**: Claude Code ejecuta los hooks en un entorno donde el micrófono entrega silencio. Por eso `confirma-voz.sh` no escucha él mismo: deja la pregunta en `confirmacion-pregunta` y es el bucle de voz quien la hace, escucha y escribe `confirmacion-respuesta`.
- **El tono lo da `dictar`** (`--tono`), justo cuando ya está grabando: si sonara antes de abrir el micrófono, una respuesta corta e inmediata se perdería en el arranque.
- **SDK de Swift**: el SDK más nuevo de Command Line Tools puede no casar con el compilador; `install.sh` prueba del más nuevo al más viejo.
- **Terminal compartida**: Terminal.app hereda las variables de entorno del proceso que lo lanza; hay que limpiar `CLAUDE_CODE_CHILD_SESSION` y poner `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` o la transcripción no se guarda. Para enviar el prompt no basta un salto de línea: hace falta pulsar Intro con System Events (permiso de Accesibilidad), que roba el foco un instante.
- **Una sola conversación a la vez**: `conversa.pid` hace de cerrojo; relanzar el script cierra la conversación abierta.
- **Permisos (TCC)**: se conceden a la app que lanza el proceso (Atajos o Terminal), no al script.
