# Atajos de la app Atajos

Los atajos son el punto de entrada desde Siri, el teclado o el menú de acciones rápidas. Cada uno tiene una sola acción, **Ejecutar script de shell** (shell `zsh`, entrada "sin entrada" salvo donde se indica). Hay que marcar antes **Ajustes de Atajos → Avanzado → Permitir ejecutar scripts**.

| Atajo | Script | Notas |
|---|---|---|
| Hablar con Claude | `~/.local/bin/claude-conversa` | Asígnale una tecla global en los detalles del atajo. Lanzarlo con la conversación abierta la cierra, así que la misma tecla sirve de interruptor. |
| Resumen del día | `~/.local/bin/claude-hoy` | Lee en voz alta recordatorios, calendario y correo. |
| Explicar selección | `~/.local/bin/claude-explica` | Acción rápida: entrada "texto" desde el menú de servicios. |
| Preguntar a la pantalla | `~/.local/bin/claude-pantalla` | Hace una captura y pregunta. |

Permisos que macOS pedirá la primera vez (Ajustes → Privacidad y seguridad): **Micrófono** y **Reconocimiento de voz** para `dictar`; **Accesibilidad** para Atajos y Terminal (necesario para `claude-escribe` y para la terminal compartida); **Automatización** sobre Notas, Recordatorios, Terminal y System Events.

Consejo: los bucles hechos con acciones Repetir/Si de Atajos fallan con scripts; por eso toda la lógica vive en zsh y el atajo solo lanza el script.
