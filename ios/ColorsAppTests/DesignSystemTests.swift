// Sistema de diseño (docs/design/DESIGN_SYSTEM.md): fuentes registradas y usadas de
// verdad, pesos variables, Dynamic Type, fallback, valores de los tokens, contraste
// WCAG 2.x de los pares texto/fondo en claro y oscuro, neutralidad del pocillo con el
// Lab del motor (srgbToLab), píxeles exactos del pocillo renderizado y tamaños de los
// componentes principales.
import XCTest
import SwiftUI
import UIKit
import ColorEngine
@testable import ColorsApp

@MainActor
final class DesignSystemTests: XCTestCase {

    // MARK: Fuentes

    func testBundledFontsAreRegisteredByUIAppFonts() throws {
        let status = FontRegistry.bootstrap()
        XCTAssertTrue(status.literata, "Literata no registrada")
        XCTAssertTrue(status.jakarta, "Plus Jakarta Sans no registrada")
        XCTAssertFalse(status.registeredAtRuntime, "UIAppFonts no cargó las fuentes: hizo falta el registro de respaldo")
        XCTAssertTrue(UIFont.familyNames.contains("Literata"))
        XCTAssertTrue(UIFont.familyNames.contains("Plus Jakarta Sans"))
        for name in FontRegistry.requiredInstances {
            XCTAssertNotNil(UIFont(name: name, size: 14), "Falta la instancia \(name)")
        }
        let appFonts = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String]
        XCTAssertEqual(Set(appFonts ?? []), ["Literata-VF.ttf", "PlusJakartaSans-VF.ttf"])
    }

    func testOFLLicensesAreBundled() throws {
        for file in FontRegistry.licenseFiles {
            let url = try XCTUnwrap(Bundle.main.url(forResource: file, withExtension: "txt"), "\(file).txt fuera del bundle")
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE Version 1.1"), file)
        }
        for entry in FontLicenses.entries {
            XCTAssertNotNil(FontLicenses.text(for: entry))
        }
    }

    func testFamilyPlusWeightResolvesNamedVariableInstances() {
        XCTAssertEqual(Typography.familyFont("Literata", size: 18, weight: .medium).fontName, "Literata-Regular_Medium")
        XCTAssertEqual(Typography.familyFont("Literata", size: 18, weight: .semibold).fontName, "Literata-Regular_SemiBold")
        XCTAssertEqual(Typography.familyFont("Plus Jakarta Sans", size: 12, weight: .semibold).fontName, "PlusJakartaSans-Regular_SemiBold")
        XCTAssertEqual(Typography.familyFont("Plus Jakarta Sans", size: 11, weight: .bold).fontName, "PlusJakartaSans-Regular_Bold")
        XCTAssertEqual(Typography.uiFont(.headlineSM).familyName, "Literata")
        XCTAssertEqual(Typography.uiFont(.labelSM).familyName, "Plus Jakarta Sans")
    }

    /// SwiftUI cae en silencio a SF si el nombre de la fuente falla: el ancho lo delata.
    func testSwiftUITextUsesCustomFontsAndWeights() {
        let sample = "ChromaSol · Combinación Nº 067 Laelia Pink"
        func width(_ font: Font) -> CGFloat {
            size(of: Text(sample).font(font).fixedSize(), width: 2000).width
        }
        let literata = width(Typography.font(.headlineSM))
        let sfSerif = width(.system(.headline, design: .serif, weight: .medium))
        let missing = width(.custom("NoSuchFamilyXYZ", size: 18, relativeTo: .headline).weight(.medium))
        XCTAssertNotEqual(literata, missing, accuracy: 0.5, "Literata no se aplica (mismo ancho que el fallback de SF)")
        XCTAssertNotEqual(literata, sfSerif, accuracy: 0.5)
        let jakarta = width(Typography.font(.bodyMD))
        let jakartaMissing = width(.custom("NoSuchFamilyXYZ", size: 14, relativeTo: .subheadline))
        XCTAssertNotEqual(jakarta, jakartaMissing, accuracy: 0.5, "Plus Jakarta Sans no se aplica")
        let regular = width(.custom("Literata", size: 20, relativeTo: .title3).weight(.regular))
        let bold = width(.custom("Literata", size: 20, relativeTo: .title3).weight(.bold))
        XCTAssertNotEqual(regular, bold, accuracy: 0.5, "El peso no cambia la instancia variable")
    }

    func testFallbackUsesSystemSerifWhenCustomFontsAreMissing() {
        let none = FontRegistryStatus(literata: false, jakarta: false, registeredAtRuntime: false)
        let sample = "ChromaSol Nº 067"
        let fallback = size(of: Text(sample).font(Typography.font(.headlineSM, status: none)).fixedSize(), width: 2000).width
        let system = size(of: Text(sample).font(.system(.headline, design: .serif, weight: .medium)).fixedSize(), width: 2000).width
        XCTAssertEqual(fallback, system, accuracy: 0.01)
    }

    func testRolesScaleWithDynamicType() {
        for role in [TextRole.headlineSM, .bodyMD, .labelSM, .hex] {
            let text = Text("Aa Ñ").textRole(role)
            let large = size(of: text.environment(\.dynamicTypeSize, .large), width: 400).height
            let ax3 = size(of: text.environment(\.dynamicTypeSize, .accessibility3), width: 400).height
            XCTAssertGreaterThan(ax3, large * 1.6, "\(role.id) no escala con Dynamic Type (\(large) → \(ax3))")
        }
        // La cabecera crece con el texto (sin cortar la marca) y la barra de acciones cabe en 370 pt.
        func headerHeight(_ dts: DynamicTypeSize) -> CGFloat {
            size(of: AppHeader(section: "FEED", sunAction: {}).environment(\.dynamicTypeSize, dts), width: 402).height
        }
        XCTAssertGreaterThanOrEqual(headerHeight(.accessibility1), Sizes.header)
        XCTAssertEqual(headerHeight(.accessibility5), headerHeight(.accessibility1), "La cabecera no limita Dynamic Type a AX1")
        for dts in [DynamicTypeSize.large, .xxxLarge, .accessibility2] {
            let bar = FeedActionBar(verdict: nil, isSaved: true, onYes: {}, onNo: {}, onSave: {}, onCopy: {}, share: .action({}))
            let w = size(of: bar.environment(\.dynamicTypeSize, dts), width: 370).width
            XCTAssertLessThanOrEqual(w, 370, "FeedActionBar desborda con \(dts)")
        }
        XCTAssertTrue(TextRole.all.allSatisfy { $0.size >= 11 }, "Texto por debajo de 11 pt")
        XCTAssertGreaterThanOrEqual(TextRole.hex.size, 12)
    }

    // MARK: Tokens

    func testTokenValuesMatchDesignTables() {
        let expected: [(ThemeToken, UInt32, UInt32)] = [
            (ThemeTokens.surface, 0xFCF9F1, 0x15130E), (ThemeTokens.card, 0xFFFFFF, 0x1C1913),
            (ThemeTokens.containerLowest, 0xFFFFFF, 0x0F0D09), (ThemeTokens.containerHighest, 0xE5E2DB, 0x37322A),
            (ThemeTokens.onSurface, 0x1C1C17, 0xEDE6D6), (ThemeTokens.onSurfaceVariant, 0x414942, 0xCDC5B3),
            (ThemeTokens.outline, 0x717971, 0x979080), (ThemeTokens.primary, 0x144226, 0xA1D2AC),
            (ThemeTokens.onPrimary, 0xFFFFFF, 0x0B3A1D), (ThemeTokens.secondary, 0x954A00, 0xFFB785),
            (ThemeTokens.secondaryContainer, 0xFD933F, 0x713700), (ThemeTokens.tertiary, 0x144136, 0xA2D0C0),
            (ThemeTokens.error, 0xBA1A1A, 0xFFB4AB), (ThemeTokens.inverseSurface, 0x31312B, 0xEDE6D6),
            (ThemeTokens.wellFill, 0xFFFFFF, 0x303030), (ThemeTokens.wellFillAlt, 0xF2F2F2, 0x333333),
            (ThemeTokens.wellEdge, 0xD6D6D6, 0x4A4A4A), (ThemeTokens.wellText, 0x1F1F1F, 0xEDEDED),
            (ThemeTokens.wellTextSecondary, 0x5C5C5C, 0xB0B0B0), (ThemeTokens.wellPlaceholder, 0xE6E6E6, 0x3D3D3D),
        ]
        for (token, light, dark) in expected {
            XCTAssertEqual(token.light, light, "\(token.name) claro")
            XCTAssertEqual(token.dark, dark, "\(token.name) oscuro")
        }
        XCTAssertEqual(Set(ThemeTokens.all.map(\.name)).count, ThemeTokens.all.count, "Nombres de token duplicados")
        // El UIColor dinámico resuelve el valor del tema pedido.
        for token in [ThemeTokens.surface, ThemeTokens.primary, ThemeTokens.wellFill] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let resolved = UIColor(light: token.light, dark: token.dark)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
                let v = (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
                XCTAssertEqual(v, style == .dark ? token.dark : token.light, "\(token.name) \(style.rawValue)")
            }
        }
    }

    func testTextBackgroundPairsPassWCAGAAInBothThemes() {
        typealias T = ThemeTokens
        // (texto, fondo, mínimo). 4,5 texto normal; 3,0 elementos no textuales.
        let pairs: [(ThemeToken, ThemeToken, Double)] = [
            (T.onSurface, T.surface, 4.5), (T.onSurface, T.containerLow, 4.5), (T.onSurface, T.container, 4.5),
            (T.onSurface, T.containerHigh, 4.5), (T.onSurface, T.containerHighest, 4.5), (T.onSurface, T.card, 4.5),
            (T.onSurfaceVariant, T.surface, 4.5), (T.onSurfaceVariant, T.container, 4.5),
            (T.onSurfaceVariant, T.containerHigh, 4.5), (T.onSurfaceVariant, T.containerHighest, 4.5),
            (T.onSurfaceVariant, T.card, 4.5), (T.onSurfaceVariant, T.chipCeladon, 4.5),
            (T.primary, T.surface, 4.5), (T.primary, T.card, 4.5), (T.primary, T.container, 4.5),
            (T.onPrimary, T.primary, 4.5), (T.onPrimaryContainer, T.primaryContainer, 4.5),
            (T.secondary, T.surface, 4.5), (T.secondary, T.container, 4.5), (T.secondary, T.card, 4.5),
            (T.onSecondary, T.secondary, 4.5), (T.onSecondaryContainer, T.secondaryContainer, 4.5),
            (T.tertiary, T.surface, 4.5), (T.tertiary, T.card, 4.5), (T.onTertiary, T.tertiary, 4.5),
            (T.onTertiaryContainer, T.tertiaryContainer, 4.5),
            (T.error, T.surface, 4.5), (T.error, T.card, 4.5), (T.onError, T.error, 4.5),
            (T.onErrorContainer, T.errorContainer, 4.5), (T.inverseOnSurface, T.inverseSurface, 4.5),
            (T.onPrimaryFixed, T.primaryFixed, 4.5), (T.onSecondaryFixed, T.secondaryFixed, 4.5),
            (T.onSecondaryFixedVariant, T.secondaryFixed, 4.5),
            (T.onMossBadge, T.mossBadge, 4.5), (T.onAmberBadge, T.amberBadge, 4.5), (T.onCeladonBadge, T.celadonBadge, 4.5),
            (T.wellText, T.wellFill, 4.5), (T.wellText, T.wellFillAlt, 4.5),
            (T.wellTextSecondary, T.wellFill, 4.5), (T.wellTextSecondary, T.wellFillAlt, 4.5),
            (T.wellTextSecondary, T.wellPlaceholder, 3.0), (T.outline, T.surface, 3.0),
        ]
        var failures: [String] = []
        for scheme in [ColorScheme.light, .dark] {
            for (fg, bg, minimum) in pairs {
                let ratio = contrast(fg.rgb8(for: scheme), bg.rgb8(for: scheme))
                if ratio < minimum {
                    failures.append("\(scheme) \(fg.name)/\(bg.name) = \(String(format: "%.2f", ratio)) < \(minimum)")
                }
            }
            // Texto sobre el pergamino esmerilado en el peor caso (tinte sobre negro en claro, sobre blanco en oscuro).
            let tint = ThemeTokens.frostTint
            let under: (r: UInt8, g: UInt8, b: UInt8) = scheme == .light ? (0, 0, 0) : (255, 255, 255)
            let frosted = composite(tint.rgb8(for: scheme), alpha: tint.opacity(for: scheme), over: under)
            for fg in [T.onSurface, T.primary] where contrast(fg.rgb8(for: scheme), frosted) < 4.5 {
                failures.append("\(scheme) \(fg.name)/frost = \(contrast(fg.rgb8(for: scheme), frosted))")
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testWellTokensAreNeutralWithEngineLab() {
        for scheme in [ColorScheme.light, .dark] {
            for token in ThemeTokens.neutralWell {
                var c = token.rgb8(for: scheme)
                if token.opacity(for: scheme) < 1 {
                    c = composite(c, alpha: token.opacity(for: scheme), over: ThemeTokens.wellFill.rgb8(for: scheme))
                }
                XCTAssertTrue(c.r == c.g && c.g == c.b, "\(token.name) \(scheme) no es gris: \(c)")
                let lab = srgbToLab(r: c.r, g: c.g, b: c.b)
                let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
                XCTAssertLessThan(chroma, 2, "\(token.name) \(scheme) croma \(chroma)")
            }
        }
        XCTAssertEqual(ThemeTokens.wellFill.light, 0xFFFFFF)
        let dark = ThemeTokens.wellFill.rgb8(for: .dark)
        let darkL = srgbToLab(r: dark.r, g: dark.g, b: dark.b).L
        XCTAssertTrue((18...22).contains(darkL), "wellFill oscuro L* \(darkL) fuera de 18–22")
        // El marco sí es cálido (control: el test distingue neutro de pergamino).
        let surface = ThemeTokens.surface.rgb8(for: .light)
        let s = srgbToLab(r: surface.r, g: surface.g, b: surface.b)
        XCTAssertGreaterThan((s.a * s.a + s.b * s.b).squareRoot(), 2)
    }

    /// Los píxeles del pocillo renderizado valen exactamente (255,255,255) en claro y (48,48,48) en oscuro.
    func testRenderedWellPixelsAreExactNeutrals() throws {
        for (scheme, expected) in [(ColorScheme.light, UInt8(255)), (.dark, UInt8(48))] {
            let view = SwatchWell(padding: 12, cornerRadius: 0) {
                HStack(spacing: 0) {
                    Color(rgb8: 197, 83, 71)
                    Color(rgb8: 18, 53, 78)
                }
                .frame(width: 60, height: 20)
            }
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let px = try rgbaPixels(image)
            // Relleno del pocillo: a 6 pt del borde (lejos del filo de 1 px y del swatch).
            for (x, y) in [(6, 22), (78, 22), (40, 4), (40, 40)] {
                let p = px.pixel(x * 2, y * 2)
                XCTAssertEqual([p.r, p.g, p.b], [expected, expected, expected], "\(scheme) (\(x),\(y)) = \(p)")
            }
            // Y el swatch conserva su color exacto.
            let swatch = px.pixel(26 * 2, 22 * 2)
            XCTAssertEqual([swatch.r, swatch.g, swatch.b], [197, 83, 71], "\(scheme) swatch = \(swatch)")
        }
    }

    // MARK: Tamaños de los componentes principales

    func testMainComponentSizes() throws {
        let dictionary = try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
        let combo337 = PaletteColor.combo(337, in: dictionary)
        let palette = [
            PaletteColor(id: 0, hex: "#222524", name: "Black", weight: 0.39, deltaE: 3.1)!,
            PaletteColor(id: 1, hex: "#b49aa2", name: "Laelia Pink", weight: 0.23, deltaE: 4.2)!,
            PaletteColor(id: 2, hex: "#917a7e", name: "Vistoris Lake", weight: 0.16)!,
            PaletteColor(id: 3, hex: "#d5b8c0", name: "Corinthian Pink", weight: 0.13)!,
            PaletteColor(id: 4, hex: "#6b5a57", name: "Hay's Russet", weight: 0.08)!,
        ]
        let match = ComboMatchSummary(comboId: 337, name: dictionary.displayName(id: 337), colors: combo337)
        var measured: [String: CGSize] = [:]
        func measure<V: View>(_ name: String, _ view: V, width: CGFloat) -> CGSize {
            let s = size(of: view.environment(\.dynamicTypeSize, .large), width: width)
            measured[name] = s
            return s
        }

        XCTAssertEqual(measure("AppHeader", AppHeader(section: "FEED", sunAction: {}, avatarAction: {}), width: 402).height, Sizes.header)
        XCTAssertEqual(measure("SolarTabBar", SolarTabBar(items: SolarTabs.standard(feed: 0, extraer: 1, rejilla: 2, jardin: 3),
                                                          selection: .constant(0)), width: 402).height, Sizes.tabBar)
        XCTAssertEqual(measure("SwatchBead", SwatchBead(color: .red), width: 100).height, Sizes.pinBead)
        XCTAssertEqual(measure("StoryProgressBar", StoryProgressBar(count: 11, current: 3), width: 370).height, 3)
        XCTAssertEqual(measure("SolarPrimaryButton", SolarPrimaryButton(title: "Sí, es eso", systemImage: "heart") {}, width: 370).height,
                       48, accuracy: 1)
        XCTAssertEqual(measure("FilterChip", FilterChip(title: "2 colores", isSelected: true) {}, width: 370).height, 32, accuracy: 1)
        XCTAssertEqual(measure("SolarSearchField", SolarSearchField(placeholder: "Busca", text: .constant("")), width: 370).height,
                       Sizes.minTouch, accuracy: 1)
        // Tira de 24 pt en pocillo con 8 pt de relleno.
        XCTAssertEqual(measure("PaletteRibbon.strip", PaletteRibbon(colors: combo337, style: .strip), width: 370).height,
                       Sizes.dayRibbon + 2 * Spacing.wellPadding, accuracy: 0.01)
        XCTAssertEqual(measure("PaletteGridCard.stripes", PaletteGridCard(title: "Nº 337", subtitle: "Nº 337 · 4 colores",
                                                                          colors: combo337, state: .locked), width: 179).height,
                       187.7, accuracy: 2)
        let garment = measure("GarmentCard", GarmentCard(index: 1, color: palette[0]), width: 179)
        XCTAssertEqual(garment.height, 155.3, accuracy: 2)
        let post = measure("FeedPostCard", FeedPostCard(content: FeedPostContent(source: .library, metadata: "14 sept 2026, 10:45",
                                                                                 photo: nil, photoAspectRatio: 0.8, palette: palette,
                                                                                 match: match, verdict: .yes),
                                                        actions: FeedPostActions(onYes: {}, onNo: {}, onSave: {}, onCopyCombo: {})),
                           width: 370)
        // La foto 4:5 ocupa 370 × 462,5 dentro de la tarjeta; el resto (cabecera, gotas, pie y acciones) 321,5.
        XCTAssertEqual(post.height, 784, accuracy: 2)
        let day = measure("DailyPickCard", DailyPickCard(eyebrow: "Combinación del día", numberLabel: "Nº 337", name: "Nº 337",
                                                          colors: combo337, status: "4 colores · Bloqueada", onShuffle: {}), width: 370)
        XCTAssertEqual(day.height, 189, accuracy: 2)
        let harvest = measure("HarvestRow", HarvestRow(thumbnail: nil, title: "Nº 337", metadata: "ayer · Carrete", verdict: .yes,
                                                       palette: palette), width: 370)
        XCTAssertEqual(harvest.height, 196.7, accuracy: 2)
        let tile = measure("ExportTile", ExportTile(title: "Copiar hex", detail: "Los colores de la última cosecha",
                                                    systemImage: "doc.on.doc") {}, width: 170)
        XCTAssertEqual(tile.height, 104.7, accuracy: 2)
        let stats = measure("StatHeader", StatHeader(detail: "Acierto: 82 %", stats: [
            StatItem(id: "a", value: "42", label: "Fotos"), StatItem(id: "b", value: "20/348", label: "Desbloqueadas"),
            StatItem(id: "c", value: "41", label: "Sí, es eso"),
        ], onSettings: {}), width: 370)
        XCTAssertEqual(stats.height, 158.7, accuracy: 2)
        print("DesignSystemTests sizes:", measured.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value.width))x\(String(format: "%.1f", $0.value.height))" }.joined(separator: " "))
    }

    func testPinGeometryFromLabelMap() {
        let none = paletteLabelNone
        // 4 × 3: swatch 0 en forma de L (su centroide cae fuera de la región), swatch 1 en una esquina.
        let map: [UInt8] = [
            0, none, none, 1,
            0, none, none, none,
            0, 0, 0, paletteLabelDiscarded,
        ]
        let p = PinOverlay.positions(labelMap: map, width: 4, height: 3, swatchCount: 3)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[1], CGPoint(x: 3.5 / 4, y: 0.5 / 3))
        let p0 = try? XCTUnwrap(p[0])
        // Centroide (0,8; 1,6) → píxel etiquetado más cercano (0, 2) o (1, 2): siempre sobre la etiqueta 0.
        if let p0 {
            let x = Int(p0.x * 4 - 0.5), y = Int(p0.y * 3 - 0.5)
            XCTAssertEqual(map[y * 4 + x], 0)
        }
        let rect = PinOverlay.displayRect(imageSize: CGSize(width: 772, height: 1024), in: CGSize(width: 370, height: 400), contentMode: .fit)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 185, accuracy: 0.001)
    }

    // MARK: Utilidades

    private func size<V: View>(of view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// Luminancia relativa WCAG 2.x (sRGB).
    private func luminance(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Double {
        func channel(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func contrast(_ a: (r: UInt8, g: UInt8, b: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func composite(_ c: (r: UInt8, g: UInt8, b: UInt8), alpha: Double,
                           over u: (r: UInt8, g: UInt8, b: UInt8)) -> (r: UInt8, g: UInt8, b: UInt8) {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) * alpha + Double(y) * (1 - alpha)).rounded()) }
        return (mix(c.r, u.r), mix(c.g, u.g), mix(c.b, u.b))
    }

    private struct Pixels {
        let width: Int
        let data: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let i = (y * width + x) * 4
            return (data[i], data[i + 1], data[i + 2])
        }
    }

    private func rgbaPixels(_ image: CGImage) throws -> Pixels {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(ok)
        return Pixels(width: w, data: data)
    }
}
