// Piezas del Feed que no están en el sistema de diseño (docs/design/DESIGN_SYSTEM.md §4
// n.º 29 y 32): banner del escaneo del carrete, estado vacío y la fila de publicación que
// carga la foto del análisis y conecta `FeedLuminousPostCard` (FeedLuminousPost.swift) con
// acciones reales (§0.2 B: «Sí, es eso», «No», Guardar, Copiar hex y Compartir; sin «me gusta»
// ni contadores). Luces y movimiento del ejemplo: docs/design/FIDELITY.md §3.
import SwiftUI

// MARK: - Datos de una publicación

/// Lo que pinta una publicación, calculado una vez por versión del scan (`rev`).
struct FeedItem: Identifiable, Hashable {
    let scan: ScanRecord
    let palette: [PaletteColor]
    let match: ComboMatchSummary?
    let top1Size: Int?
    let metadata: String
    let notice: String?
    let noticeIsFallback: Bool
    let paletteTitle: String
    /// «Análisis antiguo» si el scan se calculó con otra versión del motor o de la política.
    let outdatedNotice: String?

    var id: String { scan.id }

    init(scan: ScanRecord, dictionary: WadaDictionary, isExample: Bool = false, timeZone: TimeZone = .current) {
        self.scan = scan
        palette = FeedPostText.palette(scan, in: dictionary)
        match = FeedComboName.match(for: scan, in: dictionary)
        top1Size = scan.top1.flatMap { dictionary.combo(id: $0)?.size }
        metadata = FeedPostText.metadata(scan, timeZone: timeZone, isExample: isExample)
        let crop = FeedPostText.cropNotice(scan)
        notice = crop?.text
        noticeIsFallback = crop?.isFallback ?? false
        paletteTitle = FeedPostText.paletteTitle(scan)
        outdatedNotice = FeedPostText.outdatedNotice(scan)
    }

    /// El análisis es de una versión anterior: al abrirlo en Extraer se recalcula.
    var isOutdated: Bool { outdatedNotice != nil }

    /// Hex de la combinación ganadora (lo que copia «Copiar»).
    var comboHexList: String? { match.map { DesignFormat.hexList($0.colors) } }
}

/// Acciones de una publicación (las implementa FeedView).
struct FeedPostHandlers {
    var vote: (FeedbackVerdict) -> Void
    var toggleSave: () -> Void
    var copyCombo: () -> Void
    var copyPalette: () -> Void
    var copyColor: (PaletteColor) -> Void
    var openInExtract: (CGImage?) -> Void
    var openCombo: (Int) -> Void
    var share: (CGImage?) -> Void
    var delete: () -> Void
}

// MARK: - Publicación

struct FeedPostRow: View {
    let item: FeedItem
    let verdict: FeedbackVerdict?
    let isSaved: Bool
    let isCopied: Bool
    let isReopening: Bool
    let photoStore: ScanPhotoStore
    let handlers: FeedPostHandlers

    @State private var photo: CGImage?
    /// Gota copiada hace un momento (marca neutra de 1,2 s).
    @State private var copiedColorIndex: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                FeedAccessiblePostCard(content: content, actions: actions, isCopied: isCopied)
            } else {
                FeedLuminousPostCard(content: content, actions: actions, isCopied: isCopied, copiedColorIndex: copiedColorIndex)
            }
        }
            .overlay {
                if isReopening {
                    ProgressView("Reanalizando…")
                        .padding(Spacing.md)
                        .parchmentFrost(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.post.\(item.id)")
            .task(id: "\(item.id)#\(item.scan.rev)") {
                photo = await ScanPhotoLoader.image(for: item.scan, store: photoStore)
            }
    }

    private var content: FeedPostContent {
        FeedPostContent(source: FeedPostText.source(item.scan.source), metadata: item.metadata,
                        photo: photo.map { Image(decorative: $0, scale: 1) },
                        photoAspectRatio: photo.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 4.0 / 5.0,
                        cropNotice: item.notice, cropNoticeIsFallback: item.noticeIsFallback,
                        outdatedNotice: item.outdatedNotice,
                        paletteTitle: item.paletteTitle, palette: item.palette, match: item.match,
                        verdict: FeedPostText.verdict(verdict), isSaved: isSaved)
    }

    private func markCopied(_ color: PaletteColor) {
        guard let index = item.palette.firstIndex(of: color) else { return }
        copiedColorIndex = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedColorIndex == index { copiedColorIndex = nil }
        }
    }

    private var actions: FeedPostActions {
        var menu = [
            PostMenuItem(id: "open", title: "Abrir en Extraer", systemImage: "arrow.up.left.and.arrow.down.right") {
                handlers.openInExtract(photo)
            },
        ]
        if let match = item.match {
            menu.append(PostMenuItem(id: "combo", title: "Ver combinación", systemImage: "square.grid.2x2") {
                handlers.openCombo(match.comboId)
            })
        }
        menu.append(PostMenuItem(id: "delete", title: "Borrar del Feed", systemImage: "trash", isDestructive: true) {
            handlers.delete()
        })
        return FeedPostActions(
            onYes: { handlers.vote(.yes) },
            onNo: { handlers.vote(.no) },
            onSave: handlers.toggleSave,
            onCopyCombo: item.match == nil ? nil : handlers.copyCombo,
            onCopyPalette: item.palette.isEmpty ? nil : handlers.copyPalette,
            onCopyColor: { color in
                handlers.copyColor(color)
                markCopied(color)
            },
            onOpenInExtract: photo == nil ? nil : { handlers.openInExtract(photo) },
            onOpenCombo: item.match.map { match in { handlers.openCombo(match.comboId) } },
            menu: menu,
            share: .action({ handlers.share(photo) }))
    }
}

