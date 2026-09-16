// Movimiento y luz (ios/ColorsApp/Design/Motion): valores exactos del ejemplo del usuario
// (exampleDesign/…/code.html), curvas CSS contra valores de referencia calculados aparte
// (bisección en Python), fotogramas clave de cada efecto, política de pausa, y en vistas
// alojadas de verdad: con «Reducir movimiento» ningún reloj ambiental corre, en segundo
// plano o con `.ambientMotion(false)` tampoco, el dibujo con movimiento reducido no cambia
// con el tiempo y las motas de luz nunca pintan sobre un pocillo neutro.
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

@MainActor
final class MotionTests: XCTestCase {

    // MARK: Curvas CSS

    func testCubicBezierMatchesCSSReference() {
        // Referencias: bisección de 200 pasos sobre x(t) (script independiente).
        let cases: [(CubicBezierCurve, [Double])] = [
            (.easeOut, [0.308366, 0.378138, 0.684643, 0.906535]),
            (.easeInOut, [0.08166, 0.129162, 0.5, 0.870838]),
            (.ease, [0.295244, 0.408511, 0.802403, 0.960459]),
            (.tailwindPing, [0.5, 0.577573, 0.839245, 0.964216]),
            (.tailwindPulse, [0.086497, 0.135307, 0.5, 0.864693]),
        ]
        for (curve, expected) in cases {
            for (x, y) in zip([0.2, 0.25, 0.5, 0.75], expected) {
                XCTAssertEqual(curve.value(at: x), y, accuracy: 1e-4, "\(curve) en \(x)")
            }
            XCTAssertEqual(curve.value(at: 0), 0)
            XCTAssertEqual(curve.value(at: 1), 1)
        }
        XCTAssertEqual(CubicBezierCurve.linear.value(at: 0.37), 0.37)
    }

    func testAnimationClockDelayAndWrap() {
        let clock = AnimationClock(duration: 8.5, delay: 1.5)
        XCTAssertNil(clock.progress(at: 1.0), "durante el retraso no hay ciclo")
        XCTAssertEqual(try XCTUnwrap(clock.progress(at: 1.5)), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(clock.progress(at: 1.5 + 4.25)), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(clock.progress(at: 1.5 + 8.5 * 3 + 0.85)), 0.1, accuracy: 1e-9)
    }

    // MARK: Motas de luz

