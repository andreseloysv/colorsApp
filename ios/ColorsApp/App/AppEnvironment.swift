// Entorno de la app: diccionario, base de datos, repositorios, versiones del
// motor y runner del escaneo. Se crea una vez en `ColorsAppApp` y se inyecta
// con `.environmentObject`; las vistas lo reciben con
// `@EnvironmentObject var env: AppEnvironment`.
import Foundation
import Combine
import ColorEngine

@MainActor
final class AppEnvironment: ObservableObject {
    let dictionary: WadaDictionary
    let database: AppDatabase
    let scans: ScanRepository
    let unlocks: UnlockRepository
    let feedback: FeedbackRepository
    let settings: SettingsRepository
    /// `ce_version()` del motor C.
    let engineVersion: String
    /// `ce_dict_version()` embebida en el motor (== `dictionary.dictVersion`).
    let engineDictVersion: String
    /// Lanzamientos de la app (Documents/launches.txt; criterio de F0).
    let launches: Int
    /// Runner del escaneo del carrete: PhotoKitScanRunner en la app (bootstrap);
    /// NoopScanRunner en tests y previews salvo que se inyecte otro.
    private(set) var scanRunner: any ScanRunning
    /// Progreso del escaneo en curso, para la pestaña Hoy.
    @Published private(set) var scanProgress: ScanProgress = .idle

    /// `dict_version` del dictionary.json del bundle.
    var dictVersion: String { dictionary.dictVersion }
    /// Total de combinaciones (348), para el contador de la rejilla.
    var comboCount: Int { dictionary.combinations.count }

    init(dictionary: WadaDictionary, database: AppDatabase, scanRunner: any ScanRunning, launches: Int) {
        self.dictionary = dictionary
        self.database = database
        self.scans = ScanRepository(database)
        self.unlocks = UnlockRepository(database)
        self.feedback = FeedbackRepository(database)
        self.settings = SettingsRepository(database)
        self.engineVersion = colorEngineVersion
        self.engineDictVersion = dictionaryVersion
        self.launches = launches
        self.scanRunner = scanRunner
        attach(scanRunner)
    }

    /// Arranque real: diccionario del bundle (con comprobación de versión),
    /// base de datos en Application Support, contador de lanzamientos y el
    /// escaneo del carrete real (PhotoKitScanRunner; no pide acceso a Fotos hasta
    /// que se lanza un escaneo).
    static func bootstrap(bundle: Bundle = .main) throws -> AppEnvironment {
        let dictionary = try WadaDictionary.load(from: bundle)
        let database = try AppDatabase.open()
        let launches = (try? LaunchCounter.increment()) ?? LaunchCounter.read()
        let env = AppEnvironment(dictionary: dictionary, database: database, scanRunner: NoopScanRunner(), launches: launches)
        env.installPhotoKitScanRunner()
        return env
    }

    /// true si el proceso es el host de XCTest (no se presentan hojas automáticas).
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Entorno para tests y previews: base de datos en memoria, sin contador.
    static func forTesting(bundle: Bundle = .main, scanRunner: (any ScanRunning)? = nil) throws -> AppEnvironment {
        let dictionary = try WadaDictionary.load(from: bundle)
        return AppEnvironment(dictionary: dictionary, database: try AppDatabase.inMemory(),
                              scanRunner: scanRunner ?? NoopScanRunner(), launches: 0)
    }

    /// Sustituye el runner (fase 7: PhotoKitScanRunner).
    func setScanRunner(_ runner: any ScanRunning) {
        scanRunner = runner
        attach(runner)
    }

    /// Escaneo del carrete con el progreso publicado en `scanProgress`.
    func runInitialScan(limit: Int = 200) async throws -> ScanSummary {
        scanProgress = ScanProgress(phase: .requestingAccess)
        do {
            let summary = try await scanRunner.runInitialScan(limit: limit)
            scanProgress = scanRunner.progress
            return summary
        } catch {
            scanProgress = scanRunner.progress
            throw error
        }
    }

    private func attach(_ runner: any ScanRunning) {
        runner.onProgress = { [weak self] progress in
            self?.scanProgress = progress
        }
    }
}
