// Pantallas secundarias con el marco solarpunk (docs/design/FIDELITY.md §7.5): Ajustes,
// «Acerca de», licencias de fuentes y el flujo de escaneo del carrete. Comprueba la
// geometría de la cabecera de marca, que las vistas se construyen en claro y oscuro, que
// el punto de la marca se mueve con el tiempo y queda QUIETO con «Reducir movimiento», y
// que el visor de capas sigue siendo neutro a propósito (sin luces de color).
import XCTest
import SwiftUI
import UIKit
import SubjectKit
@testable import ColorsApp

@MainActor
final class SecondaryScreensFidelityTests: XCTestCase {

    // MARK: Cabecera

    func testSecondaryHeaderMatchesHeaderMetrics() {
        for scheme in [ColorScheme.light, .dark] {
            let header = SecondaryHeader(section: "Ajustes", identifier: "ajustes.header")
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, .large)
            XCTAssertEqual(size(of: header, width: 402).height, Sizes.header, "\(scheme)")
        }
        // La hoja del escaneo usa el aspa en vez de la flecha.
        XCTAssertEqual(SecondaryHeader<EmptyView>.Leading.back.symbol, "chevron.left")
        XCTAssertEqual(SecondaryHeader<EmptyView>.Leading.close.symbol, "xmark")
        XCTAssertNil(SecondaryHeader<EmptyView>.Leading.none.symbol)
        XCTAssertEqual(SecondaryHeader<EmptyView>.Leading.back.label, "Volver")
        XCTAssertNotNil(ImageRenderer(content: SecondaryHeader(section: "Acerca de").frame(width: 402)).uiImage)
    }

    /// El ambiente de la cabecera (punto ámbar con ping y emblema) se mueve; con «Reducir
    /// movimiento» el dibujo es idéntico en cualquier instante (FIDELITY.md §8.3-3 y §8.3-4).
    func testSecondaryHeaderMovesAndStopsWithReduceMotion() throws {
        let size = CGSize(width: 402, height: Sizes.header)
        let header = SecondaryHeader(section: "Ajustes").background(Color.white)
        let a = try pixels(header.motionTime(0).environment(\.brandFrozenTime, 0), size: size)
        let b = try pixels(header.motionTime(0.6).environment(\.brandFrozenTime, 0.6), size: size)
        XCTAssertNotEqual(a, b, "la cabecera de una pantalla secundaria debe moverse")

        let quiet0 = try pixels(header.forceReducedMotion().motionTime(0)
            .environment(\.brandReduceMotionOverride, true).environment(\.brandFrozenTime, 0), size: size)
        let quiet1 = try pixels(header.forceReducedMotion().motionTime(1.25)
            .environment(\.brandReduceMotionOverride, true).environment(\.brandFrozenTime, 1.25), size: size)
        XCTAssertEqual(quiet0, quiet1, "con «Reducir movimiento» la cabecera queda quieta")
    }

    // MARK: Pantallas

    func testSecondaryScreensBuildInBothSchemes() throws {
        let env = try AppEnvironment.forTesting()
        for scheme in [ColorScheme.light, .dark] {
            let licenses = UIHostingController(rootView: NavigationStack { FontLicensesView() }
                .environmentObject(env).environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(licenses.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100, "licencias \(scheme)")
            let entry = try XCTUnwrap(FontLicenses.entries.first)
            let text = UIHostingController(rootView: NavigationStack { FontLicenseTextView(entry: entry) }
                .environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(text.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100, "licencia \(scheme)")
            let scan = UIHostingController(rootView: ScanOnboardingView(onSkip: {})
                .environmentObject(env).environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(scan.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100, "escaneo \(scheme)")
        }
        // «Acerca de» enlaza las licencias y sigue citando las dos fuentes OFL.
        XCTAssertEqual(FontLicenses.entries.map(\.family), ["Literata", "Plus Jakarta Sans"])
    }

    /// El resultado empujado desde el Feed lleva la misma cabecera de marca (sin la barra del sistema).
    func testResultViewBuildsWithBrandHeader() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: SubjectOptions(mode: .off), env: env)
        for scheme in [ColorScheme.light, .dark] {
            let model = ResultViewModel(outcome: outcome, env: env, garden: GardenStore(url: nil))
            let host = UIHostingController(rootView: NavigationStack { ResultView(model: model) }
                .environmentObject(env).environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(host.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100, "resultado \(scheme)")
        }
    }

    /// El visor de capas se queda neutro A PROPÓSITO (FIDELITY.md §7.5): fondo #121212 y
    /// pocillos #303030, sin pergamino ni luces de color, porque es la pantalla de juicio.
    func testLayersInspectorStaysNeutral() {
        for scheme in [ColorScheme.light, .dark] {
            let backdrop = ThemeTokens.storyBackdrop.rgb8(for: scheme)
            XCTAssertEqual(backdrop.r, backdrop.g, "el fondo del visor de capas no es neutro (\(scheme))")
            XCTAssertEqual(backdrop.g, backdrop.b, "el fondo del visor de capas no es neutro (\(scheme))")
            XCTAssertEqual(backdrop.r, 0x12)
            let well = ThemeTokens.wellFill.rgb8(for: scheme)
            XCTAssertEqual(well.r, well.g)
            XCTAssertEqual(well.g, well.b)
        }
    }

    /// Los atajos de depuración que analizan una foto de EJEMPLO arrancan con base en memoria:
    /// su cosecha de muestra no puede aparecer en el Jardín ni en el Feed reales.
    func testFixtureDebugScreensUseInMemoryDatabase() {
        for screen in [DebugLaunch.Screen.resultDemo, .resultPeople, .resultPeopleMask, .layersPeople,
                       .layersDemo, .resultDemoPerson, .resultDemoPeople, .resultDemoPeopleMask] {
            XCTAssertTrue(screen.analyzesFixture, "\(screen)")
        }
        for screen in [DebugLaunch.Screen.feed, .extraer, .rejilla, .jardin, .ajustes, .explorar(67),
                       .feedDemo, .feedEmpty] {
            XCTAssertFalse(screen.analyzesFixture, "\(screen)")
        }
    }

    // MARK: Utilidades

    private func size<V: View>(of view: V, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private func pixels<V: View>(_ view: V, size: CGSize, scheme: ColorScheme = .light) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
}
