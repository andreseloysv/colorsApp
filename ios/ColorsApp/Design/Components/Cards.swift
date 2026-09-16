// Tarjetas del Feed, Extraer y la Rejilla (docs/design/DESIGN_SYSTEM.md §4 n.º 6, 7,
// 11, 12, 17 y 23). Todo color de datos va en un pocillo (§1.4); el pergamino, los
// lavados y las sombras cálidas se quedan en el marco. Acciones reales (§0.2 B):
// «Sí, es eso», «No», Guardar (colección local), Copiar hex y Compartir la tarjeta.
import SwiftUI

// MARK: - Prenda (Extraer)

/// Tarjeta de un color de la ropa (§4 n.º 17): bloque plano de 64 pt, «01 · 39 %», la etiqueta
/// de la prenda cuando la hay («Parte de arriba» / «Parte de abajo» / «Prenda entera», ADR-011),
/// nombre de Wada más cercano, hex y «ΔE 2,3». La tarjeta entera es un pocillo.
struct GarmentCard: View {
    /// Posición 1-based en la paleta.
    let index: Int
    let color: PaletteColor
    /// Región de prenda; nil = camino clásico (sin pose), la tarjeta queda como antes.
    var region: String? = nil
    var isSelected: Bool = false
    var isCopied: Bool = false
    var onTap: (() -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let blockShape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        let card = VStack(alignment: .leading, spacing: Spacing.sm) {
            blockShape
                .fill(color.color)
                .overlay(SwatchHairline(shape: blockShape))
                .frame(height: Sizes.garmentBlock)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(eyebrow)
                        .textRole(.overline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellTextSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.wellTextSecondary)
                        .accessibilityHidden(true)
                }
                if let region {
                    Text(region)
                        .textRole(.labelSM)
                        .foregroundStyle(Theme.wellText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).fill(Theme.wellFillAlt))
                        .overlay(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                            .strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)))
                        .padding(.top, 1)
                }
                Text(color.name ?? color.hex)
                    .textRole(.headlineSM)
                    .foregroundStyle(Theme.wellText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: Spacing.xs) {
                    Text(color.hex)
                        .textRole(.hex)
                        .foregroundStyle(Theme.wellTextSecondary)
                    Spacer(minLength: 0)
                    if let de = color.deltaE {
                        Text(DesignFormat.deltaE(de))
                            .textRole(.labelSM)
                            .foregroundStyle(Theme.wellText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).fill(Theme.wellFillAlt))
                            .overlay(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                                .strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)))
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background { shape.fill(Theme.wellFill).elevation(.rest, neutral: true) }
        .overlay(shape.strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)))
        .neutralZone(cornerRadius: Radius.card)
        .overlay { if isSelected { WellSelectionRing(shape: shape) } }

        Group {
            if let onTap {
                Button(action: onTap) { card.contentShape(shape) }.buttonStyle(.solarPress)
            } else {
                card
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(onTap == nil ? "" : "Copia el hex")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var eyebrow: String {
        let n = String(format: "%02d", index)
        guard let w = color.weight else { return n }
        return "\(n) · \(DesignFormat.percent(w))"
    }

    private var accessibilityText: String {
        var parts = ["Color \(index)"]
        if let w = color.weight { parts.append("\(Int((w * 100).rounded())) por ciento") }
        if let name = color.name { parts.append(name) }
        parts.append(color.hex)
        if let de = color.deltaE { parts.append(DesignFormat.deltaE(de)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Combinación del día / al azar

/// Tarjeta de combinación del día (Feed) o al azar (Rejilla) (§4 n.º 6 y 7).
struct DailyPickCard: View {
    enum Layout: Sendable, Equatable {
        /// Feed: «COMBINACIÓN DEL DÍA», tira de 24 pt, nombre `headline-md` y botón ámbar a todo el ancho.
        case day
        /// Rejilla: «AL AZAR», título y descripción, fichas de 48 pt y botón musgo compacto.
        case random(title: String, description: String)
    }

    let eyebrow: String
    let numberLabel: String
    let name: String
    let colors: [PaletteColor]
    /// «2 colores · Bloqueada» / «En tu rejilla».
    let status: String
    var layout: Layout = .day
    var buttonTitle: String = "Otra combinación"
    var onShuffle: () -> Void
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch layout {
            case .day: dayContent
            case .random(let title, let description): randomContent(title: title, description: description)
            }
        }
        .padding(Spacing.md)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.container)
                if case .random = layout {
                    SolarWash(kind: .warm, diameter: 150, blur: 36).offset(x: 50, y: -70)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .elevation(.restStrong)
        }
        .sunGlint(cornerRadius: Radius.card)
    }

    private var eyebrowRow: some View {
        HStack(spacing: 6) {
            Image(systemName: layout == .day ? "sun.max.fill" : "dice")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text(eyebrow).textRole(.overline).foregroundStyle(Theme.secondary)
            Spacer(minLength: Spacing.sm)
            SolarBadge(title: numberLabel)
        }
    }

    @ViewBuilder private var dayContent: some View {
        eyebrowRow
        openable {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                PaletteRibbon(colors: colors, style: .strip, height: Sizes.dayRibbon)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(name)
                        .textRole(.headlineMD)
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Text(status)
                        .textRole(.labelMD)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
        }
        SolarPrimaryButton(title: buttonTitle, systemImage: "dice", variant: .amber, elevated: false, action: onShuffle)
            .padding(.top, 2)
    }

    @ViewBuilder private func randomContent(title: String, description: String) -> some View {
        eyebrowRow
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textRole(.headlineSM).foregroundStyle(Theme.primary)
            Text(description).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        openable {
            PaletteRibbon(colors: colors, style: .tiles, height: Sizes.randomTile, wellPadding: Spacing.wellPaddingCompact)
        }
        .padding(.top, Spacing.xs)
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).textRole(.labelLG).foregroundStyle(Theme.primary).lineLimit(1)
                Text(status).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            SolarPrimaryButton(title: buttonTitle, systemImage: "dice", size: .compact, fullWidth: false,
                               elevated: false, action: onShuffle)
        }
        .padding(.top, 2)
    }

    @ViewBuilder private func openable<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if let onOpen {
            Button(action: onOpen) { content().contentShape(Rectangle()) }
                .buttonStyle(.solarPress)
                .accessibilityHint("Abre la combinación")
        } else {
            content()
        }
    }
}

