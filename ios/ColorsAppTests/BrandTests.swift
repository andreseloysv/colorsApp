// Marca ChromaSol (Design/Brand): el emblema y los cuatro iconos de pestaña se renderizan
// en claro y en oscuro (con tinta distinta), las poses siguen los tiempos de code.html del
// ejemplo, Reduce Motion deja todo en reposo (y el reloj no corre) y el icono de la app
// está en el catálogo (1024 × 1024, opaco) y registrado en el Info.plist compilado.
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

@MainActor
final class BrandTests: XCTestCase {

    // MARK: Render en claro y oscuro

    func testTabIconsRenderInLightAndDark() throws {
        for kind in BrandTabIconKind.allCases {
            let light = try render(BrandTabIconFrame(kind: kind, size: 48).environment(\.colorScheme, .light))
            let dark = try render(BrandTabIconFrame(kind: kind, size: 48).environment(\.colorScheme, .dark))
            XCTAssertEqual(light.width, dark.width)
            XCTAssertGreaterThan(opaqueFraction(light), 0.12, "\(kind): icono casi vacío en claro")
            XCTAssertGreaterThan(opaqueFraction(dark), 0.12, "\(kind): icono casi vacío en oscuro")
            // En oscuro los trazos cambian de tinta: los píxeles no pueden ser idénticos.
            XCTAssertGreaterThan(difference(light, dark), 0.002, "\(kind): el tema oscuro no cambia la tinta")
        }
    }

    func testEmblemRendersAllStylesInLightAndDark() throws {
        for style in ChromaSolEmblemStyle.allCases {
            let light = try render(ChromaSolEmblem(style: style, scheme: .light).frame(width: 96, height: 96))
            let dark = try render(ChromaSolEmblem(style: style, scheme: .dark).frame(width: 96, height: 96))
            XCTAssertGreaterThan(opaqueFraction(light), 0.5, "\(style)")
            XCTAssertGreaterThan(difference(light, dark), 0.02, "\(style): claro y oscuro iguales")
        }
        // Tamaño de cabecera (32 pt, estilo compacto automático).
        XCTAssertEqual(ChromaSolLogo(size: 32).resolvedStyle, .compact)
        XCTAssertEqual(ChromaSolLogo(size: 96).resolvedStyle, .full)
        XCTAssertNotNil(ImageRenderer(content: ChromaSolLockup(section: "FEED")).uiImage)
    }

    func testActivePoseChangesTheDrawingOverTime() throws {
        for kind in BrandTabIconKind.allCases {
            let a = try render(BrandTabIconFrame(kind: kind, pose: BrandMotion.pose(kind, at: 0.0, active: true, reduceMotion: false), size: 48))
            let b = try render(BrandTabIconFrame(kind: kind, pose: BrandMotion.pose(kind, at: 0.75, active: true, reduceMotion: false), size: 48))
            XCTAssertGreaterThan(difference(a, b), 0.001, "\(kind): la animación no mueve el dibujo")
        }
    }

    // MARK: Tiempos del ejemplo

