// Fidelidad de la Rejilla al ejemplo del usuario (docs/design/FIDELITY.md §5 y §8.3): tiempos
// exactos del barajado (M16), giro del reloj de sol, banda sin lavados alrededor del pocillo,
// insignia del avatar, respuesta al pulsar de la tarjeta, atajos de movimiento y, renderizada con
// el reloj congelado, la tarjeta «Al azar» con luces: pocillo exacto (blanco / #303030), fichas con
// el sRGB de Wada, banda de 16 pt sin luz y orbe cálido presente arriba a la derecha.
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

final class RejillaFidelityTests: XCTestCase {

    func testShuffleTimingsMatchExample() {
        // generateRandomPalette(): scaleY(0.4); a los 120 + 60·i ms color nuevo y scaleY(1); duration-500.
        XCTAssertEqual(RejillaShuffleTiles.squashScale, 0.4)
        XCTAssertEqual(RejillaShuffleTiles.duration, 0.5)
        XCTAssertEqual(RejillaShuffleTiles.swapDelay(index: 0), 0.12, accuracy: 1e-12)
        XCTAssertEqual(RejillaShuffleTiles.swapDelay(index: 4), 0.36, accuracy: 1e-12)
        XCTAssertEqual(RejillaShuffleTiles.swapDelay(index: -3), 0.12, accuracy: 1e-12)
    }

    func testDialRotationAddsTurnPlusExtra() {
        // currentRotation += 360 + Math.floor(Math.random() * 180)
        XCTAssertEqual(RejillaRandomCard.nextDialRotation(from: 0, extra: 90), 450)
        XCTAssertEqual(RejillaRandomCard.nextDialRotation(from: 450, extra: 0), 810)
        XCTAssertLessThan(RejillaRandomCard.nextDialRotation(from: 0, extra: 500), 540)
        XCTAssertEqual(RejillaRandomCard.nextDialRotation(from: 0, extra: -5), 360)
        XCTAssertEqual(RejillaRandomCard.breathDuration, 8)
    }

    func testWashBandKeepsSixteenPointsAroundWell() {
        let band = RejillaWellBandMask.band(wellFrame: CGRect(x: 12, y: 140, width: 300, height: 60), clearance: 16, height: 300)
        XCTAssertEqual(band, 124...216)
        XCTAssertEqual(RejillaWellBandMask.band(wellFrame: CGRect(x: 0, y: 8, width: 10, height: 290), clearance: 16, height: 300), 0...300)
        XCTAssertNil(RejillaWellBandMask.band(wellFrame: .zero, clearance: 16, height: 300))
        XCTAssertEqual(RejillaRandomCard.washClearance, 16)
    }

    func testAvatarBadgeCountsUnlocksSinceLastGardenVisit() {
        XCTAssertEqual(RejillaAvatarBadge.newUnlocks(unlocked: 20, lastSeen: nil), 20)
        XCTAssertEqual(RejillaAvatarBadge.newUnlocks(unlocked: 20, lastSeen: 17), 3)
        XCTAssertEqual(RejillaAvatarBadge.newUnlocks(unlocked: 5, lastSeen: 9), 0)
        XCTAssertEqual(RejillaAvatarBadge.accessibilityLabel(newUnlocks: 0), "Tu jardín")
        XCTAssertEqual(RejillaAvatarBadge.accessibilityLabel(newUnlocks: 1), "Tu jardín, 1 combinación nueva")
        XCTAssertEqual(RejillaAvatarBadge.accessibilityLabel(newUnlocks: 3), "Tu jardín, 3 combinaciones nuevas")
        XCTAssertEqual(RejillaAvatarBadge.lastSeenKey, "jardin.lastSeenUnlockCount")
    }

