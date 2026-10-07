// Semáforo de la conversación por voz: un círculo flotante que cambia de color
// según el contenido de ~/.local/state/siri-claude/estado:
//   escuchando -> verde, procesando -> ámbar (parpadea), hablando -> azul, otro -> gris.
// Termina solo cuando el archivo de estado desaparece o muere el proceso padre (--padre PID).
// Compilar: swiftc -O -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX<versión>.sdk -framework AppKit -o ~/.local/bin/semaforo semaforo.swift
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let estadoPath = home + "/.local/state/siri-claude/estado"
var padre: pid_t = 0
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--padre"), i + 1 < args.count { padre = pid_t(args[i + 1]) ?? 0 }

final class Circulo: NSView {
    var color = NSColor.systemGray
    var alpha: CGFloat = 1
    override func draw(_ rect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: r).fill()
    }
    override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let lado: CGFloat = 34
// Posición: se guarda en un archivo (x e y desde la esquina superior izquierda, en puntos) cada vez que
// El usuario arrastra el círculo, y se restaura al arrancar. Sin archivo, a la derecha del notch del portátil.
let pantallaCompleta = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
let posicionArchivo = NSString(string: "~/.local/state/siri-claude/semaforo-posicion").expandingTildeInPath
var arriba = NSPoint(x: 826, y: -2)
if let txt = try? String(contentsOfFile: posicionArchivo, encoding: .utf8) {
    let partes = txt.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
    if partes.count == 2 { arriba = NSPoint(x: partes[0], y: partes[1]) }
}
let origen = NSPoint(x: pantallaCompleta.minX + arriba.x, y: pantallaCompleta.maxY - arriba.y - lado)
let win = NSPanel(contentRect: NSRect(origin: origen, size: NSSize(width: lado, height: lado)),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = false
win.level = .statusBar
win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
win.isMovableByWindowBackground = true
win.hidesOnDeactivate = false
let vista = Circulo(frame: NSRect(x: 0, y: 0, width: lado, height: lado))
win.contentView = vista
win.orderFrontRegardless()
NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { _ in
    let f = win.frame
    let x = f.minX - pantallaCompleta.minX
    let y = pantallaCompleta.maxY - f.maxY
    try? String(format: "%.0f %.0f\n", x, y).write(toFile: posicionArchivo, atomically: true, encoding: .utf8)
}

var tick = 0
Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
    if padre > 0 && kill(padre, 0) != 0 { app.terminate(nil) }
    guard let estado = try? String(contentsOfFile: estadoPath, encoding: .utf8) else { app.terminate(nil); return }
    tick += 1
    switch estado.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "escuchando": vista.color = .systemGreen; vista.alpha = 1
    case "procesando": vista.color = .systemOrange; vista.alpha = (tick / 3) % 2 == 0 ? 1 : 0.35
    case "hablando":   vista.color = .systemBlue; vista.alpha = 1
    default:           vista.color = .systemGray; vista.alpha = 0.7
    }
    vista.needsDisplay = true
}
app.run()