    func testKeyframeTimingsMatchExample() {
        XCTAssertEqual(BrandKeyframes.bounce.duration, 2.2)
        XCTAssertEqual(BrandKeyframes.blink.duration, 3.4)
        XCTAssertEqual(BrandKeyframes.flutter.duration, 2)
        XCTAssertEqual(BrandKeyframes.wings.duration, 0.18)
        XCTAssertEqual(BrandKeyframes.bob.duration, 3.2)
        XCTAssertEqual(BrandKeyframes.sway.duration, 2.6)
        XCTAssertEqual(BrandKeyframes.sparkle.duration, 12)
        XCTAssertLessThanOrEqual(BrandMotion.maxFramesPerSecond, 30)

        // Bote al 50 %: translateY(-5px) scale(1.04, 0.96).
        let mid = BrandMotion.pose(.feed, at: 1.1, active: true, reduceMotion: false)
        XCTAssertEqual(mid.offsetY, -5, accuracy: 1e-9)
        XCTAssertEqual(mid.scaleX, 1.04, accuracy: 1e-9)
        XCTAssertEqual(mid.scaleY, 0.96, accuracy: 1e-9)
        // Parpadeo al 96 %: scaleY(0.1).
        XCTAssertEqual(BrandMotion.pose(.feed, at: 3.4 * 0.96, active: true, reduceMotion: false).eyeScaleY, 0.1, accuracy: 1e-9)
        // dragonfly-flutter 25 %: rotate(-5deg) scale(1.05); wing-vibrate 50 %: opacity .3, scaleY .55.
        let flutter = BrandMotion.pose(.extraer, at: 0.5, active: true, reduceMotion: false)
        XCTAssertEqual(flutter.rotation, -5, accuracy: 1e-9)
        XCTAssertEqual(flutter.scaleX, 1.05, accuracy: 1e-9)
        let wings = BrandMotion.pose(.extraer, at: 0.09, active: true, reduceMotion: false)
        XCTAssertEqual(wings.wingOpacity, 0.3, accuracy: 1e-6)
        XCTAssertEqual(wings.wingScaleY, 0.55, accuracy: 1e-6)
        // Balanceos: 25 % de 3,2 s → −8°; 35 % de 2,6 s → 6°.
        XCTAssertEqual(BrandMotion.pose(.rejilla, at: 0.8, active: true, reduceMotion: false).rotation, -8, accuracy: 1e-9)
        XCTAssertEqual(BrandMotion.pose(.jardin, at: 0.91, active: true, reduceMotion: false).rotation, 6, accuracy: 1e-9)
        // solar-sparkle 50 %: rotate(180deg) scale(1.1) drop-shadow 14px 0.9; lineal: 25 % → 90°.
        let sun = BrandMotion.sparkle(at: 6, animated: true, reduceMotion: false)
        XCTAssertEqual(sun.rotation, 180, accuracy: 1e-9)
        XCTAssertEqual(sun.scale, 1.1, accuracy: 1e-9)
        XCTAssertEqual(sun.glowBlur, 14, accuracy: 1e-9)
        XCTAssertEqual(BrandMotion.sparkle(at: 3, animated: true, reduceMotion: false).rotation, 90, accuracy: 1e-9)
        // ease-in-out es simétrica y monótona.
        let curve = CSSTimingCurve.easeInOut
        XCTAssertEqual(curve.value(at: 0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(curve.value(at: 0.25) + curve.value(at: 0.75), 1, accuracy: 1e-6)
        XCTAssertLessThan(curve.value(at: 0.25), 0.25)
    }

    // MARK: Reduce Motion

    func testReduceMotionFreezesEveryPose() {
        let times: [Double] = [0, 0.09, 0.4, 0.8, 1.1, 1.7, 2.5, 3.264, 5.9, 11.3]
        for kind in BrandTabIconKind.allCases {
            for t in times {
                XCTAssertEqual(BrandMotion.pose(kind, at: t, active: true, reduceMotion: true), .rest, "\(kind) t=\(t)")
                XCTAssertEqual(BrandMotion.pose(kind, at: t, active: false, reduceMotion: false), .rest, "inactivo \(kind) t=\(t)")
            }
        }
        for t in times {
            XCTAssertEqual(BrandMotion.sparkle(at: t, animated: true, reduceMotion: true), .rest)
            XCTAssertEqual(BrandMotion.halo(at: t, reduceMotion: true), .rest)
            XCTAssertEqual(BrandMotion.wordmarkPing(at: t, reduceMotion: true).opacity, 0)
        }
        XCTAssertFalse(BrandMotion.isRunning(animated: true, reduceMotion: true, sceneActive: true))
        XCTAssertFalse(BrandMotion.isRunning(animated: true, reduceMotion: false, sceneActive: false), "en segundo plano no corre")
        XCTAssertFalse(BrandMotion.isRunning(animated: false, reduceMotion: false, sceneActive: true), "inactivo no corre")
        XCTAssertTrue(BrandMotion.isRunning(animated: true, reduceMotion: false, sceneActive: true))
    }

    /// Con Reduce Motion forzado, el icono activo pinta lo mismo en cualquier instante; sin él, cambia.
    func testReduceMotionRendersIdenticalFramesAtAnyTime() throws {
        for kind in BrandTabIconKind.allCases {
            func frame(_ t: TimeInterval, reduce: Bool) throws -> CGImage {
                try render(BrandTabIcon(kind: kind, isActive: true, size: 48)
                    .environment(\.brandReduceMotionOverride, reduce)
                    .environment(\.brandFrozenTime, t))
            }
            let still0 = try frame(0.3, reduce: true)
            let still1 = try frame(1.45, reduce: true)
            // Tolerancia de ruido de render (desenfoques por GPU: unos pocos niveles de 255 en toda la
            // imagen, ~5e-7); un movimiento real da > 1e-3.
            XCTAssertLessThan(difference(still0, still1), Self.renderNoise, "\(kind): con Reduce Motion el icono se mueve")
            let moving0 = try frame(0.3, reduce: false)
            let moving1 = try frame(1.45, reduce: false)
            XCTAssertGreaterThan(difference(moving0, moving1), 0.001, "\(kind): sin Reduce Motion el icono no se mueve")
        }
        let logoStill = try render(ChromaSolLogo(size: 64, animated: true).environment(\.brandReduceMotionOverride, true).environment(\.brandFrozenTime, 4))
        let logoRest = try render(ChromaSolLogo(size: 64, animated: false).environment(\.brandFrozenTime, 4))
        XCTAssertLessThan(difference(logoStill, logoRest), Self.renderNoise, "con Reduce Motion el sol del logotipo no gira ni brilla")
        let logoMoving = try render(ChromaSolLogo(size: 64, animated: true).environment(\.brandReduceMotionOverride, false).environment(\.brandFrozenTime, 4))
        XCTAssertGreaterThan(difference(logoMoving, logoRest), 0.001)
    }

    // MARK: Identificadores de pestaña

    func testKindsMapToTabIdentifiersAndLabels() {
        let identifiers = SolarTabs.standard(feed: 0, extraer: 1, rejilla: 2, jardin: 3).compactMap(\.accessibilityIdentifier)
        XCTAssertEqual(identifiers.compactMap(BrandTabIconKind.init(tabIdentifier:)), BrandTabIconKind.allCases)
        XCTAssertEqual(BrandTabIconKind.allCases.map(\.sectionLabel), ["FEED", "EXTRAER", "REJILLA", "JARDÍN"])
        XCTAssertNil(BrandTabIconKind(tabIdentifier: "tab.otra"))
    }

    // MARK: Icono de la app

    func testAppIconIsRegisteredInCompiledInfoPlist() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
                                  "CFBundleIcons ausente: el catálogo no registró AppIcon")
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
    }

