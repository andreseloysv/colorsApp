// Repositorios sobre AppDatabase: la única puerta de la UI a las tablas.
// Funciones async (GRDB `write`/`read` async) y observaciones
// (`ValueObservation` -> `AsyncValueObservation`, iterable con `for try await`).
// Mantienen las columnas sync-ready: updated_at, rev, dirty y borrado suave.
import Foundation
import GRDB

// MARK: - scans

struct ScanRepository: Sendable {
    let db: any DatabaseWriter

    init(_ database: AppDatabase) { db = database.writer }

    /// Inserta (o reemplaza por id) un scan.
    func insert(_ scan: ScanRecord) async throws {
        try await db.write { db in try scan.save(db) }
    }

    func fetch(id: String) async throws -> ScanRecord? {
        try await db.read { db in try ScanRecord.fetchOne(db, key: id) }
    }

    /// Últimos scans no borrados, más reciente primero.
    func recent(limit: Int = 50) async throws -> [ScanRecord] {
        try await db.read { db in try Self.recentRequest(limit: limit).fetchAll(db) }
    }

    /// Scans no borrados con un top-1 dado (para "dónde vi esta combinación").
    func scans(withTop1 comboId: Int, limit: Int = 50) async throws -> [ScanRecord] {
        try await db.read { db in
            try ScanRecord
                .filter(ScanRecord.Columns.deletedAt == nil && ScanRecord.Columns.top1 == comboId)
                .order(ScanRecord.Columns.scannedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await db.read { db in try ScanRecord.filter(ScanRecord.Columns.deletedAt == nil).fetchCount(db) }
    }

    /// Borrado suave (deleted_at, rev + 1, dirty).
    func softDelete(id: String, now: Date = Date()) async throws {
        try await db.write { db in
            guard var scan = try ScanRecord.fetchOne(db, key: id) else { return }
            scan.deletedAt = now
            scan.touch(now: now)
            try scan.update(db)
        }
    }

    /// Borra todos los scans de un origen (p. ej. "Rehacer escaneo": `.library`).
    func deleteAll(source: ScanSource) async throws {
        _ = try await db.write { db in try ScanRecord.filter(ScanRecord.Columns.source == source.rawValue).deleteAll(db) }
    }

    /// Observación de los últimos scans (emite el valor actual y cada cambio).
    func observeRecent(limit: Int = 50) -> AsyncValueObservation<[ScanRecord]> {
        ValueObservation.tracking { db in try Self.recentRequest(limit: limit).fetchAll(db) }.values(in: db)
    }

    private static func recentRequest(limit: Int) -> QueryInterfaceRequest<ScanRecord> {
        ScanRecord
            .filter(ScanRecord.Columns.deletedAt == nil)
            .order(ScanRecord.Columns.scannedAt.desc)
            .limit(limit)
    }
}

// MARK: - unlocks

struct UnlockRepository: Sendable {
    let db: any DatabaseWriter

    init(_ database: AppDatabase) { db = database.writer }

    /// Desbloquea `comboId` si no lo estaba. Devuelve true si es nuevo (o si
    /// estaba borrado y se ha restaurado), false si ya estaba desbloqueado.
    @discardableResult
    func unlock(comboId: Int, source: ScanSource, assetLocalId: String? = nil, scanId: String? = nil,
                at date: Date = Date()) async throws -> Bool {
        try await db.write { db in
            try Self.unlockInTransaction(db, comboId: comboId, source: source, assetLocalId: assetLocalId,
                                         scanId: scanId, at: date)
        }
    }

    /// Desbloquea varios en una transacción; devuelve los ids nuevos en el orden dado.
    func unlock(comboIds: [Int], source: ScanSource, assetLocalId: String? = nil, scanId: String? = nil,
                at date: Date = Date()) async throws -> [Int] {
        try await db.write { db in
            var fresh: [Int] = []
            for id in comboIds where try Self.unlockInTransaction(db, comboId: id, source: source,
                                                                   assetLocalId: assetLocalId, scanId: scanId, at: date) {
                fresh.append(id)
            }
            return fresh
        }
    }

    private static func unlockInTransaction(_ db: Database, comboId: Int, source: ScanSource, assetLocalId: String?,
                                            scanId: String?, at date: Date) throws -> Bool {
        if var existing = try UnlockRecord.fetchOne(db, key: comboId) {
            guard existing.deletedAt != nil else { return false }
            existing.deletedAt = nil
            existing.firstSeenAt = date
            existing.source = source
            existing.assetLocalId = assetLocalId
            existing.scanId = scanId
            existing.touch(now: date)
            try existing.update(db)
            return true
        }
        try UnlockRecord(comboId: comboId, firstSeenAt: date, source: source, assetLocalId: assetLocalId,
                         scanId: scanId).insert(db)
        return true
    }

    func isUnlocked(comboId: Int) async throws -> Bool {
        try await db.read { db in
            try UnlockRecord.filter(UnlockRecord.Columns.comboId == comboId && UnlockRecord.Columns.deletedAt == nil)
                .fetchCount(db) > 0
        }
    }

    /// Todos los desbloqueos vivos, por combo_id ascendente.
    func all() async throws -> [UnlockRecord] {
        try await db.read { db in try Self.liveRequest.fetchAll(db) }
    }

    func unlockedIds() async throws -> Set<Int> {
        try await db.read { db in Set(try Self.liveRequest.fetchAll(db).map(\.comboId)) }
    }

    func count() async throws -> Int {
        try await db.read { db in try Self.liveRequest.fetchCount(db) }
    }

    /// Borra todos los desbloqueos de un origen (borrado físico; "Rehacer escaneo").
    func deleteAll(source: ScanSource? = nil) async throws {
        _ = try await db.write { db in
            if let source {
                try UnlockRecord.filter(Column("source") == source.rawValue).deleteAll(db)
            } else {
                try UnlockRecord.deleteAll(db)
            }
        }
    }

    /// Observación de los desbloqueos vivos (valor actual + cada cambio).
    func observeAll() -> AsyncValueObservation<[UnlockRecord]> {
        ValueObservation.tracking { db in try Self.liveRequest.fetchAll(db) }.values(in: db)
    }

    /// Observación del conjunto de ids desbloqueados (para la rejilla 348).
    func observeUnlockedIds() -> AsyncValueObservation<Set<Int>> {
        ValueObservation.tracking { db in Set(try Self.liveRequest.fetchAll(db).map(\.comboId)) }.values(in: db)
    }

    /// Observación del contador "41/348".
    func observeCount() -> AsyncValueObservation<Int> {
        ValueObservation.tracking { db in try Self.liveRequest.fetchCount(db) }.values(in: db)
    }

    private static var liveRequest: QueryInterfaceRequest<UnlockRecord> {
        UnlockRecord.filter(UnlockRecord.Columns.deletedAt == nil).order(UnlockRecord.Columns.comboId)
    }
}

// MARK: - feedback

struct FeedbackRepository: Sendable {
    let db: any DatabaseWriter

    init(_ database: AppDatabase) { db = database.writer }

    /// Registra un veredicto sobre un scan y devuelve el registro creado.
    @discardableResult
    func record(scanId: String, verdict: FeedbackVerdict, at date: Date = Date()) async throws -> FeedbackRecord {
        let record = FeedbackRecord(scanId: scanId, verdict: verdict, createdAt: date)
        try await db.write { db in try record.insert(db) }
        return record
    }

    /// Veredictos de un scan, más reciente primero.
    func forScan(id: String) async throws -> [FeedbackRecord] {
        try await db.read { db in
            try FeedbackRecord
                .filter(FeedbackRecord.Columns.scanId == id && FeedbackRecord.Columns.deletedAt == nil)
                .order(FeedbackRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Último veredicto de un scan (nil si no hay).
    func latest(forScan id: String) async throws -> FeedbackRecord? {
        try await forScan(id: id).first
    }

    func all() async throws -> [FeedbackRecord] {
        try await db.read { db in
            try FeedbackRecord.filter(FeedbackRecord.Columns.deletedAt == nil)
                .order(FeedbackRecord.Columns.createdAt.desc).fetchAll(db)
        }
    }

    /// Recuento (sí, no) de veredictos vivos.
    func counts() async throws -> (yes: Int, no: Int) {
        try await db.read { db in
            let yes = try FeedbackRecord.filter(Column("verdict") == FeedbackVerdict.yes.rawValue && FeedbackRecord.Columns.deletedAt == nil).fetchCount(db)
            let no = try FeedbackRecord.filter(Column("verdict") == FeedbackVerdict.no.rawValue && FeedbackRecord.Columns.deletedAt == nil).fetchCount(db)
            return (yes, no)
        }
    }

    /// Observación del último veredicto de un scan.
    func observeLatest(forScan id: String) -> AsyncValueObservation<FeedbackRecord?> {
        ValueObservation.tracking { db in
            try FeedbackRecord
                .filter(FeedbackRecord.Columns.scanId == id && FeedbackRecord.Columns.deletedAt == nil)
                .order(FeedbackRecord.Columns.createdAt.desc)
                .fetchOne(db)
        }.values(in: db)
    }
}

// MARK: - settings

struct SettingsRepository: Sendable {
    /// Claves conocidas (tabla `settings`, valor TEXT).
    enum Key: String, Sendable, CaseIterable {
        /// "true"/"false": máscara de persona (Vision) en el análisis. Apagado por defecto.
        case personMask = "person_mask"
        /// "true"/"false": el escaneo del carrete (día 0) ya se hizo.
        case initialScanDone = "initial_scan_done"
        /// ISO 8601 del último escaneo del carrete.
        case initialScanAt = "initial_scan_at"
        /// Entero: fotos analizadas en el último escaneo.
        case initialScanCount = "initial_scan_count"
    }

    let db: any DatabaseWriter

    init(_ database: AppDatabase) { db = database.writer }

    func get(_ key: Key) async throws -> String? {
        try await db.read { db in
            try SettingRecord.filter(SettingRecord.Columns.key == key.rawValue && SettingRecord.Columns.deletedAt == nil)
                .fetchOne(db)?.value
        }
    }

    /// Escribe (`value` nil = borrado suave).
    func set(_ key: Key, _ value: String?, now: Date = Date()) async throws {
        try await db.write { db in
            if var existing = try SettingRecord.fetchOne(db, key: key.rawValue) {
                if let value {
                    existing.value = value
                    existing.deletedAt = nil
                } else {
                    existing.deletedAt = now
                }
                existing.touch(now: now)
                try existing.update(db)
            } else if let value {
                try SettingRecord(key: key.rawValue, value: value, now: now).insert(db)
            }
        }
    }

    func bool(_ key: Key, default defaultValue: Bool = false) async throws -> Bool {
        guard let raw = try await get(key) else { return defaultValue }
        return raw == "true" || raw == "1"
    }

    func setBool(_ key: Key, _ value: Bool) async throws {
        try await set(key, value ? "true" : "false")
    }

    func int(_ key: Key, default defaultValue: Int = 0) async throws -> Int {
        guard let raw = try await get(key), let v = Int(raw) else { return defaultValue }
        return v
    }

    func setInt(_ key: Key, _ value: Int) async throws {
        try await set(key, String(value))
    }

    /// Observación del valor de una clave (nil si no existe o está borrada).
    func observe(_ key: Key) -> AsyncValueObservation<String?> {
        ValueObservation.tracking { db in
            try SettingRecord.filter(SettingRecord.Columns.key == key.rawValue && SettingRecord.Columns.deletedAt == nil)
                .fetchOne(db)?.value
        }.values(in: db)
    }
}
