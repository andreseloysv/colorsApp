// Contador de lanzamientos persistido en un fichero de Documents. Sirve en la
// fase 0 para comprobar que reinstalar la app (perfil de 7 días del Personal
// Team) conserva el contenedor de datos: si el número no vuelve a 1, se
// conservan.
import Foundation

enum LaunchCounter {
    static let fileName = "launches.txt"

    /// Directorio Documents del contenedor de la app.
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Lee el contador de `directory/launches.txt` (0 si no existe).
    static func read(in directory: URL = documentsDirectory) -> Int {
        let url = directory.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Incrementa el contador, lo escribe de forma atómica y devuelve el nuevo valor.
    @discardableResult
    static func increment(in directory: URL = documentsDirectory) throws -> Int {
        let next = read(in: directory) + 1
        let url = directory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "\(next)\n".write(to: url, atomically: true, encoding: .utf8)
        return next
    }
}
