// Fidelidad visual del Feed al ejemplo del usuario (docs/design/FIDELITY.md §3): cabecera
// luminosa y barra de pestañas con sus medidas, personajes de la marca por pestaña, insignia
// «✦» del avatar ligada a combinaciones nuevas reales, argumentos de captura deterministas,
// y que las piezas nuevas (tarjeta del día, publicación, gotas, sol) se construyen en claro,
// oscuro y con «Reducir movimiento».
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

@MainActor
final class FeedFidelityTests: XCTestCase {
    private func size<V: View>(of view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, .large))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func testHeaderAndTabBarKeepTheExampleHeights() {
        XCTAssertEqual(size(of: FeedHeader(onAnalyze: {}, onGarden: {}), width: 402).height, Sizes.header)
        XCTAssertEqual(size(of: FeedHeader(newUnlocks: 3, onAnalyze: {}, onGarden: {}), width: 402).height, Sizes.header)
        let items = SolarTabs.standard(feed: AppTab.feed, extraer: .extraer, rejilla: .rejilla, jardin: .jardin)
        for style in [RootTabBar.Style.luminous, .standard] {
            XCTAssertEqual(size(of: RootTabBar(items: items, selection: .constant(.feed), style: style), width: 402).height, Sizes.tabBar)
        }
    }

    func testTabsUseTheOriginalBrandCharacters() {
        XCTAssertEqual(AppTab.allCases.map(\.brandKind), BrandTabIconKind.allCases)
        let items = SolarTabs.standard(feed: AppTab.feed, extraer: .extraer, rejilla: .rejilla, jardin: .jardin)
        for item in items {
            XCTAssertEqual(item.accessibilityIdentifier, item.tag.brandKind.tabIdentifier)
        }
        // Variante luminosa (Feed): sombra ámbar y filo; resto: sepia sin filo.
        XCTAssertEqual(RootTabBar.Style.luminous.bar, MotionSpec.tabBar)
        XCTAssertEqual(RootTabBar.Style.standard.bar.hairline.a, 0)
        XCTAssertEqual(RootTabBar.Style.standard.bar.shadow.blur, 12)
    }

    func testAvatarBadgeCountsOnlyNewUnlocks() {
        XCTAssertEqual(FeedView.newUnlocks(total: 12, seen: 9), 3)
        XCTAssertEqual(FeedView.newUnlocks(total: 4, seen: 9), 0)
        XCTAssertEqual(FeedView.newUnlocks(total: 4, seen: -2), 4)
        XCTAssertEqual(FeedGardenAvatarButton.accessibilityLabel(newUnlocks: 0), "Tu jardín")
        XCTAssertEqual(FeedGardenAvatarButton.accessibilityLabel(newUnlocks: 1), "Tu jardín, 1 combinación nueva")
        XCTAssertEqual(FeedGardenAvatarButton.accessibilityLabel(newUnlocks: 5), "Tu jardín, 5 combinaciones nuevas")
        XCTAssertNotEqual(FeedView.gardenSeenKey, FeedView.gardenSeenDemoKey)
    }

    /// Aloja una vista en una ventana propia y cuenta sus relojes ambientales (como MotionTests).
    private func hostedCounts<V: View>(_ view: V, scope: String) async throws -> (running: Int, registered: Int) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view.motionActivityScope(scope))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let counts = (MotionActivityMonitor.shared.runningCount(scope: scope), MotionActivityMonitor.shared.registeredCount(scope: scope))
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(nanoseconds: 300_000_000)
        return counts
    }

    func testFeedAmbientClocksRunVisibleAndPauseWhenHiddenOrReduced() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        func feed(enabled: Bool, reduce: Bool = false) -> some View {
            FeedView(garden: GardenStore(url: nil), photoStore: ScanPhotoStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("feed-fidelity-\(UUID().uuidString)", isDirectory: true)))
                .environmentObject(env)
                .environment(\.scenePhase, .active)
                .ambientMotion(enabled)
                .forceReducedMotion(reduce)
        }
        let visible = try await hostedCounts(feed(enabled: true), scope: "feed.visible")
        XCTAssertGreaterThanOrEqual(visible.running, 6, "motas, halo, anillos, sol, chip, barrido… deben correr: \(visible)")
        let hidden = try await hostedCounts(feed(enabled: false), scope: "feed.hidden")
        XCTAssertGreaterThan(hidden.registered, 0)
        XCTAssertEqual(hidden.running, 0, "pestaña oculta: ningún reloj ambiental en marcha")
        let reduced = try await hostedCounts(feed(enabled: true, reduce: true), scope: "feed.reduced")
        XCTAssertEqual(reduced.running, 0, "Reducir movimiento: todo quieto")
    }

    func testDebugMotionArguments() {
        let none = RootMotionDebugOverrides.parse(["ColorsApp"])
        XCTAssertNil(none.time)
        XCTAssertFalse(none.reduceMotion)
        let frozen = RootMotionDebugOverrides.parse(["ColorsApp", "-uiScreen", "feed-demo", "-uiMotionTime", "1.6", "-uiReduceMotion", "1"])
        XCTAssertEqual(frozen.time, 1.6)
        XCTAssertTrue(frozen.reduceMotion)
    }

    func testLuminousPiecesBuildInBothThemesAndReducedMotion() throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let colors = PaletteColor.combo(98, in: env.dictionary)
        XCTAssertFalse(colors.isEmpty)
        let palette = Array(PaletteColor.combo(250, in: env.dictionary).prefix(5))
        let content = FeedPostContent(source: .camera, metadata: "15 sept, 20:42 · Persona principal de 3", photo: nil,
                                      photoAspectRatio: 4.0 / 5.0, cropNotice: "Solo ropa", paletteTitle: "Paleta de la ropa",
                                      palette: palette, match: nil, verdict: .yes, isSaved: true)
        for scheme in [ColorScheme.light, .dark] {
            for reduce in [false, true] {
                let day = FeedDayCard(eyebrow: "Combinación del día", isToday: true, comboId: 98, numberLabel: "Nº 098",
                                      name: "Caoba y añil", colors: colors, status: "2 colores · En tu rejilla",
                                      onShuffle: {}, onOpen: {}, onCopyColor: { _ in })
                    .environment(\.colorScheme, scheme).forceReducedMotion(reduce).motionTime(1.25)
                let daySize = size(of: day, width: 370)
                XCTAssertGreaterThan(daySize.height, 150, "tarjeta del día \(scheme) reduce=\(reduce)")
                XCTAssertLessThan(daySize.height, 260, "tarjeta del día demasiado alta \(scheme) reduce=\(reduce)")
                let post = FeedLuminousPostCard(content: content, actions: FeedPostActions(onYes: {}, onNo: {}, onSave: {},
                                                                                          onCopyPalette: {}, onCopyColor: { _ in }),
                                                copiedColorIndex: 1)
                    .environment(\.colorScheme, scheme).forceReducedMotion(reduce)
                XCTAssertGreaterThan(size(of: post, width: 370).height, 500)
            }
        }
        XCTAssertEqual(size(of: FeedSunSpiritButton(action: {}), width: 100).height, Sizes.headerButton)
        XCTAssertGreaterThan(size(of: FeedBrassButton(title: "Otra combinación") {}, width: 346).height, 43)
        XCTAssertGreaterThan(size(of: FeedDropletWell(colors: palette), width: 322).height, Sizes.droplet)
    }
}
