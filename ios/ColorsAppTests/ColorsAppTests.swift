// Tests XCTest del stub de la fase 0: el motor C responde desde la app y el
// contador de lanzamientos persiste en disco.
import XCTest
@testable import ColorsApp

final class ColorsAppTests: XCTestCase {
    func testEngineVersionIsNotEmpty() {
        XCTAssertFalse(EngineFacts.engineVersion.isEmpty)
    }

    func testSharmaPair1DeltaE2000() {
        XCTAssertEqual(EngineFacts.sharmaPair1DeltaE, 2.0425, accuracy: 1e-4)
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
}