    func testGridCardPressEffect() {
        let rest = ComboGridCard.pressEffect(pressed: false, reduceMotion: false)
        XCTAssertEqual(rest.scale, 1)
        XCTAssertEqual(rest.glowOpacity, 0)
        let pressed = ComboGridCard.pressEffect(pressed: true, reduceMotion: false)
        XCTAssertEqual(pressed.scale, 0.98)
        XCTAssertEqual(pressed.glowOpacity, 0.2)
        let reduced = ComboGridCard.pressEffect(pressed: true, reduceMotion: true)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.opacity, 0.8)
        XCTAssertEqual(ComboGridCard.metaRole.size, 11, "ningún texto por debajo de 11 pt")
    }

    func testMotionLaunchOptions() {
        let o = RejillaLaunchOptions.parse(["app", "-uiScreen", "rejilla", "-uiRejillaMotionTime", "2.6",
                                            "-uiRejillaReduceMotion", "1", "-uiRejillaAutoShuffle", "1.5"])
        XCTAssertEqual(o.motionTime, 2.6)
        XCTAssertTrue(o.reduceMotion)
        XCTAssertEqual(o.autoShuffleAfter, 1.5)
        let none = RejillaLaunchOptions.parse(["app", "-uiRejillaMotionTime", "-1"])
        XCTAssertNil(none.motionTime)
        XCTAssertFalse(none.reduceMotion)
        XCTAssertNil(none.autoShuffleAfter)
    }

    /// Tarjeta «Al azar» renderizada a t = 1,5 s: pocillo exacto, fichas exactas, sin luz en la banda
    /// de 16 pt alrededor del pocillo y con el orbe cálido arriba a la derecha.
    @MainActor
    func testRandomCardLightsStayOutOfWellBand() throws {
        let dictionary = try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
        let colors = PaletteColor.combo(12, in: dictionary) // #C5A56E, #099197
        let width: CGFloat = 370
        for scheme in [ColorScheme.light, .dark] {
            let card = RejillaRandomCard(comboId: 12, name: "Prueba", colors: colors, isUnlocked: false,
                                         isProposedName: true, total: 348, onShuffle: {}, onOpen: {})
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(40)
                .background(Theme.surface)
                .environment(\.colorScheme, scheme)
                .motionTime(1.5)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let px = try Pixels(image)
            let label = "\(scheme)"
            // Localiza el pocillo: primera fila con su color en la columna central (lejos de las esquinas
            // redondeadas y del hueco entre fichas, que también es pocillo).
            let well: UInt8 = scheme == .light ? 255 : 48
            let x = Int((40 + Spacing.md + 3) * 2)
            let midX = Int((40 + width / 2) * 2)
            var wellTop: Int?
            for y in stride(from: Int(40 * 2 + 60 * 2), to: image.height, by: 1) {
                let p = px.pixel(midX, y)
                if p.r == well, p.g == well, p.b == well {
                    wellTop = y
                    break
                }
            }
            let top = try XCTUnwrap(wellTop, "\(label): pocillo no encontrado")
            // Relleno del pocillo (6 pt) y ficha 1 con su color exacto.
            for dy in [2, 8] {
                let p = px.pixel(x + 20, top + dy)
                XCTAssertEqual([p.r, p.g, p.b], [well, well, well], "\(label): relleno del pocillo = \(p)")
            }
            let tile = px.pixel(x + 40, top + 30 * 2)
            XCTAssertEqual([tile.r, tile.g, tile.b], [197, 165, 110], "\(label): Isabella Color exacto = \(tile)")
            // Banda de 16 pt por encima del pocillo: el fondo de la tarjeta sin lavado (container exacto).
            let container = ThemeTokens.container.rgb8(for: scheme)
            // Filas a 3, 8 y 15 pt por encima del borde superior del pocillo.
            for dy in [6, 16, 30] {
                for cx in [x + 20, Int((40 + width / 2) * 2), Int((40 + width - 30) * 2)] {
                    let p = px.pixel(cx, top - dy)
                    XCTAssertLessThanOrEqual(abs(Int(p.r) - Int(container.r)), 1, "\(label): banda (\(cx),\(top - dy)) = \(p)")
                    XCTAssertLessThanOrEqual(abs(Int(p.g) - Int(container.g)), 1, "\(label): banda (\(cx),\(top - dy)) = \(p)")
                    XCTAssertLessThanOrEqual(abs(Int(p.b) - Int(container.b)), 1, "\(label): banda (\(cx),\(top - dy)) = \(p)")
                }
            }
            // Orbe cálido arriba a la derecha (dentro de la tarjeta): más cálido que el fondo.
            let orb = px.pixel(Int((40 + width - 14) * 2), Int((40 + 14) * 2))
            XCTAssertGreaterThan(Int(orb.r) - Int(orb.b), Int(container.r) - Int(container.b) + 6,
                                 "\(label): orbe cálido = \(orb), fondo = \(container)")
        }
    }
}