    func testMotesMatchExampleValues() {
        let m = MotionSpec.motes
        XCTAssertEqual(m.count, 5)
        // (tamaño, hex, alfa, blur, halo px, halo hex, left, bottom, duración, retraso)
        let expected: [(CGFloat, UInt32, Double, CGFloat, Double, UInt32, CGFloat, CGFloat, Double, Double)] = [
            (8, 0xFCD34D, 0.6, 1, 10, 0xFDE047, 0.12, 0.15, 7, 0),
            (10, 0x5EEAD4, 0.5, 1, 12, 0x5EEAD4, 0.78, 0.25, 8.5, 1.5),
            (6, 0xFDE68A, 0.7, 0.5, 8, 0xFEF08A, 0.45, 0.40, 6.5, 3),
            (8, 0x6EE7B7, 0.4, 1, 10, 0x6EE7B7, 0.88, 0.65, 9, 2),
            (6, 0xFCD34D, 0.5, 0, 6, 0xFCD34D, 0.28, 0.08, 7.8, 4.2),
        ]
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(m[i].size, e.0, "mota \(i)")
            XCTAssertEqual(m[i].fill, MotionRGBA(hex: e.1, alpha: e.2), "mota \(i)")
            XCTAssertEqual(m[i].blur, e.3, "mota \(i)")
            XCTAssertEqual(m[i].glow.blur, e.4, "mota \(i)")
            XCTAssertEqual(m[i].glow.radius, CGFloat(e.4 / 2), "mota \(i)")
            XCTAssertEqual(m[i].glow.color, MotionRGBA(hex: e.5), "mota \(i)")
            XCTAssertEqual(m[i].left, e.6, "mota \(i)")
            XCTAssertEqual(m[i].bottom, e.7, "mota \(i)")
            XCTAssertEqual(m[i].clock, AnimationClock(duration: e.8, delay: e.9), "mota \(i)")
        }
        XCTAssertEqual(MotionSpec.ambientFramesPerSecond, 30)
    }

    func testMoteFloatKeyframes() throws {
        let canvas = CGSize(width: 400, height: 800)
        let mote = MotionSpec.motes[0] // 7 s, sin retraso, 8 pt, left 12 %, bottom 15 %
        let rest = mote.restCenter(in: canvas)
        XCTAssertEqual(rest.x, 400 * 0.12 + 4, accuracy: 1e-9)
        XCTAssertEqual(rest.y, 800 * 0.85 - 4, accuracy: 1e-9)

        let f0 = mote.frame(at: 0, in: canvas)
        XCTAssertEqual(f0.opacity, 0)
        XCTAssertEqual(f0.center, rest)

        let f20 = mote.frame(at: 7 * 0.2, in: canvas)
        XCTAssertEqual(f20.opacity, 0.8, accuracy: 1e-9)
        XCTAssertEqual(f20.center.x - rest.x, 4.625491, accuracy: 1e-4)
        XCTAssertEqual(f20.center.y - rest.y, -37.003928, accuracy: 1e-4)

        let f50 = mote.frame(at: 3.5, in: canvas)
        XCTAssertEqual(f50.opacity, 0.663071, accuracy: 1e-4)
        XCTAssertEqual(f50.center.y - rest.y, -82.157182, accuracy: 1e-4)

        let f80 = mote.frame(at: 7 * 0.8, in: canvas)
        XCTAssertEqual(f80.opacity, 0.6, accuracy: 1e-9)

        let fEnd = mote.frame(at: 7 - 1e-9, in: canvas)
        XCTAssertEqual(fEnd.opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(fEnd.center.x - rest.x, 15, accuracy: 1e-5)
        XCTAssertEqual(fEnd.center.y - rest.y, -120, accuracy: 1e-5)

        // Mota con retraso de 1,5 s: oculta y quieta hasta que arranca.
        let delayed = MotionSpec.motes[1]
        let hidden = delayed.frame(at: 1.0, in: canvas)
        XCTAssertEqual(hidden.opacity, 0)
        XCTAssertEqual(hidden.center, delayed.restCenter(in: canvas))
        XCTAssertEqual(delayed.frame(at: 1.5 + 8.5 * 0.2, in: canvas).opacity, 0.8, accuracy: 1e-9)
    }

    // MARK: Halo, destello, giro, ping, pulso, barrido

    func testGlowPulseKeyframes() {
        let a = MotionSpec.glowPulseA, b = MotionSpec.glowPulseB
        XCTAssertEqual(a.inner, ShadowSpec(MotionRGBA(245, 158, 11, 0.25), blur: 16))
        XCTAssertEqual(a.outer, ShadowSpec(MotionRGBA(45, 90, 60, 0.15), blur: 30))
        XCTAssertEqual(a.border, MotionRGBA(234, 179, 8, 0.4))
        XCTAssertEqual(b.inner, ShadowSpec(MotionRGBA(45, 212, 191, 0.35), blur: 24))
        XCTAssertEqual(b.outer, ShadowSpec(MotionRGBA(245, 158, 11, 0.3), blur: 36))
        XCTAssertEqual(b.border, MotionRGBA(94, 234, 212, 0.5))
        XCTAssertEqual(MotionSpec.glowPulse.value(at: 0), a)
        XCTAssertEqual(MotionSpec.glowPulse.value(at: 0.5), b)
        XCTAssertEqual(MotionSpec.glowPulse.value(at: 1), a)
        // A mitad de tramo (ease-in-out = 0,5): radios SwiftUI 8→12 y 15→18 a medio camino.
        let mid = MotionSpec.glowPulse.value(at: 0.25)
        XCTAssertEqual(Double(mid.inner.radius), 10, accuracy: 1e-6)
        XCTAssertEqual(Double(mid.outer.radius), 16.5, accuracy: 1e-6)
        XCTAssertEqual(mid.border.a, 0.45, accuracy: 1e-6)
        // Tarjeta estática.
        XCTAssertEqual(MotionSpec.glowCard.inner, ShadowSpec(MotionRGBA(234, 179, 8, 0.22), blur: 18))
        XCTAssertEqual(MotionSpec.glowCard.outer, ShadowSpec(MotionRGBA(45, 90, 60, 0.12), blur: 28))
        XCTAssertEqual(MotionSpec.glowCard.border, MotionRGBA(234, 179, 8, 0.25))
    }

    func testSolarSparkleKeyframes() {
        XCTAssertEqual(MotionSpec.sparkleClock.duration, 12)
        let rest = SolarSparkleModifier.state(at: 0)
        XCTAssertEqual(rest.rotation, 0)
        XCTAssertEqual(rest.scale, 1)
        XCTAssertEqual(rest.shadow.radius, 3)
        XCTAssertEqual(rest.shadow.color, MotionRGBA(245, 158, 11, 0.6))
        let quarter = SolarSparkleModifier.state(at: 3)
        XCTAssertEqual(quarter.rotation, 90, accuracy: 1e-9)
        XCTAssertEqual(quarter.scale, 1.05, accuracy: 1e-9)
        let peak = SolarSparkleModifier.state(at: 6)
        XCTAssertEqual(peak.rotation, 180, accuracy: 1e-9)
        XCTAssertEqual(peak.scale, 1.1, accuracy: 1e-9)
        XCTAssertEqual(Double(peak.shadow.radius), 7, accuracy: 1e-9)
        XCTAssertEqual(peak.shadow.color.a, 0.9, accuracy: 1e-9)
        XCTAssertEqual(SolarSparkleModifier.state(at: 9).rotation, 90, accuracy: 1e-9, "vuelve: 180 → 0")
        XCTAssertEqual(SolarSparkleModifier.state(at: 12).rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(SolarSparkleModifier.state(at: nil), MotionSpec.sparkleRest, "reposo con «Reducir movimiento»")
    }

    func testSpinPingPulseShimmer() {
        XCTAssertEqual(MotionSpec.Spin.toast, 3)
        XCTAssertEqual(MotionSpec.Spin.brassButton, 6)
        XCTAssertEqual(MotionSpec.Spin.lensChip, 8)
        XCTAssertEqual(MotionSpec.Spin.sunDialRings, 25)
        XCTAssertEqual(SpinningModifier.angle(at: 0.75, duration: 3), 90, accuracy: 1e-9)
        XCTAssertEqual(SpinningModifier.angle(at: 3, duration: 3), 0, accuracy: 1e-9)
        XCTAssertEqual(SpinningModifier.angle(at: 6, duration: 8), 270, accuracy: 1e-9)
        XCTAssertEqual(SpinningModifier.angle(at: nil, duration: 8), 0)

        XCTAssertEqual(PingModifier.state(at: 0), ScaleOpacity(scale: 1, opacity: 1))
        let pingMid = PingModifier.state(at: 0.375)
        XCTAssertEqual(pingMid.scale, 1.839245, accuracy: 1e-4)
        XCTAssertEqual(pingMid.opacity, 0.160755, accuracy: 1e-4)
        XCTAssertEqual(PingModifier.state(at: 0.75).scale, 2, accuracy: 1e-9)
        XCTAssertEqual(PingModifier.state(at: 0.9), ScaleOpacity(scale: 2, opacity: 0))
        XCTAssertEqual(PingModifier.state(at: nil), ScaleOpacity(scale: 1, opacity: 1))

        XCTAssertEqual(PulseModifier.opacity(at: 0), 1)
        XCTAssertEqual(PulseModifier.opacity(at: 0.5), 0.75, accuracy: 1e-4)
        XCTAssertEqual(PulseModifier.opacity(at: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PulseModifier.opacity(at: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(PulseModifier.opacity(at: nil), 1)

        XCTAssertEqual(MotionSpec.shimmerClock.duration, 2.5)
        XCTAssertEqual(MotionSpec.shimmerPeakOpacity, 0.3)
        XCTAssertEqual(try XCTUnwrap(ShimmerSweepModifier<Capsule>.offset(at: 0)), -1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ShimmerSweepModifier<Capsule>.offset(at: 1.25)), 0.604806, accuracy: 1e-4)
        XCTAssertNil(ShimmerSweepModifier<Capsule>.offset(at: nil), "sin barrido con «Reducir movimiento»")
    }

    // MARK: Barras, sombras, pulsación

    func testFrostedBarsAndWarmShadowsMatchExample() {
        XCTAssertEqual(MotionSpec.header.tintOpacity, 0.85)
        XCTAssertEqual(MotionSpec.header.shadow, ShadowSpec(MotionRGBA(234, 179, 8, 0.1), blur: 14, y: 1))
        XCTAssertEqual(MotionSpec.header.hairline, MotionRGBA(245, 158, 11, 0.1))
        XCTAssertEqual(MotionSpec.tabBar.tintOpacity, 0.9)
        XCTAssertEqual(MotionSpec.tabBar.shadow, ShadowSpec(MotionRGBA(234, 179, 8, 0.12), blur: 16, y: -3))
        XCTAssertEqual(MotionSpec.tabBar.hairline, MotionRGBA(245, 158, 11, 0.15))

        XCTAssertEqual(WarmShadow.brassButton.layers, [ShadowSpec(MotionRGBA(234, 179, 8, 0.4), blur: 18)])
        XCTAssertEqual(WarmShadow.brassButton.pressedLayers, [ShadowSpec(MotionRGBA(234, 179, 8, 0.6), blur: 24)])
        XCTAssertEqual(WarmShadow.lensChipAmber.layers, [ShadowSpec(MotionRGBA(245, 158, 11, 0.3), blur: 12)])
        XCTAssertEqual(WarmShadow.lensChipTeal.layers, [ShadowSpec(MotionRGBA(45, 212, 191, 0.3), blur: 12)])
        XCTAssertEqual(WarmShadow.activeChip.layers, [ShadowSpec(MotionRGBA(45, 90, 60, 0.3), blur: 12)])
        XCTAssertEqual(WarmShadow.toast.layers, [ShadowSpec(MotionRGBA(245, 158, 11, 0.4), blur: 20)])
        XCTAssertEqual(WarmShadow.logo.layers, [ShadowSpec(MotionRGBA(245, 158, 11, 0.3), blur: 6)])
        XCTAssertEqual(WarmShadow.headerAvatar.layers, [ShadowSpec(MotionRGBA(245, 158, 11, 0.35), blur: 12)])
        XCTAssertEqual(WarmShadow.activeTab.layers, [ShadowSpec(MotionRGBA(188, 239, 199, 0.85), blur: 15)])
        XCTAssertEqual(MotionSpec.headerAvatarRing, MotionRGBA(252, 211, 77, 0.6))
        XCTAssertEqual(MotionSpec.lensChipAmberBorder, MotionRGBA(252, 211, 77, 0.4))
        XCTAssertEqual(MotionSpec.Glint.standard, 0.7)
        // En oscuro el halo musgo pasa a #A1D2AC con la misma opacidad; el resto no cambia.
        XCTAssertEqual(MotionSpec.activeChip.adapted(for: .dark), ShadowSpec(MotionRGBA(161, 210, 172, 0.3), blur: 12))
        XCTAssertEqual(MotionSpec.activeChip.adapted(for: .light), MotionSpec.activeChip)
        XCTAssertEqual(MotionSpec.toast.adapted(for: .dark), MotionSpec.toast)
    }

    func testPressScaleEffect() {
        let plain = PressScaleButtonStyle()
        XCTAssertTrue(PressScaleButtonStyle.effect(pressed: false, reduceMotion: false, style: plain) == (1, 0, 1))
        XCTAssertTrue(PressScaleButtonStyle.effect(pressed: true, reduceMotion: false, style: plain) == (0.95, 0, 1))
        let lift = PressScaleButtonStyle.pressLift(scale: 0.9)
        XCTAssertTrue(PressScaleButtonStyle.effect(pressed: true, reduceMotion: false, style: lift) == (0.9, -4, 1))
        XCTAssertEqual(lift.duration, 0.3)
        // Con «Reducir movimiento»: ni escala ni desplazamiento, solo un fundido.
        XCTAssertTrue(PressScaleButtonStyle.effect(pressed: true, reduceMotion: true, style: lift) == (1, 0, 0.8))
        XCTAssertEqual(PressScaleButtonStyle.pressScaleWide.scale, 0.98)
    }

    func testMotionPolicy() {
        let base = MotionPolicy(reduceMotion: false, scenePhase: .active, isVisible: true, isEnabled: true)
        XCTAssertTrue(base.isRunning)
        var p = base; p.reduceMotion = true
        XCTAssertFalse(p.isRunning); XCTAssertTrue(p.showsRestState)
        p = base; p.scenePhase = .background
        XCTAssertFalse(p.isRunning); XCTAssertFalse(p.showsRestState)
        p = base; p.scenePhase = .inactive
        XCTAssertFalse(p.isRunning)
        p = base; p.isVisible = false
        XCTAssertFalse(p.isRunning)
        p = base; p.isEnabled = false
        XCTAssertFalse(p.isRunning)
    }

    // MARK: Vistas alojadas: relojes en marcha o en pausa

    /// Aloja la galería de movimiento en una ventana propia y cuenta los relojes ambientales.
    private func hostedCounts<V: View>(_ view: V, scope: String) async throws -> (running: Int, registered: Int) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view.motionActivityScope(scope))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 900_000_000)
        let counts = (MotionActivityMonitor.shared.runningCount(scope: scope), MotionActivityMonitor.shared.registeredCount(scope: scope))
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(MotionActivityMonitor.shared.registeredCount(scope: scope), 0, "\(scope): quedaron efectos registrados al cerrar")
        return counts
    }

    private func gallery(_ page: MotionGalleryPage, phase: ScenePhase = .active) -> some View {
        MotionGalleryContent(page: .constant(page), dictionary: nil, sample: .empty, chip: .constant(0), tab: .constant(0))
            .environment(\.scenePhase, phase)
    }

    func testAmbientClocksRunNormallyAndStopWithReduceMotion() async throws {
        for page in MotionGalleryPage.allCases {
            let normal = try await hostedCounts(gallery(page), scope: "normal-\(page.rawValue)")
            XCTAssertGreaterThan(normal.registered, 5, "\(page): la galería debe tener efectos")
            XCTAssertGreaterThan(normal.running, 3, "\(page): en primer plano corren los efectos visibles")
            XCTAssertLessThanOrEqual(normal.running, normal.registered)

            let reduced = try await hostedCounts(gallery(page).forceReducedMotion(), scope: "reduced-\(page.rawValue)")
            XCTAssertGreaterThan(reduced.registered, 5)
            XCTAssertEqual(reduced.running, 0, "\(page): con «Reducir movimiento» no corre ningún reloj")

            let background = try await hostedCounts(gallery(page, phase: .background), scope: "bg-\(page.rawValue)")
            XCTAssertEqual(background.running, 0, "\(page): en segundo plano todo en pausa")

            let disabled = try await hostedCounts(gallery(page).ambientMotion(false), scope: "off-\(page.rawValue)")
            XCTAssertEqual(disabled.running, 0, "\(page): con .ambientMotion(false) todo en pausa")
        }
    }

    func testEffectsOffscreenInScrollViewArePaused() async throws {
        let view = ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 3000)
                Image(systemName: "sparkles").spinning(duration: 3)
                PingDot()
            }
        }
        .frame(width: 402, height: 874)
        .environment(\.scenePhase, .active)
        let counts = try await hostedCounts(view, scope: "offscreen")
        XCTAssertEqual(counts.registered, 2)
        XCTAssertEqual(counts.running, 0, "fuera del área visible del ScrollView no corre")
    }

    // MARK: Dibujo

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

    private var effectsSample: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill").font(.system(size: 30)).foregroundStyle(.orange).solarSparkle()
            Image(systemName: "camera.filters").font(.system(size: 30)).spinning(duration: 3)
            PingDot(color: .orange, size: 12, keepsCore: false)
            Capsule().fill(Color.brown).frame(width: 160, height: 36).shimmerSweep()
        }
        .background(Color.white)
    }

    func testReducedMotionDrawingDoesNotChangeOverTime() throws {
        let size = CGSize(width: 200, height: 180)
        let reduced0 = try pixels(effectsSample.forceReducedMotion().motionTime(0.4), size: size)
        let reduced1 = try pixels(effectsSample.forceReducedMotion().motionTime(1.7), size: size)
        XCTAssertEqual(reduced0, reduced1, "con «Reducir movimiento» el dibujo es el mismo en cualquier instante")
        let moving0 = try pixels(effectsSample.motionTime(0.4), size: size)
        let moving1 = try pixels(effectsSample.motionTime(1.7), size: size)
        XCTAssertNotEqual(moving0, moving1, "sin «Reducir movimiento» los efectos cambian con el tiempo")

        // Las motas: invisibles con «Reducir movimiento», visibles a mitad de ciclo sin él.
        let motesSize = CGSize(width: 300, height: 600)
        let hidden = try pixels(LightMotesOverlay().forceReducedMotion().motionTime(3.5), size: motesSize)
        XCTAssertEqual(hidden.enumerated().filter { $0.offset % 4 == 3 }.map(\.element).max(), 0)
        let shown = try pixels(LightMotesOverlay().motionTime(3.5), size: motesSize)
        XCTAssertGreaterThan(shown.enumerated().filter { $0.offset % 4 == 3 }.map(\.element).max() ?? 0, 60)
    }

    func testLightMotesNeverPaintOverNeutralWell() throws {
        // Mota grande colocada en el centro del pocillo, fotografiada en su máximo (20 % del ciclo).
        let big = MotionSpec.Mote(id: 9, size: 60, fill: TailwindColor.amber300.opacity(1), blur: 1,
                                  glow: ShadowSpec(TailwindColor.yellow300, blur: 20), left: 0.5 - 30 / 300, bottom: 0.5 - 30 / 300,
                                  clock: AnimationClock(duration: 1000))
        let view = ZStack {
            Color(rgb8: 252, 249, 241)
            SwatchWell(padding: 12, cornerRadius: 0) {
                HStack(spacing: 0) { Color(rgb8: 197, 83, 71); Color(rgb8: 18, 53, 78) }.frame(width: 120, height: 60)
            }
        }
        .frame(width: 300, height: 300)
        .lightMotes(motes: [big])
        // 20 % del ciclo: opacidad 0,8 y centro subido 37 pt (y ≈ 113), a caballo del borde superior del pocillo.
        let px = try pixels(view.motionTime(200), size: CGSize(width: 300, height: 300))
        func rgb(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * 300 + x) * 4; return [px[i], px[i + 1], px[i + 2]] }
        // Pocillo: x 78…222, y 108…192; swatches x 90…210, y 120…180. Relleno del pocillo: blanco exacto.
        for (x, y) in [(150, 114), (130, 112), (170, 115), (84, 150), (216, 150), (150, 186), (84, 114), (216, 186)] {
            XCTAssertEqual(rgb(x, y), [255, 255, 255], "pocillo (\(x),\(y))")
        }
        // Swatches intactos, también bajo la mota.
        XCTAssertEqual(rgb(140, 124), [197, 83, 71])
        XCTAssertEqual(rgb(190, 140), [18, 53, 78])
        // La mota sí pinta fuera del pocillo (justo encima de su borde superior).
        XCTAssertNotEqual(rgb(155, 96), [252, 249, 241], "la mota se ve fuera de la zona neutra")
    }

    // MARK: Reposo y Ahorro de energía (FIDELITY.md §1.1)

    func testMotionPolicyStopsWhenIdleOrLowPower() {
        let base = MotionPolicy(reduceMotion: false, scenePhase: .active, isVisible: true, isEnabled: true)
        XCTAssertTrue(base.isRunning)
        XCTAssertEqual(base.activity, .active)
        var p = base; p.activity = .idle
        XCTAssertFalse(p.isRunning, "tras 30 s sin tocar la pantalla el ambiente se para")
        XCTAssertFalse(p.showsRestState, "el reposo congela el último fotograma, no salta a la pose de reposo")
        p = base; p.activity = .lowPower
        XCTAssertFalse(p.isRunning, "en Ahorro de energía el ambiente se para")
        p = base; p.activity = AmbientActivityState(isIdle: true, isLowPower: true)
        XCTAssertFalse(p.isRunning)
        XCTAssertTrue(AmbientActivityState.active.allowsAmbientMotion)
        XCTAssertFalse(AmbientActivityState.idle.allowsAmbientMotion)
        XCTAssertFalse(AmbientActivityState.lowPower.allowsAmbientMotion)
    }

    func testAmbientClocksStopWhenIdleOrLowPower() async throws {
        let page = MotionGalleryPage.feed
        let running = try await hostedCounts(gallery(page), scope: "activity-on")
        XCTAssertGreaterThan(running.running, 3, "en actividad normal corren los efectos visibles")
        let idle = try await hostedCounts(gallery(page).ambientActivity(.idle), scope: "activity-idle")
        XCTAssertEqual(idle.running, 0, "en reposo ningún reloj ambiental corre")
        XCTAssertEqual(idle.registered, running.registered)
        let lowPower = try await hostedCounts(gallery(page).ambientActivity(.lowPower), scope: "activity-lowpower")
        XCTAssertEqual(lowPower.running, 0, "en Ahorro de energía ningún reloj ambiental corre")
    }

    /// El reloj de reposo con el retraso acortado por argumento de depuración: entra en
    /// reposo solo y vuelve al primer toque.
    func testAmbientActivityMonitorGoesIdleAndWakesUp() async throws {
        let monitor = AmbientActivityMonitor()
        monitor.applyDebugArguments(["-uiAmbientIdleDelay", "0.25"])
        monitor.start()
        defer { monitor.stop() }
        XCTAssertFalse(monitor.state.isIdle, "recién arrancado está activo")
        try await Task.sleep(nanoseconds: 900_000_000)
        try XCTSkipUnless(monitor.isWatchingTouches, "sin ventana no hay vigilancia de toques y no hay reposo")
        XCTAssertTrue(monitor.state.isIdle, "sin toques pasa a reposo")
        monitor.noteActivity()
        XCTAssertFalse(monitor.state.isIdle, "un toque lo despierta en el acto")
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(monitor.state.isIdle, "y vuelve a dormirse")
    }

    /// El gesto que ve los toques queda instalado en la ventana y no le roba nada a nadie.
    func testAmbientActivityWatchesWindowTouchesWithoutStealingThem() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let monitor = AmbientActivityMonitor()
        monitor.applyDebugArguments(["-uiAmbientIdleDelay", "0.25"])
        monitor.start()
        defer { monitor.stop() }
        let gesture = try XCTUnwrap(monitor.touchRecognizer, "el gesto no se enganchó a la ventana")
        XCTAssertNotNil(gesture.view, "el gesto debe vivir en una ventana")
        XCTAssertTrue(monitor.isWatchingTouches)
        let press = try XCTUnwrap(gesture as? UILongPressGestureRecognizer)
        XCTAssertEqual(press.minimumPressDuration, 0)
        XCTAssertFalse(press.cancelsTouchesInView, "no puede robarle el toque a los botones")
        XCTAssertFalse(press.delaysTouchesBegan)
        XCTAssertFalse(press.delaysTouchesEnded)
        XCTAssertTrue(monitor.gestureRecognizer(press, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()),
                      "reconoce a la vez que cualquier otro gesto")
        // Y con el gesto puesto, el reposo sí llega.
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(monitor.state.isIdle)
        monitor.stop()
        XCTAssertNil(monitor.touchRecognizer)
    }

    /// Sin ventana donde mirar los toques no se declara el reposo (si no, el ambiente se
    /// quedaría congelado sin forma de despertarlo).
    func testAmbientActivityNeverIdlesWithoutATouchWatcher() async throws {
        let monitor = AmbientActivityMonitor()
        monitor.applyDebugArguments(["-uiAmbientIdleDelay", "0.25"])
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(nanoseconds: 900_000_000)
        if monitor.isWatchingTouches {
            XCTAssertTrue(monitor.state.isIdle, "con gesto enganchado sí hay reposo")
        } else {
            XCTAssertFalse(monitor.state.isIdle, "sin gesto enganchado nunca se declara el reposo")
        }
    }

    func testAmbientActivityDebugArgumentsForceState() {
        let idle = AmbientActivityMonitor()
        idle.applyDebugArguments(["-uiAmbientIdle", "1"])
        XCTAssertEqual(idle.state, .idle)
        idle.noteActivity()
        XCTAssertEqual(idle.state, .idle, "el estado forzado no se despierta con un toque")
        let low = AmbientActivityMonitor()
        low.applyDebugArguments(["-uiAmbientLowPower", "1"])
        XCTAssertEqual(low.state, .lowPower)
        let none = AmbientActivityMonitor()
        none.applyDebugArguments(["-uiScreen", "feed-demo"])
        XCTAssertEqual(none.state, .active)
    }

    // MARK: Pestañas inactivas

    func testMoteClockIsTwentyFramesPerSecond() {
        XCTAssertEqual(MotionSpec.moteFramesPerSecond, 20)
        XCTAssertEqual(MotionSpec.moteFrameInterval, 1.0 / 20, accuracy: 1e-12)
        XCTAssertEqual(MotionSpec.TabIdle.framesPerSecond, 15)
    }

    /// Las pestañas inactivas se mueven con los mismos tiempos y amplitud reducida.
    func testInactiveTabPoseIsDampedButMoving() {
        for kind in BrandTabIconKind.allCases {
            XCTAssertEqual(BrandMotion.ambientPose(kind, at: nil), .rest, "\(kind): sin tiempo, reposo")
            let poses = stride(from: 0.0, through: 3.2, by: 0.1).map { BrandMotion.ambientPose(kind, at: $0) }
            XCTAssertGreaterThan(Set(poses.map { "\($0.offsetY)|\($0.rotation)|\($0.scaleX)|\($0.scaleY)" }).count, 8,
                                 "\(kind): la pestaña inactiva no se mueve")
            // Amplitud: como mucho el 45 % de la de la activa, y nunca ping ni alas.
            let phase = MotionSpec.TabIdle.phase(kind)
            for t in stride(from: 0.0, through: 3.2, by: 0.05) {
                let active = BrandMotion.pose(kind, at: t + phase, active: true, reduceMotion: false)
                let idleP = BrandMotion.ambientPose(kind, at: t)
                XCTAssertEqual(idleP.rotation, active.rotation * MotionSpec.TabIdle.amplitude, accuracy: 1e-9)
                XCTAssertEqual(idleP.offsetY, active.offsetY * MotionSpec.TabIdle.amplitude, accuracy: 1e-9)
                XCTAssertEqual(idleP.scaleY, 1 + (active.scaleY - 1) * MotionSpec.TabIdle.amplitude, accuracy: 1e-9)
                XCTAssertEqual(idleP.pingOpacity, 0, "\(kind): la inactiva no lleva anillo de ping")
                XCTAssertEqual(idleP.wingScaleY, 1, "\(kind): las alas quedan quietas en la inactiva")
                XCTAssertEqual(idleP.eyeScaleY, active.eyeScaleY, accuracy: 1e-9, "el parpadeo se conserva entero")
            }
        }
        // Amplitud 0 = exactamente la pose de reposo.
        XCTAssertEqual(BrandMotion.ambientPose(.feed, at: 1.1, amplitude: 0).offsetY, 0)
    }

    func testInactiveTabIconRendersMovingUnlessReducedOrIdle() throws {
        let size = CGSize(width: 56, height: 56)
        for kind in BrandTabIconKind.allCases {
            let a = try pixels(BrandTabIcon(kind: kind, isActive: false, size: 48).motionTime(0.3), size: size)
            let b = try pixels(BrandTabIcon(kind: kind, isActive: false, size: 48).motionTime(1.45), size: size)
            XCTAssertNotEqual(a, b, "\(kind): el icono inactivo debe moverse")
            let still0 = try pixels(BrandTabIcon(kind: kind, isActive: false, size: 48).forceReducedMotion().motionTime(0.3), size: size)
            let still1 = try pixels(BrandTabIcon(kind: kind, isActive: false, size: 48).forceReducedMotion().motionTime(1.45), size: size)
            XCTAssertEqual(still0, still1, "\(kind): con «Reducir movimiento» el icono inactivo queda quieto")
        }
    }
}

private func == (lhs: (CGFloat, CGFloat, Double), rhs: (CGFloat, CGFloat, Double)) -> Bool {
    abs(lhs.0 - rhs.0) < 1e-9 && abs(lhs.1 - rhs.1) < 1e-9 && abs(lhs.2 - rhs.2) < 1e-9
}