    func testAppIconSourcePNGsAreOpaque1024() throws {
        let set = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ColorsApp/Assets.xcassets/AppIcon.appiconset")
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json"))) as? [String: Any]
        let images = try XCTUnwrap(contents?["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 3)
        for entry in images {
            let name = try XCTUnwrap(entry["filename"] as? String)
            XCTAssertEqual(entry["size"] as? String, "1024x1024")
            let image = try XCTUnwrap(UIImage(contentsOfFile: set.appendingPathComponent(name).path)?.cgImage, name)
            XCTAssertEqual(image.width, 1024, name)
            XCTAssertEqual(image.height, 1024, name)
            XCTAssertTrue([.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo), "\(name) con alfa")
        }
    }

    // MARK: Utilidades

    /// Diferencia media máxima atribuible al ruido del render (no a un cambio de pose).
    private static let renderNoise = 2e-5

    private func render<V: View>(_ view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    /// Fracción de píxeles con alfa > 8 %.
    private func opaqueFraction(_ image: CGImage) -> Double {
        let px = rgba(image)
        var n = 0
        for i in stride(from: 3, to: px.count, by: 4) where px[i] > 20 { n += 1 }
        return Double(n) / Double(image.width * image.height)
    }

    /// Diferencia media absoluta normalizada (0…1) entre dos imágenes del mismo tamaño.
    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        let pa = rgba(a), pb = rgba(b)
        var sum = 0
        for i in 0..<pa.count { sum += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(sum) / Double(pa.count * 255)
    }
}
