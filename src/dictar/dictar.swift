// dictar: escucha el micrófono y escribe en stdout lo dictado, hasta detectar una pausa.
//
//   dictar [--pausa SEG] [--max SEG] [--idioma es-ES]
//
// Sale con 0 y el texto (vacío si no se oyó nada antes de --max segundos).
// Sale con 1 y un mensaje en stderr si faltan permisos o falla el reconocimiento.

import AVFoundation
import Foundation
import Speech

var pausa = 1.6        // segundos sin cambios en la transcripción para dar la frase por terminada
var maxSeg = 20.0      // segundos máximos esperando a que empiece a hablar
var idioma = "es-ES"
var umbral: Float = 0.012   // nivel RMS por encima del cual se considera que hay voz
var debug = false
func traza(_ m: String) { if debug { FileHandle.standardError.write(("[dictar] " + m + "\n").data(using: .utf8)!) } }

var argumentos = Array(CommandLine.arguments.dropFirst())
while !argumentos.isEmpty {
    let a = argumentos.removeFirst()
    switch a {
    case "--pausa": pausa = Double(argumentos.removeFirst()) ?? pausa
    case "--max": maxSeg = Double(argumentos.removeFirst()) ?? maxSeg
    case "--idioma": idioma = argumentos.removeFirst()
    case "--debug": debug = true
    case "--umbral": umbral = Float(argumentos.removeFirst()) ?? umbral
    default:
        FileHandle.standardError.write("argumento desconocido: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

func fallo(_ mensaje: String) -> Never {
    FileHandle.standardError.write((mensaje + "\n").data(using: .utf8)!)
    exit(1)
}

func esperar(hasta listo: () -> Bool) {
    while !listo() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
}

// Permisos: micrófono y reconocimiento de voz. La primera vez macOS pregunta al usuario.
var micOK: Bool? = nil
AVCaptureDevice.requestAccess(for: .audio) { micOK = $0 }
esperar { micOK != nil }
if micOK != true { fallo("Sin permiso de micrófono (Ajustes > Privacidad y seguridad > Micrófono).") }

var vozOK: SFSpeechRecognizerAuthorizationStatus? = nil
SFSpeechRecognizer.requestAuthorization { vozOK = $0 }
esperar { vozOK != nil }
if vozOK != .authorized { fallo("Sin permiso de reconocimiento de voz (Ajustes > Privacidad y seguridad > Reconocimiento de voz).") }

guard let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: idioma)), reconocedor.isAvailable else {
    fallo("Reconocimiento de voz no disponible para \(idioma).")
}

let peticion = SFSpeechAudioBufferRecognitionRequest()
peticion.shouldReportPartialResults = true
peticion.addsPunctuation = true
traza("reconocedor disponible=\(reconocedor.isAvailable) enDispositivo=\(reconocedor.supportsOnDeviceRecognition)")
if reconocedor.supportsOnDeviceRecognition { peticion.requiresOnDeviceRecognition = true }

var texto = ""
var ultimoSonido = Date()
let motor = AVAudioEngine()
let entrada = motor.inputNode
let formato = entrada.outputFormat(forBus: 0)
traza("formato entrada: \(formato)")
var buffers = 0
entrada.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, _ in
    peticion.append(buffer)
    buffers += 1
    guard let canal = buffer.floatChannelData?[0] else { return }
    var suma: Float = 0
    for i in 0..<Int(buffer.frameLength) { suma += canal[i] * canal[i] }
    let rms = (suma / Float(max(buffer.frameLength, 1))).squareRoot()
    if rms > umbral { ultimoSonido = Date() }
    if debug && buffers % 20 == 0 { traza(String(format: "audio buffers=%d rms=%.4f texto=%@", buffers, rms, texto)) }
}
motor.prepare()
do { try motor.start() } catch { fallo("No se pudo abrir el micrófono: \(error.localizedDescription)") }

var ultimoCambio = Date()
let inicio = Date()
var terminado = false

let tarea = reconocedor.recognitionTask(with: peticion) { resultado, error in
    if let r = resultado {
        let nuevo = r.bestTranscription.formattedString
        // El reconocedor en dispositivo a veces entrega, tras endAudio(), un resultado final VACÍO que
        // pisaría lo ya transcrito: nunca sustituir texto por nada.
        if nuevo.isEmpty && !texto.isEmpty {
            traza("resultado vacío ignorado (final=\(r.isFinal))")
        } else if nuevo != texto { texto = nuevo; ultimoCambio = Date(); traza("parcial: \(nuevo)") }
        if r.isFinal { terminado = true }
    }
    if let e = error {
        // Incluye "No speech detected" tras unos segundos de silencio y el error que llega al cancelar
        // nosotros la tarea: en ambos casos se devuelve lo transcrito hasta ahora (quizá nada) y el que
        // llama decide si vuelve a escuchar. Los permisos ya se comprobaron antes de llegar aquí.
        traza("error reconocimiento: \(e.localizedDescription)")
        terminado = true
    }
}

esperar {
    if terminado { return true }
    let ahora = Date()
    // Frase terminada: hay texto, el micrófono lleva `pausa` segundos en silencio y el reconocedor no ha cambiado nada hace poco.
    if !texto.isEmpty && ahora.timeIntervalSince(ultimoSonido) >= pausa && ahora.timeIntervalSince(ultimoCambio) >= 0.5 { traza("fin: silencio"); return true }
    // Salida de emergencia: hay texto pero el reconocedor lleva un buen rato sin cambiar nada (ruido de fondo
    // por encima del umbral, o el micrófono captando algo que no es voz). No esperar al silencio.
    if !texto.isEmpty && ahora.timeIntervalSince(ultimoCambio) >= pausa + 2.5 { traza("fin: sin cambios"); return true }
    // Tope absoluto por frase: el reconocedor en dispositivo no aguanta sesiones de más de un minuto.
    if !texto.isEmpty && ahora.timeIntervalSince(inicio) >= 58 { traza("fin: tope"); return true }
    if texto.isEmpty && ahora.timeIntervalSince(inicio) >= maxSeg { return true }
    return false
}

motor.stop()
entrada.removeTap(onBus: 0)
peticion.endAudio()
// Da al reconocedor hasta un segundo para entregar el resultado final con las últimas palabras.
let limite = Date(timeIntervalSinceNow: 1.0)
esperar { terminado || Date() >= limite }
tarea.cancel()

print(texto)