// MARK: - Rejilla

/// Tarjeta de combinación en la cuadrícula de 2 columnas (§4 n.º 23).
struct PaletteGridCard: View {
    enum State: Sendable, Equatable {
        /// En tu rejilla; `since` = fecha corta del desbloqueo («14 sept»).
        case unlocked(since: String?)
        case locked
    }

    let title: String
    /// «Nº 012 · 3 colores».
    let subtitle: String
    let colors: [PaletteColor]
    var state: State
    /// Bloqueada pero mostrando sus colores (resultados de búsqueda).
    var revealsColors: Bool = false
    var isSaved: Bool = false
    var onToggleSave: (() -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Theme.wellFill
                PaletteRibbon(colors: colors, style: .stripes, height: Sizes.gridStripes - 2 * Spacing.wellPaddingCompact,
                              locked: isLocked && !revealsColors, inWell: false)
                    .padding(Spacing.wellPaddingCompact)
                Rectangle().fill(Theme.wellEdge).frame(height: 1 / max(displayScale, 1))
            }
            .frame(height: Sizes.gridStripes)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .textRole(.cardTitle)
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                Text(subtitle)
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    statusLabel
                    Spacer(minLength: Spacing.xs)
                    if let onToggleSave {
                        Button(action: onToggleSave) {
                            Image(systemName: isSaved ? "leaf.fill" : "leaf")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(isSaved ? Theme.primary : Theme.onSurfaceVariant)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.solarPress)
                        .accessibilityLabel(isSaved ? "Guardada en tu jardín" : "Guardar en tu jardín")
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
            .padding(.bottom, onToggleSave == nil ? Spacing.sm : 2)
        }
        .background { shape.fill(Theme.card).elevation(.rest) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeTokens.outlineVariant.color.opacity(0.35), lineWidth: 1 / max(displayScale, 1)))
    }

    private var isLocked: Bool { state == .locked }

    @ViewBuilder private var statusLabel: some View {
        switch state {
        case .unlocked(let since):
            Label {
                Text(since ?? "En tu rejilla").textRole(.labelSM).lineLimit(1)
            } icon: {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .semibold))
            }
            .labelStyle(TightLabelStyle())
            .foregroundStyle(Theme.primary)
        case .locked:
            Label {
                Text("Bloqueada").textRole(.labelSM).lineLimit(1)
            } icon: {
                Image(systemName: "lock").font(.system(size: 11, weight: .semibold))
            }
            .labelStyle(TightLabelStyle())
            .foregroundStyle(Theme.onSurfaceVariant)
        }
    }
}

