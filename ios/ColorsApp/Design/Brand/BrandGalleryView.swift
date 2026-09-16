// Galería DEBUG de la marca: logotipo, wordmark con etiquetas de sección, icono de la app
// (el mismo dibujo que ios/Scripts/render_app_icon.swift) y los cuatro iconos de pestaña
// animados, activos e inactivos, en claro y oscuro.
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen brand-gallery \
//     [-uiBrandPage logo|tabbar] [-uiAppearance light|dark] [-uiBrandReduceMotion 1] [-uiBrandFrozenTime 1.2]
//     [-uiBrandScrollTo emblema|wordmark|icono|personajes]
#if DEBUG
import SwiftUI

enum BrandGalleryLaunch {
    static let screenValue = "brand-gallery"

    static var isRequested: Bool { value(after: "-uiScreen") == screenValue }

    static var page: BrandGalleryPage { value(after: "-uiBrandPage").flatMap(BrandGalleryPage.init(rawValue:)) ?? .logo }

    static var forcedScheme: ColorScheme? {
        switch value(after: "-uiAppearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    /// `-uiBrandReduceMotion 1` fuerza Reduce Motion en la galería.
    static var forcedReduceMotion: Bool? {
        value(after: "-uiBrandReduceMotion").map { $0 == "1" || $0 == "true" }
    }

    /// `-uiBrandScrollTo <sección>` desplaza la galería a esa sección al abrir (p. ej. `wordmark`).
    static var scrollTarget: String? { value(after: "-uiBrandScrollTo") }

    /// `-uiBrandFrozenTime <s>` congela todas las animaciones de marca en ese instante.
    static var frozenTime: TimeInterval? { value(after: "-uiBrandFrozenTime").flatMap(TimeInterval.init) }

    private static func value(after argument: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum BrandGalleryPage: String, CaseIterable, Identifiable {
    case logo, tabbar
    var id: String { rawValue }
    var title: String { self == .logo ? "Logotipo" : "Pestañas" }
}

struct BrandGalleryView: View {
    @State private var page = BrandGalleryLaunch.page
    @State private var reduceMotion = BrandGalleryLaunch.forcedReduceMotion ?? false
    @State private var liveSelection: BrandTabIconKind = .feed
    private let scheme = BrandGalleryLaunch.forcedScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        controls
                        switch page {
                        case .logo: logoPage
                        case .tabbar: tabbarPage
                        }
                    }
                    .padding(.horizontal, Spacing.margin)
                    .padding(.vertical, Spacing.md)
                }
                .onAppear {
                    if let target = BrandGalleryLaunch.scrollTarget {
                        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
            BrandTabBarPreview(selection: $liveSelection)
        }
        .background(Theme.surface.ignoresSafeArea())
        .environment(\.brandReduceMotionOverride, BrandGalleryLaunch.forcedReduceMotion ?? (reduceMotion ? true : nil))
        .environment(\.brandFrozenTime, BrandGalleryLaunch.frozenTime)
        .preferredColorScheme(scheme)
        .accessibilityIdentifier("brand.gallery")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("Página", selection: $page) {
                ForEach(BrandGalleryPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Reducir movimiento (forzado)", isOn: $reduceMotion)
                .textRole(.labelMD)
                .foregroundStyle(Theme.onSurfaceVariant)
                .tint(Theme.primary)
        }
    }

    // MARK: Logotipo

    @ViewBuilder
    private var logoPage: some View {
        section("CABECERA", "Emblema 32 pt, «ChromaSol» con punto ámbar y etiqueta de sección") {
            VStack(spacing: Spacing.sm) {
                ForEach(BrandTabIconKind.allCases) { kind in
                    headerStrip(kind.sectionLabel, dot: kind == .feed)
                }
            }
        }
        section("EMBLEMA", "Sol de hojas, rueda de color, prisma y prado; destello 12 s") {
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                caption("32 pt") { ChromaSolLogo(size: 32) }
                caption("48 pt") { ChromaSolLogo(size: 48) }
                caption("96 pt · destello") { ChromaSolLogo(size: 96, animated: true) }
            }
            .frame(maxWidth: .infinity)
            ChromaSolLogo(size: 220, animated: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
        }
        section("WORDMARK", "Literata 34 semibold y etiqueta Plus Jakarta Sans") {
            ChromaSolLockup(section: "Estudio de color", size: .display)
        }
        section("ICONO DE LA APP", "1024 × 1024 desde el mismo dibujo (claro y oscuro)") {
            HStack(spacing: Spacing.lg) {
                appIconTile(.light)
                appIconTile(.dark)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func headerStrip(_ label: String, dot: Bool) -> some View {
        HStack {
            ChromaSolLockup(section: label, showsDot: dot)
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .frame(height: Sizes.header)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.surface.opacity(0.85))
                Rectangle().fill(Color(brand: 0xF59E0B, opacity: 0.10)).frame(height: 1)
            }
            .shadow(color: Color(brand: 0xEAB308, opacity: 0.10), radius: 7, x: 0, y: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func appIconTile(_ scheme: ColorScheme) -> some View {
        caption(scheme == .dark ? "Oscuro" : "Claro") {
            ChromaSolEmblem(style: .appIcon, scheme: scheme, glow: false)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 120 * 0.2237, style: .continuous))
                .shadow(color: Theme.sepia.opacity(0.18), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: Pestañas

    @ViewBuilder
    private var tabbarPage: some View {
        section("BARRA DE PESTAÑAS", "Activa animada con halo verde; inactivas quietas") {
            VStack(spacing: Spacing.sm) {
                ForEach(BrandTabIconKind.allCases) { kind in
                    BrandTabBarPreview(selection: .constant(kind))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
        section("PERSONAJES", "Tiempos de code.html del ejemplo") {
            HStack(alignment: .top, spacing: 0) {
                ForEach(BrandTabIconKind.allCases) { kind in
                    VStack(spacing: Spacing.xs) {
                        BrandTabIcon(kind: kind, isActive: true, size: 56)
                            .frame(height: 84)
                        Text(kind.title).textRole(.labelMD).foregroundStyle(Theme.onSurface)
                        Text(timing(kind)).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(kind.title): \(kind.characterDescription)")
                }
            }
        }
        section("REPOSO", "Inactivos o con Reducir movimiento") {
            HStack(spacing: 0) {
                ForEach(BrandTabIconKind.allCases) { kind in
                    BrandTabIcon(kind: kind, isActive: false, size: 44)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func timing(_ kind: BrandTabIconKind) -> String {
        switch kind {
        case .feed: "bota 2,2 s\nparpadea 3,4 s"
        case .extraer: "aletea 2 s\nalas 0,18 s"
        case .rejilla: "se mece 3,2 s"
        case .jardin: "se balancea 2,6 s"
        }
    }

    // MARK: Utilidades

    private func section<Content: View>(_ title: String, _ detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).textRole(.overline).foregroundStyle(Theme.secondary)
            Text(detail).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
            content()
        }
        // Ancla de `-uiBrandScrollTo`: primera palabra del título en minúsculas y sin tildes.
        .id(title.split(separator: " ").first.map { $0.lowercased().folding(options: .diacriticInsensitive, locale: nil) } ?? title)
    }

    private func caption<Content: View>(_ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Spacing.xs) {
            content()
            Text(text).textRole(.labelSM).foregroundStyle(Theme.onSurfaceVariant)
        }
    }
}
#endif