// MARK: - Banner del escaneo del carrete

/// Progreso del escaneo del carrete bajo los chips (§4 n.º 29).
struct FeedScanBanner: View {
    let progress: ScanProgress

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "photo.stack")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Tone.amber.badgeFill))
                .overlay(Circle().strokeBorder(MotionSpec.postAvatarRingAmber.color, lineWidth: 2).padding(-2))
                .overlay(alignment: .topTrailing) {
                    PingDot(color: TailwindColor.teal400.color, size: 6, keepsCore: true).offset(x: 1, y: -1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.text(progress)).textRole(.labelLG).foregroundStyle(Theme.onSurface)
                if progress.phase == .analyzing {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.primary)
                        .background(Capsule().fill(Theme.surfaceVariant))
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Theme.primary)
                }
            }
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.container))
        .glowCard(cornerRadius: Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.scanProgress")
    }

    static func isVisible(_ progress: ScanProgress) -> Bool {
        switch progress.phase {
        case .requestingAccess, .fetching, .analyzing: true
        case .idle, .finished, .failed: false
        }
    }

    static func text(_ progress: ScanProgress) -> String {
        switch progress.phase {
        case .requestingAccess: "Pidiendo acceso a Fotos…"
        case .fetching: "Buscando las últimas fotos…"
        case .analyzing: "Analizando \(progress.processed)/\(progress.total) fotos del carrete"
        case .finished: "Escaneo terminado"
        case .failed: "El escaneo no ha podido terminar"
        case .idle: ""
        }
    }
}

// MARK: - Estado vacío