/// Icono + texto con 4 pt de separación.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Publicación del Feed

/// Origen de un análisis (icono y título de la cabecera de la publicación).
enum PostSource: String, Sendable {
    case library, camera, picked

    var title: String {
        switch self {
        case .library: "Carrete"
        case .camera: "Cámara"
        case .picked: "Foto elegida"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "photo.stack"
        case .camera: "camera"
        case .picked: "photo.on.rectangle"
        }
    }
}

/// Combinación ganadora para pies de publicación y cosechas.
struct ComboMatchSummary: Sendable, Hashable {
    let comboId: Int
    /// Nombre aceptado → propuesto → «Nº 337».
    let name: String
    let colors: [PaletteColor]
    /// «Entre Nº 337 y Nº 027» si el motor lo marca ambiguo.
    var ambiguityText: String?

    var subtitle: String { DesignFormat.comboSubtitle(id: comboId, size: colors.count) }
}

/// Pie «Se parece a» (§5.1): tira de la combinación en pocillo + nombre + número.
struct ComboMatchFooter: View {
    let match: ComboMatchSummary?
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Se parece a").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
            if let match {
                let content = HStack(alignment: .center, spacing: Spacing.md) {
                    PaletteRibbon(colors: match.colors, style: .strip, height: 28, wellPadding: 6)
                        .frame(width: 104)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(match.name).textRole(.headlineSM).foregroundStyle(Theme.onSurface).lineLimit(2)
                        Text(match.subtitle).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                    if onOpen != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .accessibilityHidden(true)
                    }
                }
                if let onOpen {
                    Button(action: onOpen) { content.contentShape(Rectangle()) }
                        .buttonStyle(.solarPress)
                        .accessibilityHint("Abre la combinación")
                } else {
                    content
                }
                if let ambiguity = match.ambiguityText {
                    SolarBadge(title: ambiguity, systemImage: "arrow.left.arrow.right",
                               fill: Theme.secondaryFixed, foreground: Theme.onSecondaryFixedVariant)
                }
            } else {
                Text("El motor no ha encontrado combinación")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }
}

/// Compartir desde la barra de acciones.
enum ShareAction {
    case none
    case action(() -> Void)
    /// `ShareLink` con la imagen de la tarjeta ya renderizada.
    case image(Image, title: String)
    /// `ShareLink` con un fichero (PNG en disco, zip…).
    case url(URL, title: String)
}

