// "Exportar diagnóstico" (PLAN §7.8): zip en tmp con README.txt, feedback.csv
// (scan_id, verdict, top1..3, scores, created_at), scans.csv (sin rutas ni
// identificadores de fotos), times.txt (tiempos registrados por TimingLog) y
// images/<scan_id>.png (copias PNG sRGB de 256 px de las fotos con veredicto,
// ver DiagnosticsImages.swift). Solo por acción explícita del usuario (botón de
// Ajustes) y entregado por ShareLink/AirDrop; la app sigue sin usar red.
import Foundation
import GRDB
import ColorEngine

enum Diagnostics {
    /// Versión de GRDB.swift resuelta por SwiftPM (Package.resolved del proyecto
    /// generado; project.yml pide `from: 7.0.0`). GRDB no expone su versión en
    /// tiempo de ejecución; DiagnosticsTests la cruza con Package.resolved.
    static let grdbVersion = "7.11.1"

    /// Versión de la SQLite enlazada (sqlite3_libversion_number), "3.x.y".
    static var sqliteVersion: String {
        let n = Int(Database.sqliteLibVersionNumber)
        return "\(n / 1_000_000).\(n / 1000 % 1000).\(n % 1000)"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Resultado de una exportación.
    struct Export: Equatable, Sendable {
        let url: URL
        let feedbackRows: Int
        let scanRows: Int
        let images: Int
        let omittedImages: Int
        let notes: [String]
    }

    /// Devuelve el PNG sRGB de 256 px de un scan, o nil si no está disponible.
    typealias ImageProvider = @Sendable (ScanRecord) async -> Data?

    static let feedbackHeader = "scan_id,verdict,top1,top2,top3,scores,created_at"
    static let scansHeader = "id,source,top1,top2,top3,scores,ambiguous,engine_version,dict_version,scanned_at,palette"

    static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Campo CSV (RFC 4180): entrecomillado si contiene coma, comillas o saltos de línea.
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func feedbackCSV(_ feedback: [FeedbackRecord], scans: [String: ScanRecord]) -> String {
        var lines = [feedbackHeader]
        for f in feedback {
            let s = scans[f.scanId]
            let fields = [
                f.scanId,
                f.verdict.rawValue,
                s?.top1.map(String.init) ?? "",
                s?.top2.map(String.init) ?? "",
                s?.top3.map(String.init) ?? "",
                s?.scores ?? "",
                iso(f.createdAt),
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// scans.csv: sin `asset_local_id` (identifica fotos del carrete) ni rutas.
    static func scansCSV(_ scans: [ScanRecord]) -> String {
        var lines = [scansHeader]
        for s in scans {
            let palette = s.palette.map { String(format: "%@:%.4f", $0.hex, $0.weight) }.joined(separator: ";")
            let fields = [
                s.id,
                s.source.rawValue,
                s.top1.map(String.init) ?? "",
                s.top2.map(String.init) ?? "",
                s.top3.map(String.init) ?? "",
                s.scores,
                s.ambiguous ? "1" : "0",
                s.engineVersion,
                s.dictVersion,
                iso(s.scannedAt),
                palette,
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Construye el zip en `directory` (tmp por defecto) y devuelve su URL y el resumen.
    static func export(scans scanRepository: ScanRepository, feedback feedbackRepository: FeedbackRepository,
                       timings: TimingLog, imageProvider: ImageProvider?,
                       directory: URL = FileManager.default.temporaryDirectory,
                       now: Date = Date()) async throws -> Export {
        let feedback = try await feedbackRepository.all()
        let scans = try await scanRepository.recent(limit: 100_000)
        var byId = Dictionary(scans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Scans con veredicto pero borrados (soft delete): se recuperan para el CSV.
        for f in feedback where byId[f.scanId] == nil {
            if let s = try await scanRepository.fetch(id: f.scanId) { byId[f.scanId] = s }
        }

        var notes: [String] = []
        var entries: [ZipEntry] = [
            ZipEntry(name: "feedback.csv", text: feedbackCSV(feedback, scans: byId)),
            ZipEntry(name: "scans.csv", text: scansCSV(scans)),
            ZipEntry(name: "times.txt", text: timings.text()),
        ]

        var images = 0
        var omitted = 0
        var seen = Set<String>()
        for f in feedback where seen.insert(f.scanId).inserted {
            guard let scan = byId[f.scanId] else {
                omitted += 1
                notes.append("scan \(f.scanId): veredicto sin scan en la base de datos")
                continue
            }
            if let imageProvider, let png = await imageProvider(scan) {
                entries.append(ZipEntry(name: "images/\(scan.id).png", data: png))
                images += 1
            } else {
                omitted += 1
            }
        }
        if omitted > 0 {
            notes.append("\(omitted) foto(s) con veredicto omitidas: sin copia local y sin acceso a Fotos (o solo en iCloud).")
        }

        let readme = """
        colorsApp — diagnóstico
        exportado: \(iso(now))
        app \(appVersion) (\(appBuild)) · motor \(colorEngineVersion) · diccionario \(dictionaryVersion) · GRDB \(grdbVersion) · SQLite \(sqliteVersion)
        feedback.csv: scan_id, verdict (yes|no), top1..top3, scores (JSON), created_at
        scans.csv: todos los scans vivos, sin rutas ni identificadores de fotos
        times.txt: tiempos registrados (analyze.<origen>, scan.done...)
        images/<scan_id>.png: PNG sRGB de 256 px de las fotos con veredicto (\(images) incluidas, \(omitted) omitidas)
        \(notes.joined(separator: "\n"))
        """
        entries.insert(ZipEntry(name: "README.txt", text: readme + "\n"), at: 0)

        let data = Zip.archive(entries, date: now)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("colorsapp-diagnostico-\(fileStamp(now)).zip")
        try data.write(to: url, options: .atomic)
        return Export(url: url, feedbackRows: feedback.count, scanRows: scans.count,
                      images: images, omittedImages: omitted, notes: notes)
    }

    static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

/// Tiempos registrados (times.txt del diagnóstico): una línea
/// "<ISO8601> <etiqueta> <ms> ms" por medición. Fichero en Application
/// Support/ColorsApp junto a la base de datos. Etiquetas usadas:
/// `analyze.<origen>` (captura de Hoy) y `scan.done` (escaneo del carrete).
struct TimingLog: Sendable {
    let url: URL

    static let shared = TimingLog(
        url: AppDatabase.defaultURL.deletingLastPathComponent().appendingPathComponent("times.txt"))

    private static let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func record(_ label: String, ms: Int, now: Date = Date()) {
        let line = "\(Diagnostics.iso(now)) \(label) \(ms) ms\n"
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // El diagnóstico es lo mejor que se pueda: nunca rompe la app.
        }
    }

    func text() -> String {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func clear() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}
