// Mensajes de error en español para la UI (imagen ilegible, motor, base de
// datos, escaneo). Los errores del motor llevan el código ce_status.
import Foundation
import ColorEngine
import GRDB
import SubjectKit

enum ErrorText {
    static func describe(_ error: any Error) -> String {
        switch error {
        case let e as ImageLoadingError:
            return e.errorDescription ?? "Imagen ilegible."
        case let e as EngineBridgeError:
            switch e {
            case .contextUnavailable: return "No se ha podido preparar la imagen para el motor (CoreGraphics)."
            case .emptyImage: return "La imagen está vacía."
            }
        case let e as ColorEngineError:
            switch e {
            case .engine(let code): return "El motor de color devolvió el error \(code)."
            case .bufferTooSmall(let required, let actual):
                return "Buffer de imagen corto (\(actual) de \(required) bytes)."
            case .maskTooSmall(let required, let actual):
                return "Máscara corta (\(actual) de \(required) bytes)."
            }
        case let e as ScanError:
            switch e {
            case .notImplemented: return "El escaneo del carrete llega en la próxima build."
            case .accessDenied: return "Sin acceso a Fotos: actívalo en Ajustes > Privacidad y seguridad > Fotos."
            case .limitedAccess: return "Acceso limitado a Fotos: el escaneo del carrete necesita acceso completo."
            case .cancelled: return "Escaneo cancelado."
            }
        case let e as DatabaseError:
            return "Error de la base de datos: \(e.message ?? String(e.resultCode.rawValue))."
        case let e as SubjectError:
            switch e {
            case .invalidDimensions(let w, let h): return "Recorte de sujeto: dimensiones inválidas (\(w) × \(h))."
            case .maskSizeMismatch(let id, let expected, let actual):
                return "Recorte de sujeto: la máscara de la persona \(id) mide \(actual) bytes y debería medir \(expected)."
            case .invalidOptions(let why): return "Recorte de sujeto: opciones inválidas (\(why))."
            case .graphicsUnavailable: return "Recorte de sujeto: CoreGraphics no pudo preparar la máscara."
            case .unsupportedPixelFormat(let f): return "Recorte de sujeto: formato de Vision no soportado (\(f))."
            }
        case let e as ZipError:
            return "No se ha podido crear el zip: \(e)."
        default:
            return error.localizedDescription
        }
    }
}