/// Barra de acciones de una publicación (§4 n.º 12): Sí, No, Guardar, Copiar y Compartir.
/// Un solo voto: tras votar, el otro botón queda deshabilitado.
struct FeedActionBar: View {
    var verdict: Verdict?
    var isSaved: Bool = false
    var isCopied: Bool = false
    var onYes: (() -> Void)?
    var onNo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var share: ShareAction = .none

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Con textos grandes que no caben, la barra pasa a solo iconos (con etiqueta de VoiceOver).
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                bar(showsLabels: true)
                bar(showsLabels: true, copyLabel: false)
            }
            bar(showsLabels: false)
        }
    }

    private func bar(showsLabels: Bool, copyLabel: Bool = true) -> some View {
        HStack(spacing: Spacing.sm) {
            if let onYes {
                action(verdict == .yes ? "Es eso" : "Sí", icon: verdict == .yes ? "heart.fill" : "heart",
                       tint: verdict == .yes ? Theme.secondary : Theme.onSurfaceVariant,
                       label: "Sí, es eso", id: "feed.yes", enabled: verdict == nil || verdict == .yes,
                       showsLabel: showsLabels, action: onYes)
            }
            if let onNo {
                action("No", icon: verdict == .no ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                       tint: verdict == .no ? Theme.onSurface : Theme.onSurfaceVariant,
                       label: "No, no es eso", id: "feed.no", enabled: verdict == nil || verdict == .no,
                       showsLabel: showsLabels, action: onNo)
            }
            if let onSave {
                action(isSaved ? "Guardado" : "Guardar", icon: isSaved ? "leaf.fill" : "leaf",
                       tint: isSaved ? Theme.primary : Theme.onSurfaceVariant,
                       label: isSaved ? "Guardado en tu jardín" : "Guardar en tu jardín", id: "feed.save", enabled: true,
                       showsLabel: showsLabels, action: onSave)
            }
            if let onCopy {
                action(isCopied ? "Copiado" : "Copiar", icon: isCopied ? "checkmark" : "doc.on.doc",
                       tint: Theme.onSurfaceVariant, label: "Copiar hex de la combinación", id: "feed.copy", enabled: true,
                       showsLabel: showsLabels && copyLabel, action: onCopy)
            }
            Spacer(minLength: 0)
            shareButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .frame(minHeight: Sizes.minTouch)
    }

    private func action(_ title: String, icon: String, tint: Color, label: String, id: String,
                        enabled: Bool, showsLabel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                if showsLabel {
                    Text(title).textRole(.labelMD).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(tint)
            .frame(minHeight: Sizes.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.solarPress)
        .layoutPriority(1)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var shareButton: some View {
        let icon = Image(systemName: "square.and.arrow.up")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Theme.onSurfaceVariant)
            .frame(width: Sizes.minTouch, height: Sizes.minTouch)
            .contentShape(Rectangle())
        switch share {
        case .none:
            EmptyView()
        case .action(let run):
            Button(action: run) { icon }.accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        case .image(let image, let title):
            ShareLink(item: image, preview: SharePreview(title, image: image)) { icon }
                .accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        case .url(let url, let title):
            ShareLink(item: url, preview: SharePreview(title)) { icon }
                .accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        }
    }
}

/// Entrada del menú `ellipsis` de una publicación.
struct PostMenuItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void
}

/// Contenido de una publicación del Feed (§4 n.º 11, §5.1).
struct FeedPostContent {
    var source: PostSource
    /// «14 sept 2026, 10:45 · Persona principal · solo ropa».
    var metadata: String
    var photo: Image?
    /// Ancho / alto de la foto; se limita a 4:5 … 4:3.
    var photoAspectRatio: CGFloat = 4.0 / 5.0
    /// Aviso del recorte («Solo ropa», «Todas las personas (3)», «Foto completa»).
    var cropNotice: String?
    var cropNoticeIsFallback: Bool = false
    /// Marca de análisis antiguo («Análisis antiguo»): el scan se calculó con otra versión del
    /// motor o de la política y se re-analiza al abrirlo (ADR-011, CONTEXT §13). nil = al día.
    var outdatedNotice: String?
    /// «PALETA DE LA ROPA» o «PALETA DE LA FOTO».
    var paletteTitle: String = "Paleta de la ropa"
    var palette: [PaletteColor]
    var match: ComboMatchSummary?
    var verdict: Verdict?
    var isSaved: Bool = false
}

/// Acciones de una publicación (cada nil oculta su control).
struct FeedPostActions {
    var onYes: (() -> Void)?
    var onNo: (() -> Void)?
    var onSave: (() -> Void)?
    /// Copia los hex de la combinación ganadora.
    var onCopyCombo: (() -> Void)?
    /// Copia los hex de la paleta de la foto.
    var onCopyPalette: (() -> Void)?
    /// Toca una gota: copia ese hex.
    var onCopyColor: ((PaletteColor) -> Void)?
    var onOpenInExtract: (() -> Void)?
    var onOpenCombo: (() -> Void)?
    var menu: [PostMenuItem] = []
    var share: ShareAction = .none
}