/// Feed sin publicaciones (§4 n.º 32): invitación a Extraer y al escaneo del carrete.
struct FeedEmptyState: View {
    var title: String = "Tus fotos analizadas aparecen aquí"
    var message: String = "Analiza la ropa de una foto o escanea tu carrete: cada análisis se convierte en una publicación con su paleta y la combinación de Wada que más se parece. Todo ocurre en el teléfono."
    var onAnalyze: (() -> Void)?
    var onScanLibrary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ZStack {
                Circle().fill(Tone.amber.badgeFill)
                FeedSunSpirit()
                    .frame(width: 44, height: 44)
                    .solarSparkle()
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            Text(title)
                .textRole(.headlineMD)
                .foregroundStyle(Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textRole(.bodyLG)
                .foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if let onAnalyze {
                FeedBrassButton(title: "Analizar una foto", systemImage: "camera.macro", action: onAnalyze)
                    .padding(.top, Spacing.xs)
                    .accessibilityIdentifier("feed.empty.analyze")
            }
            if let onScanLibrary {
                GhostButton(title: "Escanear carrete", systemImage: "photo.stack", action: onScanLibrary)
                    .accessibilityIdentifier("feed.empty.scan")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                SolarWash(kind: .warm, diameter: 180, blur: 44).offset(x: 60, y: -60)
                SolarWash(kind: .green, diameter: 160, blur: 44).offset(x: -220, y: 200)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .glowPulse(cornerRadius: Radius.card)
        .accessibilityIdentifier("feed.empty")
    }
}

// MARK: - Tamaños de accesibilidad

/// Publicación para tamaños de texto de accesibilidad (§5.1: «filas de 1 swatch + nombre +
/// hex»): todo en vertical, sin truncar nombres ni hex. Mismos datos, pocillos y acciones que
/// `FeedPostCard`.
struct FeedAccessiblePostCard: View {
    let content: FeedPostContent
    var actions = FeedPostActions()
    var isCopied: Bool = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.md)
            photo
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let notice = content.cropNotice {
                    Label(notice, systemImage: content.cropNoticeIsFallback ? "exclamationmark.triangle" : "person.crop.rectangle")
                        .textRole(.bodyMD)
                        .foregroundStyle(content.cropNoticeIsFallback ? Theme.secondary : Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let outdated = content.outdatedNotice {
                    Label(outdated, systemImage: "clock.arrow.circlepath")
                        .textRole(.bodyMD)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feed.post.outdated")
                }
                Text(content.paletteTitle)
                    .textRole(.overline)
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                SwatchWell(cornerRadius: Radius.card) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(content.palette.enumerated()), id: \.offset) { i, color in
                            swatchRow(color, index: i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let copy = actions.onCopyPalette {
                    Button(action: copy) {
                        Label("Copiar hex de la paleta", systemImage: "doc.on.doc")
                            .textRole(.labelLG)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.solarPress)
                }
                footer
            }
            .padding(Spacing.md)
            Rectangle().fill(Theme.container).frame(height: 1 / max(displayScale, 1))
            FeedLuminousActionBar(verdict: content.verdict, isSaved: content.isSaved, isCopied: isCopied,
                                  onYes: actions.onYes, onNo: actions.onNo, onSave: actions.onSave,
                                  onCopy: actions.onCopyCombo, share: actions.share)
        }
        .clipShape(shape)
        .background { shape.fill(Theme.card) }
        .glowCard(shape)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: content.source.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Tone.amber.onBadge)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Tone.amber.badgeFill))
                    .accessibilityHidden(true)
                Spacer()
                if !actions.menu.isEmpty {
                    Menu {
                        ForEach(actions.menu) { item in
                            Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                                Label(item.title, systemImage: item.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                    }
                    .accessibilityLabel("Más acciones")
                }
            }
            Text(content.source.title).textRole(.labelLG).foregroundStyle(Theme.onSurface)
            Text(content.metadata).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var photo: some View {
        let aspect = min(max(content.photoAspectRatio, Sizes.postAspectRange.lowerBound), Sizes.postAspectRange.upperBound)
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.containerLow)
            .overlay {
                if let image = content.photo {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private func swatchRow(_ color: PaletteColor, index: Int) -> some View {
        let row = HStack(alignment: .center, spacing: Spacing.md) {
            Circle()
                .fill(color.color)
                .overlay(SwatchHairline(shape: Circle()))
                .frame(width: Sizes.droplet, height: Sizes.droplet)
            VStack(alignment: .leading, spacing: 2) {
                if let name = color.name {
                    Text(name).textRole(.labelLG).foregroundStyle(Theme.wellText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(color.hex).textRole(.hex).foregroundStyle(Theme.wellTextSecondary)
                if let w = color.weight {
                    Text(DesignFormat.percent(w)).textRole(.labelMD).foregroundStyle(Theme.wellTextSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        return Group {
            if let copy = actions.onCopyColor {
                Button { copy(color) } label: { row }
                    .buttonStyle(.solarPress)
                    .accessibilityHint("Copia el hex")
            } else {
                row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignFormat.accessibilityLabel(color, position: index, total: content.palette.count))
        .accessibilityAddTraits(actions.onCopyColor == nil ? [] : .isButton)
    }

    @ViewBuilder private var footer: some View {
        Text("Se parece a").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
        if let match = content.match {
            let body = VStack(alignment: .leading, spacing: Spacing.sm) {
                PaletteRibbon(colors: match.colors, style: .strip, height: 32)
                Text(match.name).textRole(.headlineSM).foregroundStyle(Theme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(match.subtitle).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                if let ambiguity = match.ambiguityText {
                    Text(ambiguity).textRole(.labelMD).foregroundStyle(Theme.onSecondaryFixedVariant)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                        .background(RoundedRectangle(cornerRadius: Radius.block, style: .continuous).fill(Theme.secondaryFixed))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let open = actions.onOpenCombo {
                Button(action: open) { body.contentShape(Rectangle()) }
                    .buttonStyle(.solarPress)
                    .accessibilityHint("Abre la combinación")
            } else {
                body
            }
        } else {
            Text("El motor no ha encontrado combinación").textRole(.bodyMD).foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Combinación del día para tamaños de accesibilidad: rótulo, número y botón en líneas propias.
struct FeedAccessibleDayCard: View {
    let eyebrow: String
    let numberLabel: String
    let name: String
    let colors: [PaletteColor]
    let status: String
    var onShuffle: () -> Void
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(eyebrow).textRole(.overline).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(numberLabel).textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
            let content = VStack(alignment: .leading, spacing: Spacing.sm) {
                PaletteRibbon(colors: colors, style: .strip, height: Sizes.dayRibbon)
                Text(name).textRole(.headlineMD).foregroundStyle(Theme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status).textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onOpen {
                Button(action: onOpen) { content.contentShape(Rectangle()) }
                    .buttonStyle(.solarPress)
                    .accessibilityHint("Abre la combinación")
            } else {
                content
            }
            FeedBrassButton(title: "Otra", systemImage: "sparkles", action: onShuffle)
                .padding(.top, Spacing.sm)
                .accessibilityLabel("Otra combinación")
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.container))
        .glowPulse(cornerRadius: Radius.card)
    }
}
