// Galería DEBUG del sistema de diseño (docs/design/DESIGN_SYSTEM.md): todos los
// componentes de ios/ColorsApp/Design con contenido real: combinaciones y nombres de
// dictionary.json y la paleta, el top-1 y los alfileres que calcula el motor sobre la
// foto de grupo embebida en Debug (harness/people/06_group_courier_street.png, CC0),
// sin recorte de sujeto. Solo existe en DEBUG.
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen design-gallery -uiGalleryPage feed
// Páginas: base, feed, feed-post, extraer, extraer-colores, rejilla, rejilla-tarjetas,
// jardin, jardin-estudio, extras. `-uiAppearance light|dark` fuerza el tema.
#if DEBUG
import SwiftUI
import UIKit
import ColorEngine

enum DesignGalleryLaunch {
    static let screenValue = "design-gallery"
    static let pageArgument = "-uiGalleryPage"
    static let appearanceArgument = "-uiAppearance"

    static var isRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiScreen"), i + 1 < args.count else { return false }
        return args[i + 1] == screenValue
    }

    static var page: DesignGalleryPage {
        value(after: pageArgument).flatMap(DesignGalleryPage.init(rawValue:)) ?? .base
    }

    static var forcedScheme: ColorScheme? {
        switch value(after: appearanceArgument) {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    private static func value(after argument: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum DesignGalleryPage: String, CaseIterable, Identifiable {
    case base, feed, feedPost = "feed-post", extraer, extraerColores = "extraer-colores", rejilla,
         rejillaTarjetas = "rejilla-tarjetas", jardin, jardinEstudio = "jardin-estudio", extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base: "Base"
        case .feed: "Feed"
        case .feedPost: "Publicación"
        case .extraer: "Extraer"
        case .extraerColores: "Colores"
        case .rejilla: "Rejilla"
        case .rejillaTarjetas: "Tarjetas"
        case .jardin: "Jardín"
        case .jardinEstudio: "Estudio"
        case .extras: "Extras"
        }
    }

    var tab: GalleryTab {
        switch self {
        case .feed, .feedPost: .feed
        case .extraer, .extraerColores: .extraer
        case .rejilla, .rejillaTarjetas: .rejilla
        case .jardin, .jardinEstudio, .base, .extras: .jardin
        }
    }
}

enum GalleryTab: Hashable { case feed, extraer, rejilla, jardin }

/// Nombre para la galería: el aceptado si existe; si no, los dos primeros colores de Wada.
func galleryName(_ id: Int, _ dictionary: WadaDictionary) -> String {
    let display = dictionary.displayName(id: id)
    guard display == WadaDictionary.numberLabel(id) else { return display }
    return dictionary.colors(ofComboId: id).prefix(2).map(\.name).joined(separator: " · ")
}

/// Datos reales para la galería: diccionario del bundle + análisis del motor sobre la foto de Debug.
struct GallerySample: Sendable {
    let photo: CGImage?
    let palette: [PaletteColor]
    let pins: [PhotoPin]
    let match: ComboMatchSummary?
    let second: ComboMatchSummary?

    static let empty = GallerySample(photo: nil, palette: [], pins: [], match: nil, second: nil)

    static func load(dictionary: WadaDictionary) -> GallerySample {
        guard let url = Bundle.main.url(forResource: "06_group_courier_street", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let raster = rasterize(image, maxSide: 1024) else { return .empty }
        let layers: PaletteDebugLayers
        do {
            layers = try raster.pixels.withUnsafeBufferPointer { px in
                try paletteDebugLayers(rgba: px, width: raster.width, height: raster.height, stride: raster.width * 4,
                                       matchOptions: .default, topK: 3)
            }
        } catch {
            return GallerySample(photo: image, palette: [], pins: [], match: nil, second: nil)
        }
        let palette = layers.analysis.swatches.enumerated().map { PaletteColor(id: $0.offset, swatch: $0.element, dictionary: dictionary) }
        let positions = PinOverlay.positions(labelMap: layers.labelMap, width: layers.debug.reducedWidth,
                                             height: layers.debug.reducedHeight, swatchCount: palette.count)
        let pins = palette.prefix(4).compactMap { c -> PhotoPin? in
            guard let p = positions[c.id] else { return nil }
            return PhotoPin(id: c.id, position: p, color: c, title: c.name ?? c.hex, detail: c.weight.map(DesignFormat.percent))
        }
        let hits = layers.analysis.hits
        func summary(_ i: Int) -> ComboMatchSummary? {
            guard hits.indices.contains(i) else { return nil }
            let id = hits[i].comboId
            var ambiguity: String?
            if i == 0, layers.analysis.ambiguous, hits.count > 1 {
                ambiguity = "Entre \(WadaDictionary.numberLabel(id)) y \(WadaDictionary.numberLabel(hits[1].comboId))"
            }
            return ComboMatchSummary(comboId: id, name: galleryName(id, dictionary),
                                     colors: PaletteColor.combo(id, in: dictionary), ambiguityText: ambiguity)
        }
        return GallerySample(photo: image, palette: palette, pins: pins, match: summary(0), second: summary(1))
    }

    private struct Raster { let width: Int; let height: Int; let pixels: [UInt8] }

    /// CGContext sRGB `.noneSkipLast` ≤ maxSide (como la app antes del motor).
    private static func rasterize(_ image: CGImage, maxSide: Int) -> Raster? {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Raster(width: w, height: h, pixels: pixels) : nil
    }
}

struct DesignGalleryView: View {
    @State private var page: DesignGalleryPage = DesignGalleryLaunch.page
    @State private var scheme: ColorScheme? = DesignGalleryLaunch.forcedScheme
    @State private var dictionary: WadaDictionary? = try? WadaDictionary.load()
    @State private var sample: GallerySample = .empty
    @State private var chip = "todo"
    @State private var segment = "cosechas"
    @State private var search = ""
    @State private var selectedPin: Int? = 0
    @State private var verdict: Verdict? = .yes
    @State private var saved = true
    @State private var shuffleSeed = 0
    @State private var toast: String?

    private var tabBinding: Binding<GalleryTab> {
        Binding(get: { page.tab }, set: { tab in
            switch tab {
            case .feed: page = .feed
            case .extraer: page = .extraer
            case .rejilla: page = .rejilla
            case .jardin: page = .jardin
            }
        })
    }

    private var isCapture: Bool {
        ProcessInfo.processInfo.arguments.contains(DesignGalleryLaunch.pageArgument)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(section: page.title.uppercased(), sunSymbol: scheme == .dark ? "moon.stars" : "sun.max",
                      sunAccessibilityLabel: "Cambiar tema claro u oscuro",
                      sunAction: { scheme = (scheme == .dark) ? .light : .dark },
                      avatarAction: { page = .jardin })
            if !isCapture {
                FilterChipRow(items: DesignGalleryPage.allCases.map { FilterChipItem(id: $0, title: $0.title) },
                              selection: $page)
                    .padding(.vertical, Spacing.xs)
            }
            ScrollView {
                pageContent
                    .padding(.horizontal, Spacing.margin)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
            }
            .scrollIndicators(.hidden)
            // «Publicación» enseña el final de la tarjeta (paleta, pie y acciones); «Feed» ya enseña el principio.
            .defaultScrollAnchor(page == .feedPost ? .bottom : .top)
            .id(page)
            SolarTabBar(items: SolarTabs.standard(feed: GalleryTab.feed, extraer: .extraer, rejilla: .rejilla, jardin: .jardin),
                        selection: tabBinding)
        }
        .background(Theme.surface.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast {
                SolarToast(title: toast).padding(.bottom, 84).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(Theme.primary)
        .preferredColorScheme(scheme)
        .task {
            guard let dictionary, sample.photo == nil else { return }
            let loaded = await Task.detached(priority: .userInitiated) { GallerySample.load(dictionary: dictionary) }.value
            sample = loaded
        }
        .accessibilityIdentifier("design.gallery")
    }

    // MARK: Páginas

    @ViewBuilder private var pageContent: some View {
        if let dictionary {
            switch page {
            case .base: basePage
            case .feed: feedPage(dictionary)
            case .feedPost: feedPostPage(dictionary)
            case .extraer: extraerPage(dictionary)
            case .extraerColores: extraerColoresPage(dictionary)
            case .rejilla: rejillaPage(dictionary)
            case .rejillaTarjetas: rejillaTarjetasPage(dictionary)
            case .jardin: jardinPage(dictionary)
            case .jardinEstudio: jardinEstudioPage(dictionary)
            case .extras: extrasPage(dictionary)
            }
        } else {
            Text("No se pudo cargar dictionary.json").textRole(.bodyMD).foregroundStyle(Theme.error)
        }
    }

    private var basePage: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tipografía").textRole(.overline).foregroundStyle(Theme.secondary)
                Text("Tu carrete en color").textRole(.headlineXLMobile).foregroundStyle(Theme.onSurface)
                Text("Combinación Nº 337").textRole(.headlineLGMobile).foregroundStyle(Theme.primary)
                Text("Colores de la ropa").textRole(.headlineMD).foregroundStyle(Theme.onSurface)
                Text("Cosechas recientes").textRole(.headlineSM).foregroundStyle(Theme.onSurface)
                Text("Se procesa en el teléfono; nada sale del dispositivo.").textRole(.bodyMD).foregroundStyle(Theme.onSurfaceVariant)
                Text("Carrete · 14 sept, 10:45").textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                HStack(spacing: Spacing.md) {
                    Text("Guardar").textRole(.labelLG).foregroundStyle(Theme.onSurface)
                    Text("2 colores").textRole(.labelMD).foregroundStyle(Theme.onSurface)
                    Text("#222524").textRole(.hex).foregroundStyle(Theme.onSurfaceVariant)
                    Text("20/348").textRole(.labelLG).monospacedDigit().foregroundStyle(Theme.primary)
                }
            }
            VStack(spacing: Spacing.sm) {
                SolarPrimaryButton(title: "Sí, es eso", systemImage: "heart") { flash("Gracias. Marcado como acierto.") }
                SolarPrimaryButton(title: "Otra combinación", systemImage: "dice", variant: .amber, elevated: false) {}
                HStack(spacing: Spacing.gutter) {
                    SolarSecondaryButton(title: "Copiar hex", systemImage: "doc.on.doc") { flash("Hex copiados") }
                    SolarSecondaryButton(title: "Compartir", systemImage: "square.and.arrow.up") {}
                }
                GhostButton(title: "Escanear carrete (200 fotos)", systemImage: "photo.stack") {}
                HStack(spacing: Spacing.gutter) {
                    SolarPrimaryButton(title: "Deshabilitado", size: .compact) {}.disabled(true)
                    SolarPrimaryButton(title: "Analizando…", size: .compact, isLoading: true) {}
                }
            }
            HStack(spacing: Spacing.sm) {
                VerdictBadge(verdict: .yes)
                VerdictBadge(verdict: .no)
                VerdictBadge(verdict: nil)
                SolarBadge(title: "Nº 104")
            }
        }
    }

    private func dayPick(_ d: WadaDictionary) -> some View {
        let id = ((Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0) * 7919 + shuffleSeed * 131) % 348 + 1
        let combo = d.combo(id: id)
        return DailyPickCard(eyebrow: "Combinación del día", numberLabel: WadaDictionary.numberLabel(id),
                             name: galleryName(id, d),
                             colors: PaletteColor.combo(id, in: d),
                             status: "\(combo?.size ?? 0) colores · Bloqueada",
                             onShuffle: { shuffleSeed += 1 }, onOpen: {})
    }

    private func feedPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FilterChipRow(items: [
                FilterChipItem(id: "todo", title: "Todo", systemImage: "sun.max.fill"),
                FilterChipItem(id: "2", title: "2 colores"),
                FilterChipItem(id: "3", title: "3 colores"),
                FilterChipItem(id: "4", title: "4 colores"),
                FilterChipItem(id: "guardadas", title: "Guardadas"),
            ], selection: $chip)
            .padding(.horizontal, -Spacing.margin)
            dayPick(d)
            feedPost(d)
        }
    }

    private func feedPostPage(_ d: WadaDictionary) -> some View {
        feedPost(d)
    }

    private func feedPost(_ d: WadaDictionary) -> some View {
        FeedPostCard(
            content: FeedPostContent(source: .library, metadata: "14 sept 2026, 10:45 · Foto completa",
                                     photo: sample.photo.map { Image(decorative: $0, scale: 1) },
                                     photoAspectRatio: sample.photo.map { CGFloat($0.width) / CGFloat($0.height) } ?? 0.8,
                                     cropNotice: "Foto completa", cropNoticeIsFallback: false,
                                     paletteTitle: "Paleta de la foto", palette: sample.palette,
                                     match: sample.match, verdict: verdict, isSaved: saved),
            actions: FeedPostActions(onYes: { verdict = verdict == .yes ? nil : .yes }, onNo: { verdict = verdict == .no ? nil : .no },
                                     onSave: { saved.toggle() }, onCopyCombo: { flash("Hex de la combinación copiados") },
                                     onCopyPalette: { flash("Hex de la paleta copiados") },
                                     onCopyColor: { flash("\($0.hex) copiado") }, onOpenInExtract: { page = .extraer },
                                     onOpenCombo: {},
                                     menu: [PostMenuItem(id: "open", title: "Abrir en Extraer", systemImage: "arrow.up.left.and.arrow.down.right") { page = .extraer },
                                            PostMenuItem(id: "delete", title: "Borrar del Feed", systemImage: "trash", isDestructive: true) {}],
                                     share: .action({})))
    }

    private func viewfinder(height: CGFloat) -> some View {
        ZStack {
            Theme.containerLow
            if let photo = sample.photo {
                Image(decorative: photo, scale: 1).resizable().scaledToFit()
                PinOverlay(pins: sample.pins, imageSize: CGSize(width: photo.width, height: photo.height),
                           selectedID: selectedPin, onSelect: { selectedPin = $0.id })
            } else {
                ProgressView()
            }
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            HStack {
                HUDPill(title: "Foto completa · sin recorte", systemImage: "person.crop.rectangle")
                Spacer()
                HUDPill(title: "Ver máscara", systemImage: "theatermask.and.paintbrush", kind: .toggle(isOn: false))
            }
            .padding(Spacing.md)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.primary)
                Text("Personas: 3 · la más grande").textRole(.labelSM).foregroundStyle(Theme.onSurfaceVariant)
                Spacer()
                SolarIconButton(systemImage: "square.3.layers.3d", accessibilityLabel: "Ver capas", size: 32, iconSize: 16,
                                foreground: Theme.primary, background: Theme.container) {}
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .parchmentFrost(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(Spacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .elevation(.rest)
    }

    private func extraerPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            viewfinder(height: 400)
            SectionHeader(title: "Colores de la foto", systemImage: "paintpalette")
            SolarBadge(title: "\(sample.palette.count) colores · foto completa", systemImage: "drop.halffull",
                       fill: Theme.container, foreground: Theme.onSurface)
            garmentGrid
        }
    }

    private var garmentGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.gutter), GridItem(.flexible(), spacing: Spacing.gutter)],
                  spacing: Spacing.gutter) {
            ForEach(Array(sample.palette.prefix(4).enumerated()), id: \.offset) { i, c in
                GarmentCard(index: i + 1, color: c, isSelected: selectedPin == c.id) { selectedPin = c.id; flash("\(c.hex) copiado") }
            }
        }
    }

    private func extraerColoresPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            garmentGrid
            PaletteRibbon(colors: sample.palette, style: .weights, height: Sizes.extractRibbon, wellCornerRadius: Radius.card)
            if let match = sample.match {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    PaletteRibbon(colors: match.colors, style: .strip, height: 64)
                    Text(match.name).textRole(.headlineLGMobile).foregroundStyle(Theme.onSurface)
                    Text(match.subtitle).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(Spacing.md)
                .solarCard()
            }
            SolarPrimaryButton(title: "Sí, es eso", systemImage: "heart") { flash("Gracias. Marcado como acierto.") }
            HStack(spacing: Spacing.gutter) {
                SolarSecondaryButton(title: "No, no es eso", systemImage: "hand.thumbsdown") {}
                SolarSecondaryButton(title: "Guardar", systemImage: "leaf") {}
            }
        }
    }

    private func gridCard(_ d: WadaDictionary, id: Int, state: PaletteGridCard.State, reveals: Bool = false, saved: Bool = false) -> some View {
        let colors = PaletteColor.combo(id, in: d)
        return PaletteGridCard(title: galleryName(id, d), subtitle: DesignFormat.comboSubtitle(id: id, size: colors.count), colors: colors,
                               state: state, revealsColors: reveals, isSaved: saved, onToggleSave: {})
    }

    private func rejillaPage(_ d: WadaDictionary) -> some View {
        let id = (shuffleSeed * 97 + 254) % 348 + 1
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            SolarSearchField(placeholder: "Busca por nombre, número o #hex", text: $search, onFilter: {})
            DailyPickCard(eyebrow: "Al azar", numberLabel: WadaDictionary.numberLabel(id),
                          name: galleryName(id, d),
                          colors: PaletteColor.combo(id, in: d), status: "En tu rejilla",
                          layout: .random(title: "Una combinación al azar",
                                          description: "Una de las 348 de Sanzo Wada. Tócala para ver sus colores y cómo desbloquearla."),
                          buttonTitle: "Otra", onShuffle: { shuffleSeed += 1 })
            FilterChipRow(items: [
                FilterChipItem(id: "todo", title: "Todas"),
                FilterChipItem(id: "2", title: "2 colores"),
                FilterChipItem(id: "3", title: "3 colores"),
                FilterChipItem(id: "4", title: "4 colores"),
                FilterChipItem(id: "desbloqueadas", title: "Desbloqueadas"),
            ], selection: $chip)
            .padding(.horizontal, -Spacing.margin)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.gutter), GridItem(.flexible(), spacing: Spacing.gutter)],
                      spacing: Spacing.gutter) {
                gridCard(d, id: 12, state: .unlocked(since: "14 sept"))
                gridCard(d, id: 67, state: .locked)
            }
        }
    }

    private func rejillaTarjetasPage(_ d: WadaDictionary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.gutter), GridItem(.flexible(), spacing: Spacing.gutter)],
                  spacing: Spacing.gutter) {
            gridCard(d, id: 12, state: .unlocked(since: "14 sept"))
            gridCard(d, id: 67, state: .locked)
            gridCard(d, id: 152, state: .unlocked(since: nil), saved: true)
            gridCard(d, id: 337, state: .locked, reveals: true)
            gridCard(d, id: 254, state: .unlocked(since: "2 sept"))
            gridCard(d, id: 301, state: .locked)
        }
    }

    private func jardinPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            StatHeader(detail: "Acierto: 82 % (41 de 50 votos)", stats: [
                StatItem(id: "fotos", value: "42", label: "Fotos analizadas", tone: .moss),
                StatItem(id: "rejilla", value: "20/348", label: "Desbloqueadas", tone: .amber),
                StatItem(id: "si", value: "41", label: "Sí, es eso", tone: .celadon),
            ], onSettings: {})
            SegmentedPill(items: [(id: "cosechas", title: "Cosechas"), (id: "guardadas", title: "Guardadas")], selection: $segment)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Colecciones").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
                    Spacer()
                    Text("3").textRole(.labelSM).foregroundStyle(Theme.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        CollectionPill(title: "2 colores", count: "12/120", kind: .collection(.moss)) {}
                        CollectionPill(title: "3 colores", count: "5/120", kind: .collection(.amber)) {}
                        CollectionPill(title: "4 colores", count: "3/108", kind: .collection(.celadon)) {}
                    }
                    .padding(.horizontal, Spacing.margin)
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, -Spacing.margin)
            }
            SectionHeader(title: "Cosechas", systemImage: "paintpalette", trailing: "Más recientes")
            harvestDroplets(d)
        }
    }

    private func harvestDroplets(_ d: WadaDictionary) -> some View {
        HarvestRow(thumbnail: sample.photo.map { Image(decorative: $0, scale: 1) },
                   title: sample.match?.name ?? "Nº —", metadata: "ayer · Carrete", verdict: .yes,
                   palette: sample.palette, variant: .droplets, isSaved: true, onCopyDominant: { flash("Hex dominante copiado") },
                   onToggleSave: {})
    }

    private func jardinEstudioPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HarvestRow(thumbnail: sample.photo.map { Image(decorative: $0, scale: 1) },
                       title: sample.second?.name ?? "Nº —", metadata: "hace 3 días · Foto elegida", verdict: nil,
                       palette: sample.palette, variant: .proportion,
                       tags: [sample.second.map { WadaDictionary.numberLabel($0.comboId) } ?? "Nº —", "Ambigua"],
                       onToggleSave: {})
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Estudio", systemImage: "square.and.arrow.up.on.square")
                    Text("Herramientas").textRole(.overline).foregroundStyle(Theme.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                          spacing: Spacing.sm) {
                    ExportTile(title: "Compartir tarjeta", detail: "Imagen 1080 × 1350 de la última cosecha",
                               systemImage: "square.and.arrow.up", tone: .moss) {}
                    ExportTile(title: "Copiar hex", detail: "Los colores de la última cosecha",
                               systemImage: "doc.on.doc", tone: .amber, state: .ready) {}
                    ExportTile(title: "Exportar diagnóstico", detail: "Zip con veredictos, tiempos y fotos votadas",
                               systemImage: "doc.zipper", tone: .celadon, state: .working) {}
                    ExportTile(title: "Escanear carrete", detail: "Últimas 200 fotos, en el teléfono",
                               systemImage: "photo.stack", tone: .amber) {}
                }
            }
            .padding(Spacing.md)
            .solarCard(fill: Theme.container, elevation: .small)
        }
    }

    private func extrasPage(_ d: WadaDictionary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                StoryProgressBar(count: 11, current: 8, progress: 0.6)
                Text("9 · Asignación a colores").textRole(.headlineMD).foregroundStyle(.white)
                Text("Cada píxel de la ropa alimenta a un color de la paleta.").textRole(.bodyMD).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Spacing.md)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.storyBackdrop))
            Text("Pocillos").textRole(.overline).foregroundStyle(Theme.secondary)
            PaletteRibbon(colors: PaletteColor.combo(337, in: d), style: .strip, height: 32, selection: 1)
            PaletteRibbon(colors: sample.palette, style: .weights, height: Sizes.weightBar)
            PaletteRibbon(colors: PaletteColor.combo(301, in: d), style: .tiles, height: Sizes.randomTile, selection: 2)
            HStack(spacing: Spacing.gutter) {
                PaletteRibbon(colors: PaletteColor.combo(152, in: d), style: .stripes, height: 64, wellPadding: 6)
                PaletteRibbon(colors: PaletteColor.combo(152, in: d), style: .stripes, height: 64, locked: true, wellPadding: 6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sample.palette.prefix(4)) { MicroColorPill(color: $0) }
                }
            }
            HStack(spacing: Spacing.md) {
                SwatchBead(color: sample.palette.first?.color ?? .black)
                SolarToast(title: "#222524 copiado")
            }
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation { toast = nil }
        }
    }
}
#endif
