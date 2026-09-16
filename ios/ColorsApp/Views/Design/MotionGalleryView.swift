// Galería DEBUG de movimiento y luz (Design/Motion): la composición del Feed del ejemplo
// con todas sus luces y animaciones sobre datos reales (combinación del diccionario,
// foto de grupo embebida en Debug y paleta del motor), más un catálogo con cada efecto
// aislado y sus valores. Solo existe en DEBUG.
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen motion-gallery
// Argumentos: `-uiMotionPage feed|catalogo`, `-uiAppearance light|dark`,
// `-uiReduceMotion 1` (fuerza «Reducir movimiento»), `-uiMotionTime <s>` (congela el reloj).
#if DEBUG
import SwiftUI
import UIKit

enum MotionGalleryLaunch {
    static let screenValue = "motion-gallery"

    static var isRequested: Bool { value(after: "-uiScreen") == screenValue }

    static var page: MotionGalleryPage {
        value(after: "-uiMotionPage").flatMap(MotionGalleryPage.init(rawValue:)) ?? .feed
    }

    static var forcedScheme: ColorScheme? {
        switch value(after: "-uiAppearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    static var forcedReduceMotion: Bool { value(after: "-uiReduceMotion") == "1" }

    static var fixedTime: Double? { value(after: "-uiMotionTime").flatMap(Double.init) }

    /// `-uiMotionScroll bottom` abre la página desplazada hasta el final (capturas).
    static var scrollsToBottom: Bool { value(after: "-uiMotionScroll") == "bottom" }

    private static func value(after argument: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum MotionGalleryPage: String, CaseIterable, Identifiable {
    case feed, catalogo
    var id: String { rawValue }
    var title: String { self == .feed ? "Feed" : "Catálogo" }
}

struct MotionGalleryView: View {
    @State private var page: MotionGalleryPage = MotionGalleryLaunch.page
    @State private var scheme: ColorScheme? = MotionGalleryLaunch.forcedScheme
    @State private var dictionary: WadaDictionary? = try? WadaDictionary.load()
    @State private var sample: GallerySample = .empty
    @State private var chip = 0
    @State private var tab = 0

    var body: some View {
        MotionGalleryContent(page: $page, dictionary: dictionary, sample: sample, chip: $chip, tab: $tab,
                             toggleScheme: { scheme = (scheme == .dark) ? .light : .dark })
            .preferredColorScheme(scheme)
            .forceReducedMotion(MotionGalleryLaunch.forcedReduceMotion)
            .motionTime(MotionGalleryLaunch.fixedTime)
            .task {
                guard let dictionary, sample.photo == nil else { return }
                sample = await Task.detached(priority: .userInitiated) { GallerySample.load(dictionary: dictionary) }.value
            }
            .accessibilityIdentifier("motion.gallery")
    }
}

/// Contenido de la galería (los tests lo alojan directamente).
struct MotionGalleryContent: View {
    @Binding var page: MotionGalleryPage
    let dictionary: WadaDictionary?
    let sample: GallerySample
    @Binding var chip: Int
    @Binding var tab: Int
    var toggleScheme: () -> Void = {}

    var body: some View {
        // Como en el ejemplo: el contenido pasa por debajo de la cabecera y de la barra de
        // pestañas esmeriladas, y las motas flotan entre el contenido y esas barras.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                chips
                if page == .feed {
                    dayCard
                    postCard
                } else {
                    MotionCatalog()
                }
            }
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(MotionGalleryLaunch.scrollsToBottom ? .bottom : .top)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: Sizes.header) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Sizes.tabBar) }
        .lightMotes()
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) { tabBar }
        .background(Theme.surface.ignoresSafeArea())
        .tint(Theme.primary)
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            BrandMark().warmDropShadow(.logo)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(AppBrand.name).textRole(.brand).foregroundStyle(Theme.primary)
                    PingDot(color: TailwindColor.amber400.color, size: 6, keepsCore: false)
                }
                Text(page == .feed ? "Movimiento" : "Catálogo").textRole(.overline).foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.sm)
            Button(action: toggleScheme) {
                ZStack {
                    SunHalo()
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(TailwindColor.amber500.color, TailwindColor.amber400.color)
                        .solarSparkle()
                }
                .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                .contentShape(Circle())
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Cambiar tema claro u oscuro")
            Button { page = page == .feed ? .catalogo : .feed } label: {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tone.moss.onBadge)
                    .frame(width: 32, height: 32)
                    .background(Tone.moss.badgeFill)
                    .glowRing(.header, sparkleBadge: true)
                    .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Cambiar de página")
        }
        .padding(.horizontal, Spacing.margin)
        .frame(height: Sizes.header)
        .background { FrostedHeaderBackground() }
    }

    // MARK: Chips

    private var chips: some View {
        let titles = ["Todo", "2 colores", "3 colores", "4 colores", "Guardadas"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(titles.indices, id: \.self) { i in
                    FilterChip(title: titles[i], systemImage: i == 0 ? "sun.max" : nil, isSelected: chip == i) { chip = i }
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: Tarjeta del día

    private var comboId: Int { 104 }

    private var dayCard: some View {
        let colors = dictionary.map { PaletteColor.combo(comboId, in: $0) } ?? []
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sun.haze.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .pulse()
                    Text("Combinación del día").textRole(.overline).foregroundStyle(Theme.secondary)
                    PingDot(color: TailwindColor.teal400.color, size: 6, keepsCore: false)
                }
                Spacer()
                SolarBadge(title: WadaDictionary.numberLabel(comboId))
                    .overlay(Capsule().strokeBorder(TailwindColor.amber500.opacity(0.2).color, lineWidth: 1))
            }
            .padding(.trailing, 4)
            PaletteRibbon(colors: colors, style: .strip, height: Sizes.dayRibbon)
            HStack {
                Text(dictionary.map { galleryName(comboId, $0) } ?? "—")
                    .textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
                Spacer()
                Text("\(colors.count) colores").textRole(.labelSM).foregroundStyle(Theme.onSurfaceVariant)
            }
            SolarPrimaryButton(title: "Otra combinación", systemImage: "sparkles", variant: .amber, luminous: true) {}
                .padding(.top, Spacing.sm)
        }
        .padding(Spacing.md)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.container)
                SunDialRings()
                    .offset(x: MotionSpec.SunDial.offset, y: -MotionSpec.SunDial.offset)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .glowPulse(cornerRadius: Radius.card)
        .padding(.horizontal, Spacing.margin)
    }

    // MARK: Publicación

    private var postCard: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tone.amber.onBadge)
                    .frame(width: 36, height: 36)
                    .background(Tone.amber.badgeFill)
                    .glowRing(.postAmber)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Foto elegida").textRole(.labelLG).foregroundStyle(Theme.onSurface)
                        Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TailwindColor.amber500.color).accessibilityHidden(true)
                    }
                    Text("Ejemplo · hoy, 10:45 · Foto completa").textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(Theme.onSurfaceVariant).frame(width: 32, height: 32)
            }
            .padding(Spacing.md)
            photo
            PaletteRibbon(colors: Array(sample.palette.prefix(5)), style: .droplets(names: true, hex: true))
                .padding(Spacing.md)
            HStack(spacing: Spacing.md) {
                Label("Sí, es eso", systemImage: "heart")
                Label("Guardar", systemImage: "leaf")
                Label("Copiar", systemImage: "doc.on.doc")
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }
            .textRole(.labelMD)
            .foregroundStyle(Theme.onSurfaceVariant)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(shape.fill(Theme.card))
        .clipShape(shape)
        .glowCard(cornerRadius: Radius.card)
        .padding(.horizontal, Spacing.margin)
    }

    private var photo: some View {
        Theme.containerLow
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let cg = sample.photo {
                    Image(decorative: cg, scale: 1).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                SunbeamLensChip(title: "Foto completa · sin recorte").padding(Spacing.md)
            }
            .overlay(alignment: .topTrailing) {
                FrostedPhotoButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Abrir en Extraer") {}
                    .padding(Spacing.xs)
            }
    }

    // MARK: Pestañas

    private var tabBar: some View {
        let items: [(String, String)] = [("Feed", "sun.max.fill"), ("Extraer", "drop.halffull"), ("Rejilla", "square.grid.2x2"), ("Jardín", "leaf")]
        return HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button { tab = i } label: {
                    VStack(spacing: 2) {
                        Image(systemName: items[i].1)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background {
                                if tab == i {
                                    Circle().fill(TailwindColor.primaryFixed.opacity(0.35).color)
                                        .warmShadow(.activeTab, in: Circle())
                                }
                            }
                        Text(items[i].0).textRole(.labelSM)
                    }
                    .foregroundStyle(tab == i ? Theme.primary : Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(height: Sizes.tabBar)
        .background { FrostedTabBarBackground() }
    }
}

// MARK: - Catálogo

private struct MotionCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            row("pingDot · 1 s · ×2 y 0 al 75 %") {
                HStack(spacing: Spacing.lg) {
                    PingDot(color: TailwindColor.amber400.color, size: 10, keepsCore: false)
                    PingDot(color: TailwindColor.teal400.color, size: 10, keepsCore: true)
                    PingDot(color: Theme.secondaryContainer, size: 10, keepsCore: true)
                }
            }
            row("pulse · 2 s · opacidad 1 → 0,5") {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "sun.max").foregroundStyle(TailwindColor.amber400.color).pulse()
                    SparkleBadge()
                }
            }
            row("spinning · 3 s · 6 s · 8 s · 25 s") {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "sparkles").spinning(duration: MotionSpec.Spin.toast)
                    Image(systemName: "wand.and.stars").spinning(duration: MotionSpec.Spin.brassButton)
                    Image(systemName: "camera.filters").spinning(duration: MotionSpec.Spin.lensChip)
                    SunDialRings(size: 56)
                }
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            }
            row("solarSparkle · 12 s · 0→180° · ámbar 6→14 px") {
                ZStack {
                    SunHalo()
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(TailwindColor.amber500.color)
                        .solarSparkle()
                }
                .frame(width: 56, height: 56)
            }
            row("shimmerSweep · 2,5 s · blanco 30 %") {
                SolarPrimaryButton(title: "Botón de latón", systemImage: "sparkles", variant: .amber, luminous: true) {}
            }
            row("PressScaleButtonStyle · 0,95 · 0,98 · sube 4 pt") {
                HStack(spacing: Spacing.sm) {
                    Button {} label: { Text("Escala").demoPill() }.buttonStyle(.pressScale)
                    Button {} label: { Text("Ancho").demoPill() }.buttonStyle(.pressScaleWide)
                    Button {} label: { Text("Eleva").demoPill() }.buttonStyle(.pressLift())
                }
            }
            row("GlowRing · cabecera · publicación") {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "leaf.fill").foregroundStyle(Tone.moss.onBadge).frame(width: 32, height: 32)
                        .background(Tone.moss.badgeFill).glowRing(.header, sparkleBadge: true)
                    Image(systemName: "photo").foregroundStyle(Tone.amber.onBadge).frame(width: 36, height: 36)
                        .background(Tone.amber.badgeFill).glowRing(.postAmber)
                    Image(systemName: "camera").foregroundStyle(Tone.celadon.onBadge).frame(width: 36, height: 36)
                        .background(Tone.celadon.badgeFill).glowRing(.postTeal)
                }
            }
            row("WarmShadow · chip · lente · toast · pestaña") {
                HStack(spacing: Spacing.md) {
                    ForEach([WarmShadow.activeChip, .lensChipAmber, .toast, .activeTab], id: \.self) { preset in
                        Capsule().fill(Theme.card).frame(width: 56, height: 24).warmShadow(preset, in: Capsule())
                    }
                }
            }
            row("SunGlint · filo interior blanco 70 %") {
                HStack(spacing: Spacing.md) {
                    Capsule().fill(Theme.primary).frame(width: 120, height: 36).insetSunGlint(Capsule())
                    Capsule().fill(Theme.secondary).frame(width: 120, height: 36).insetSunGlint(Capsule(), opacity: MotionSpec.Glint.strong)
                }
            }
            row("SunbeamLensChip · FrostedPhotoButton") {
                HStack(spacing: Spacing.sm) {
                    SunbeamLensChip(title: "Recorte: persona")
                    SunbeamLensChip(title: "Foto completa", tone: .teal)
                    FrostedPhotoButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Abrir") {}
                }
                .padding(Spacing.sm)
                .background(LinearGradient(colors: [TailwindColor.teal300.opacity(0.5).color, TailwindColor.amber300.opacity(0.5).color],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
            }
            row("glowPulse · 4 s · ámbar ↔ verde azulado") {
                Text("Tarjeta que respira").textRole(.labelLG).foregroundStyle(Theme.onSurface)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .glowPulse(cornerRadius: Radius.card)
            }
            row("Toast luminoso · icono 3 s") {
                SolarToast(title: "Hex copiados", systemImage: "sparkles", luminous: true)
            }
        }
        .padding(.horizontal, Spacing.margin)
    }

    private func row<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
            content()
        }
    }
}

private extension View {
    func demoPill() -> some View {
        textRole(.labelMD)
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.chipVertical)
            .background(Capsule().fill(Theme.primary))
    }
}
#endif
