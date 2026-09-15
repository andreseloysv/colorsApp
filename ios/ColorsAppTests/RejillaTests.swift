// Rejilla (PLAN §7.5): con una AppDatabase temporal en disco, 3 desbloqueos
// dan el contador "3/348", el filtro por tamaño respeta los recuentos del
// diccionario, la observación sigue los cambios y la rejilla se renderiza.
import XCTest
import SwiftUI
@testable import ColorsApp

final class RejillaTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("colorsapp-rejilla-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    private func makeEnvironment() throws -> AppEnvironment {
        let dictionary = try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
        let database = try AppDatabase.open(at: tempDir.appendingPathComponent("colors.sqlite"))
        return AppEnvironment(dictionary: dictionary, database: database, scanRunner: NoopScanRunner(), launches: 0)
    }

    @MainActor
    func testThreeUnlocksGiveCounterThreeOf348() async throws {
        let env = try makeEnvironment()
        let fresh = try await env.unlocks.unlock(comboIds: [1, 200, 348], source: .library, assetLocalId: "asset-1")
        XCTAssertEqual(fresh, [1, 200, 348])

        let model = RejillaModel()
        XCTAssertFalse(model.loaded)
        XCTAssertEqual(model.counterText(total: env.comboCount), "0/348")
        try await model.refresh(env.unlocks)
        XCTAssertTrue(model.loaded)
        XCTAssertEqual(model.counterText(total: env.comboCount), "3/348")
        XCTAssertEqual(RejillaModel.counterText(unlocked: 41, total: 348), "41/348")
        XCTAssertEqual(model.unlockedIds, [1, 200, 348])
        XCTAssertTrue(model.isUnlocked(200))
        XCTAssertFalse(model.isUnlocked(2))
        XCTAssertEqual(model.unlock(for: 1)?.source, .library)
        XCTAssertEqual(model.unlock(for: 1)?.assetLocalId, "asset-1")

        // Sin filtro: las 348 en orden de id.
        XCTAssertEqual(model.combos(in: env.dictionary).map(\.id), Array(1...348))
        // Filtro por tamaño: 120 / 120 / 108 y los desbloqueos que caen en cada uno.
        model.sizeFilter = 2
        XCTAssertEqual(model.combos(in: env.dictionary).count, 120)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        model.sizeFilter = 3
        XCTAssertEqual(model.combos(in: env.dictionary).count, 120)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        model.sizeFilter = 4
        XCTAssertEqual(model.combos(in: env.dictionary).count, 108)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        model.sizeFilter = nil
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 3)
        // El contador global no depende del filtro.
        XCTAssertEqual(model.counterText(total: env.comboCount), "3/348")
    }

    @MainActor
    func testObservationFollowsUnlocks() async throws {
        let env = try makeEnvironment()
        let model = RejillaModel()
        let observing = Task { await model.observe(env.unlocks) }
        defer { observing.cancel() }
        try await waitUntil("valor inicial") { model.loaded }
        XCTAssertEqual(model.counterText(total: 348), "0/348")
        try await env.unlocks.unlock(comboIds: [5, 6, 7], source: .manual)
        try await waitUntil("3 desbloqueos") { model.unlockedCount == 3 }
        XCTAssertEqual(model.counterText(total: 348), "3/348")
        try await env.unlocks.unlock(comboId: 8, source: .camera)
        try await waitUntil("4 desbloqueos") { model.unlockedCount == 4 }
        XCTAssertEqual(model.unlockedIds, [5, 6, 7, 8])
        try await env.unlocks.deleteAll(source: .manual)
        try await waitUntil("solo la cámara") { model.unlockedIds == [8] }
        XCTAssertEqual(model.counterText(total: 348), "1/348")
    }

    @MainActor
    func testGridRendersWithUnlocks() async throws {
        let env = try makeEnvironment()
        try await env.unlocks.unlock(comboIds: [1, 200, 348], source: .library)
        let model = RejillaModel()
        try await model.refresh(env.unlocks)
        let content = RejillaContentView(model: model, dictionary: env.dictionary)
            .frame(width: 390, height: 844)
            .background(Color(.systemBackground))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "la rejilla no se renderiza")
        XCTAssertEqual(image.width, 780)
        XCTAssertEqual(image.height, 1688)
        // Una casilla desbloqueada (1: colores 65 y 117) y una bloqueada se renderizan solas.
        let combo = try XCTUnwrap(env.dictionary.combo(id: 1))
        let tile = ComboTile(combo: combo, colors: env.dictionary.colors(of: combo), unlocked: true)
            .frame(width: 60, height: 60)
        XCTAssertNotNil(ImageRenderer(content: tile).cgImage)
        let locked = ComboTile(combo: combo, colors: env.dictionary.colors(of: combo), unlocked: false)
            .frame(width: 60, height: 60)
        XCTAssertNotNil(ImageRenderer(content: locked).cgImage)
        let detail = RejillaComboDetailView(combo: combo, dictionary: env.dictionary, unlock: model.unlock(for: 1))
            .frame(width: 390, height: 500)
        XCTAssertNotNil(ImageRenderer(content: detail).cgImage)
        XCTAssertEqual(RejillaComboDetailView.sourceLabel(.library), "carrete")
    }

    func testCounterTextFormatting() {
        XCTAssertEqual(RejillaModel.counterText(unlocked: 0, total: 348), "0/348")
        XCTAssertEqual(RejillaModel.counterText(unlocked: 348, total: 348), "348/348")
    }

    // MARK: Utilidades

    @MainActor
    private func waitUntil(_ what: String, timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timeout esperando: \(what)")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