private struct Pixels {
    let width: Int
    let height: Int
    let data: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let w = width, h = height
        let ok = buffer.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(ok)
        data = buffer
    }

    func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return (data[i], data[i + 1], data[i + 2])
    }
}

extension RejillaFidelityTests {
    /// Halo permanente de la tarjeta de la cuadrícula: L1 del ejemplo a la mitad (348 tarjetas a la
    /// vez), con los mismos desenfoques y el mismo par de colores (ámbar `#EAB308` + musgo).
    func testGridCardRestGlowIsHalfOfExampleCardGlow() {
        let glow = ComboGridCard.restGlow
        XCTAssertEqual(glow.inner.blur, MotionSpec.glowCard.inner.blur)   // 18 px
        XCTAssertEqual(glow.outer.blur, MotionSpec.glowCard.outer.blur)   // 28 px
        XCTAssertEqual(glow.inner.color.a, MotionSpec.glowCard.inner.color.a / 2, accuracy: 0.02)
        XCTAssertEqual(glow.outer.color.a, MotionSpec.glowCard.outer.color.a / 2, accuracy: 0.02)
        XCTAssertEqual(glow.border.a, MotionSpec.glowCard.border.a / 2, accuracy: 0.03)
        XCTAssertEqual([glow.inner.color.r, glow.inner.color.g, glow.inner.color.b],
                       [TailwindColor.yellow500.r, TailwindColor.yellow500.g, TailwindColor.yellow500.b])
        XCTAssertEqual([glow.outer.color.r, glow.outer.color.g, glow.outer.color.b],
                       [TailwindColor.moss.r, TailwindColor.moss.g, TailwindColor.moss.b])
    }

    /// La tarjeta BLOQUEADA sigue siendo clara y luminosa (`surface-container-lowest`, como las del
    /// ejemplo): nada de placa gris. El pocillo de las franjas sigue siendo neutro exacto y los
    /// colores se ven tal cual. (Con alto contraste vuelve el gris: ver `dimsLocked`.)
    @MainActor
    func testLockedGridCardStaysLightWithNeutralWell() throws {
        let dictionary = try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
        let colors = PaletteColor.combo(12, in: dictionary) // #C5A56E, #099197
        let width: CGFloat = 174
        for scheme in [ColorScheme.light, .dark] {
            let card = ComboGridCard(comboId: 12, name: ComboName(text: "Prueba", kind: .proposed),
                                     colors: colors, state: .locked, onOpen: {}, onToggleSave: {})
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(40)
                .background(Theme.surface)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let px = try Pixels(image)
            let label = "\(scheme)"
            let card8 = ThemeTokens.card.rgb8(for: scheme)
            let well8 = ThemeTokens.wellFill.rgb8(for: scheme)
            let gray8 = ThemeTokens.containerLow.rgb8(for: scheme)
            // Pocillo: 6 pt de relleno neutro exacto por encima de las franjas.
            let midX = Int((40 + width / 2) * 2)
            var wellTop: Int?
            for y in stride(from: Int(40 * 2), to: image.height, by: 1) where wellTop == nil {
                let p = px.pixel(midX, y)
                if p.r == well8.r, p.g == well8.g, p.b == well8.b { wellTop = y }
            }
            let top = try XCTUnwrap(wellTop, "\(label): pocillo no encontrado")
            for dy in [2, 6, 10] {
                let p = px.pixel(midX, top + dy)
                XCTAssertEqual([p.r, p.g, p.b], [well8.r, well8.g, well8.b], "\(label): relleno del pocillo = \(p)")
            }
            // Franja izquierda con el sRGB exacto de Wada (sin filtro ni desaturación).
            let stripe = px.pixel(Int((40 + 24) * 2), top + Int(50 * 2))
            XCTAssertEqual([stripe.r, stripe.g, stripe.b], [197, 165, 110], "\(label): Isabella Color = \(stripe)")
            // Zona de texto: `card` (blanco / #1C1913), NUNCA la placa gris de `containerLow`.
            let text = px.pixel(Int((40 + width - 12) * 2), image.height - Int(40 * 2) - 14)
            XCTAssertEqual([text.r, text.g, text.b], [card8.r, card8.g, card8.b], "\(label): marco de la bloqueada = \(text)")
            if scheme == .light {
                XCTAssertNotEqual([text.r, text.g, text.b], [gray8.r, gray8.g, gray8.b], "\(label): sigue gris")
            }
        }
    }

