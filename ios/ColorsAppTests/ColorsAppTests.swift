// Tests heredados del stub de la fase 0: el motor C responde desde la app y el
// contador de lanzamientos persiste en disco.
import XCTest
import ColorEngine
@testable import ColorsApp

final class ColorsAppTests: XCTestCase {
    func testEngineVersionIsNotEmpty() {
        XCTAssertFalse(colorEngineVersion.isEmpty)
        XCTAssertEqual(colorEngineVersion, "0.1.0")
    }

    func testSharmaPair1DeltaE2000() {
        // Par 1 del test set de Sharma, Wu y Dalal (2005): ΔE00 esperado 2.0425.
        let x = Lab(L: 50.0000, a: 2.6772, b: -79.7751)
        let y = Lab(L: 50.0000, a: 0.0000, b: -82.7485)
        XCTAssertEqual(deltaE2000(x, y), 2.0425, accuracy: 1e-4)
    }

    func testLaunchCounterPersistsInDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("colorsapp-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(LaunchCounter.read(in: dir), 0)
        XCTAssertEqual(try LaunchCounter.increment(in: dir), 1)
        XCTAssertEqual(try LaunchCounter.increment(in: dir), 2)
        XCTAssertEqual(LaunchCounter.read(in: dir), 2)
    }

    @MainActor
    func testAppEnvironmentForTestingBootstraps() throws {
        let env = try AppEnvironment.forTesting()
        XCTAssertEqual(env.dictionary.combinations.count, 348)
        XCTAssertEqual(env.engineDictVersion, env.dictVersion)
        XCTAssertEqual(env.comboCount, 348)
        XCTAssertEqual(env.scanProgress, .idle)
    }

    @MainActor
    func testNoopScanRunnerThrowsNotImplemented() async throws {
        let env = try AppEnvironment.forTesting()
        do {
            _ = try await env.runInitialScan(limit: 10)
            XCTFail("NoopScanRunner debería lanzar notImplemented")
        } catch let error as ScanError {
            XCTAssertEqual(error, .notImplemented)
        }
        XCTAssertEqual(env.scanProgress.phase, .failed)
    }
}
