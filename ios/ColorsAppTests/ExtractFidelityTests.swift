// Fidelidad de Extraer al ejemplo del usuario (docs/design/FIDELITY.md §4): valores exactos de las
// motas del visor (E8/M20), variantes de luz de los alfileres por L* del motor (E12–E16), insignia
// del avatar solo con combinaciones nuevas (E4), vaivén del brote del CTA (M8/M6), banda del barrido
// (E28–E29) y que la cabecera, la captura y el resultado se dibujan en claro, oscuro, con tiempo
// congelado y con «Reducir movimiento».
import XCTest
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class ExtractFidelityTests: XCTestCase {
    func testViewfinderMotesUseTheExampleValues() {
        let specs = ExtractViewfinderMotes.specs
        XCTAssertEqual(specs.count, 5)
        XCTAssertEqual(specs.map(\.mote.size), [12, 10, 14, 8, 6])
        XCTAssertEqual(specs.map(\.mote.clock.duration), [7, 8.5, 6.5, 9, 8.5])
        XCTAssertEqual(specs.map(\.mote.clock.delay), [0, 0, 0, 0, 1])
        XCTAssertEqual(specs.map(\.mote.glow.blur), [14, 16, 15, 12, 10])
        XCTAssertEqual(specs[0].mote.fill, MotionRGBA(hex: 0xFFDCC6))
        XCTAssertEqual(specs[3].mote.glow.color, MotionRGBA(253, 147, 63, 0.9))

        let size = CGSize(width: 370, height: 400)
        // `top-[18%] left-[22%] w-3 h-3` → centro (370·0,22 + 6, 400·0,18 + 6).
        let rest0 = specs[0].restCenter(in: size)
        XCTAssertEqual(rest0.x, 370 * 0.22 + 6, accuracy: 1e-9)
        XCTAssertEqual(rest0.y, 400 * 0.18 + 6, accuracy: 1e-9)
        // `top-[35%] right-[16%] w-2.5` → borde derecho a 16 % del ancho.
        XCTAssertEqual(specs[1].restCenter(in: size).x, 370 * 0.84 - 5, accuracy: 1e-9)

        let start = ExtractViewfinderMotes.frame(of: specs[0], at: 0, in: size)
        XCTAssertEqual(start.opacity, 0)
        XCTAssertEqual(start.center, rest0)
        let peak = ExtractViewfinderMotes.frame(of: specs[0], at: 7 * 0.2, in: size)
        XCTAssertEqual(peak.opacity, 0.8, accuracy: 1e-9)
        let eased = CubicBezierCurve.easeOut.value(at: 0.2)
        XCTAssertEqual(peak.center.x, rest0.x + 8 * eased, accuracy: 1e-6)
        XCTAssertEqual(peak.center.y, rest0.y - 40 * eased, accuracy: 1e-6)
        XCTAssertEqual(ExtractViewfinderMotes.frame(of: specs[4], at: 0.5, in: size).opacity, 0, "5.ª mota: 1 s de retraso")
    }

    func testPinToneComesFromEngineLightness() {
        XCTAssertEqual(ExtractPinTone.of(r: 0xE8, g: 0xDE, b: 0xC8), .light, "Windmill Linen del ejemplo: sin ping")
        XCTAssertEqual(ExtractPinTone.of(r: 0x2A, g: 0x48, b: 0x36), .dark, "Ancient Fern: aro verde claro")
        XCTAssertEqual(ExtractPinTone.of(r: 0xC4, g: 0x82, b: 0x3F), .mid, "Sunlit Brass: aro naranja")
        XCTAssertEqual(ExtractPinTone.of(r: 0xDD, g: 0x6E, b: 0x42), .mid)
        XCTAssertEqual(ExtractPinTone.light.sparkle, "✧")
        XCTAssertEqual(ExtractPinTone.mid.sparkle, "✦")
        // Umbrales sobre el L* del motor.
        let l = srgbToLab(r: 0xE8, g: 0xDE, b: 0xC8).L
        XCTAssertGreaterThan(l, 80)
    }

    func testAvatarBadgeOnlyWithNewUnlocks() {
        XCTAssertEqual(ExtractHeader.newUnlocks(count: 5, lastSeen: 3), 2)
        XCTAssertEqual(ExtractHeader.newUnlocks(count: 3, lastSeen: 5), 0)
        XCTAssertEqual(ExtractHeader.newUnlocks(count: 0, lastSeen: 0), 0)
        XCTAssertEqual(ExtractHeader.newUnlocks(count: 4, lastSeen: -1), 4)
        XCTAssertEqual(ExtractHeader.lastSeenUnlockKey, "jardin.lastSeenUnlockCount")
    }

    func testSproutSwayAndBudTimings() {
        XCTAssertEqual(SproutGlyph.pose(at: nil), SproutGlyph.Pose(), "Reducir movimiento: reposo")
        let peak = SproutGlyph.pose(at: 2.6 * 0.35)
        XCTAssertEqual(peak.rotation, 6, accuracy: 1e-6)
        XCTAssertEqual(peak.offsetY, -1, accuracy: 1e-6)
        let back = SproutGlyph.pose(at: 2.6 * 0.75)
        XCTAssertEqual(back.rotation, -5, accuracy: 1e-6)
        let bud = SproutGlyph.pose(at: 0.09)
        XCTAssertEqual(bud.budScaleY, 0.55, accuracy: 1e-6)
        XCTAssertEqual(ExtractMotion.bob(at: 1.6), -1.5, accuracy: 1e-6)
        XCTAssertEqual(ExtractMotion.bob(at: nil), 0)
        XCTAssertEqual(ExtractMotion.toastSeconds, 2.4)
    }

    func testShimmerBandCrossesTheWholeButton() {
        let w: CGFloat = 370
        let band = w * ExtractLuminousButton.shimmerBand
        XCTAssertEqual(ExtractLuminousButton.shimmerX(offset: -1, width: w, band: band), -band, accuracy: 1e-9)
        XCTAssertEqual(ExtractLuminousButton.shimmerX(offset: 1, width: w, band: band), w, accuracy: 1e-9)
        XCTAssertEqual(ExtractLuminousButton.shimmerX(offset: 0, width: w, band: band), (w - band) / 2, accuracy: 1e-9)
    }

    func testChromeCaptureAndResultRender() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let scene = SyntheticPersonScene.make()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-extract-fid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try await ScanAnalyzer.run(image: try XCTUnwrap(scene.image), source: .manual, subject: .default,
                                                 people: [scene.person], env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        let model = ResultViewModel(outcome: outcome, env: env, garden: GardenStore(url: nil))
        await model.load()
        for scheme in [ColorScheme.light, .dark] {
            for reduce in [false, true] {
                let page = VStack(spacing: 0) {
                    ExtractHeader(isResult: true, onSun: {}, onAvatar: {})
                    ExtractCaptureContent(state: .idle, onPick: {}, onCamera: {}, onScan: {})
                    ExtractResultContent(model: model, onOpenLayers: { _ in }, toast: .constant(nil))
                }
                .environmentObject(env)
                .padding(16)
                .frame(width: 402)
                .background(Theme.surface)
                .motionTime(reduce ? nil : 3.0)
                .forceReducedMotion(reduce)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: page)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage, "Extraer en \(scheme), reducir movimiento \(reduce)")
                XCTAssertEqual(image.size.width, 402)
                XCTAssertGreaterThan(image.size.height, 1500)
            }
        }
    }
}