    /// El avatar de la cabecera de la Rejilla dibuja EL MISMO personaje (brote en maceta) que el
    /// Feed, Extraer y el Jardín: se compara pixel a pixel con el dibujo de la marca.
    @MainActor
    func testRejillaHeaderAvatarDrawsTheBrandSprout() throws {
        func render<V: View>(_ view: V) throws -> Pixels {
            let renderer = ImageRenderer(content: view.padding(6).background(Theme.surface).environment(\.colorScheme, .light))
            renderer.scale = 2
            return try Pixels(try XCTUnwrap(renderer.cgImage))
        }
        let avatar = try render(RejillaGardenAvatar(showsBadge: false))
        let reference = try render(
            Circle()
                .fill(RadialGradient(colors: [Theme.secondaryFixed, Tone.moss.badgeFill],
                                     center: UnitPoint(x: 0.5, y: 0.35), startRadius: 2, endRadius: 20))
                .overlay { BrandTabIconFrame(kind: .jardin, size: 23).offset(y: 1.5) }
                .frame(width: Sizes.avatar, height: Sizes.avatar)
                .glowRing(.header, sparkleBadge: false)
        )
        XCTAssertEqual(avatar.width, reference.width)
        XCTAssertEqual(avatar.height, reference.height)
        var different = 0
        for y in 0..<min(avatar.height, reference.height) {
            for x in 0..<min(avatar.width, reference.width) {
                let a = avatar.pixel(x, y), b = reference.pixel(x, y)
                if abs(Int(a.r) - Int(b.r)) > 2 || abs(Int(a.g) - Int(b.g)) > 2 || abs(Int(a.b) - Int(b.b)) > 2 { different += 1 }
            }
        }
        XCTAssertEqual(different, 0, "el avatar de la Rejilla ya no es el personaje del brote de la marca")
    }

    func testBlurredOrbProfile() {
        // Disco de 160 pt con blur-2xl (σ 40): centro 1 − e^−2, mitad en el borde, casi nada a 2σ fuera.
        XCTAssertEqual(RejillaCardWashes.blurredDiscProfile(radius: 80, sigma: 40, distance: 0), 1 - exp(-2), accuracy: 1e-9)
        XCTAssertEqual(RejillaCardWashes.blurredDiscProfile(radius: 80, sigma: 40, distance: 80), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(RejillaCardWashes.blurredDiscProfile(radius: 80, sigma: 40, distance: 170), 0.02)
        XCTAssertEqual(RejillaCardWashes.blurredDiscProfile(radius: 10, sigma: 0, distance: 20), 0)
    }
}