/// Marca discreta de «Análisis antiguo» en la cabecera de una publicación: el scan se guardó
/// con otra versión del motor, del diccionario o de la política de análisis. Al abrirlo en
/// Extraer la app lo vuelve a analizar y la marca desaparece (CONTEXT §13, caso del Nº 067).
struct OutdatedScanChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(title).textRole(.labelSM).lineLimit(1)
        }
        .foregroundStyle(Theme.onSurfaceVariant)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.container))
        .padding(.top, 2)
        .accessibilityIdentifier("feed.post.outdated")
    }
}

/// Publicación del Feed (§4 n.º 11): cabecera, foto a sangre, paleta en pocillo, pie con la
/// combinación y barra de acciones reales.
struct FeedPostCard: View {
    let content: FeedPostContent
    var actions = FeedPostActions()
    var isCopied: Bool = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            photo
            VStack(alignment: .leading, spacing: Spacing.sm) {
                paletteHeader
                PaletteRibbon(colors: content.palette, style: .droplets(names: true, hex: true, weights: false),
                              wellCornerRadius: Radius.card, onTap: actions.onCopyColor)
            }
            .padding(Spacing.md)
            ComboMatchFooter(match: content.match, onOpen: actions.onOpenCombo)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
            divider
            FeedActionBar(verdict: content.verdict, isSaved: content.isSaved, isCopied: isCopied,
                          onYes: actions.onYes, onNo: actions.onNo, onSave: actions.onSave,
                          onCopy: actions.onCopyCombo, share: actions.share)
        }
        .background { shape.fill(Theme.card).elevation(.rest) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(scheme == .dark ? Theme.outlineVariant.opacity(0.6) : Theme.sepia.opacity(0.08),
                                    lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Theme.container.opacity(scheme == .dark ? 1 : 0.9)).frame(height: 1 / max(displayScale, 1))
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Tone.amber.badgeFill)
                .frame(width: Sizes.sourceIcon, height: Sizes.sourceIcon)
                .overlay {
                    Image(systemName: content.source.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tone.amber.onBadge)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.source.title).textRole(.labelLG).foregroundStyle(Theme.onSurface)
                Text(content.metadata).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                if let outdated = content.outdatedNotice {
                    OutdatedScanChip(title: outdated)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.sm)
            if !actions.menu.isEmpty {
                Menu {
                    ForEach(actions.menu) { item in
                        Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Más acciones")
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xs)
        .padding(.vertical, Spacing.sm)
    }

    private var clampedAspect: CGFloat {
        min(max(content.photoAspectRatio, Sizes.postAspectRange.lowerBound), Sizes.postAspectRange.upperBound)
    }

    private var photo: some View {
        Color.clear
            .aspectRatio(clampedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.containerLow)
            .overlay {
                if let image = content.photo {
                    image.resizable().scaledToFill()
                } else {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "photo").font(.system(size: 32, weight: .regular))
                        Text("Foto no disponible").textRole(.bodySM)
                    }
                    .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let notice = content.cropNotice {
                    HUDPill(title: notice, systemImage: "person.crop.rectangle",
                            kind: content.cropNoticeIsFallback ? .fallback : .notice)
                        .padding(Spacing.md)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let open = actions.onOpenInExtract {
                    Button(action: open) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 32, height: 32)
                            .parchmentFrost(Circle())
                            .elevation(.overPhoto)
                            .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.solarPress)
                    .padding(Spacing.xs)
                    .accessibilityLabel("Abrir en Extraer")
                }
            }
            .accessibilityElement(children: .contain)
    }

    private var paletteHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.primary)
                .accessibilityHidden(true)
            Text(content.paletteTitle).textRole(.overline).foregroundStyle(Theme.primary)
            Spacer(minLength: Spacing.sm)
            if let copy = actions.onCopyPalette {
                Button(action: copy) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .medium))
                        Text("Copiar hex").textRole(.labelSM)
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Copiar hex de la paleta")
            }
        }
    }
}
