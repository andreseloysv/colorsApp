// Publicación del Feed con las luces del ejemplo (docs/design/FIDELITY.md §3 F25–F44;
// `solar_feed…/code.html`, `<article>` con la clase de tarjeta con halo):
// - tarjeta blanca `rounded-xl` con `shadow-sm` + halo de tarjeta (`0 0 18px` ámbar 22 % +
//   `0 0 28px` musgo 12 %, borde ámbar 25 %);
// - cabecera `p-space-md` con icono de origen en círculo de 36 pt y aro `ring-2` ámbar (verde
//   azulado si la foto es de la cámara), título `label-lg` con destello y metadatos;
// - foto a sangre con la píldora de lente esmerilada (halo, filo y flor girando 8 s) y el botón
//   de lupa esmerilado con filo esmeralda;
// - banda de pergamino `bg-surface-container-low` con filo superior, rótulo de paleta y
//   «Copiar hex» que rebota; dentro, el POCILLO neutro con las gotas (pulsar 0,90 y marca de
//   copiado neutra) y el pie «Se parece a»;
// - barra de acciones reales con microanimaciones (Sí rebota, Guardar gira 12°, Copiar cambia
//   de símbolo). Sin «me gusta» ni contadores (§0.2 B).
// Zona neutra: gotas y tiras sin halo, tinte, sombra de color ni desenfoque; las luces van en
// el marco (tarjeta, píldoras sobre la foto, botones e iconos).
import SwiftUI

/// Tono de la publicación según su origen: ámbar (carrete, foto elegida) o verde azulado (cámara).
enum FeedPostTone: Sendable {
    case amber, teal

    init(_ source: PostSource) {
        self = source == .camera ? .teal : .amber
    }

    var ring: Color { self == .teal ? MotionSpec.postAvatarRingTeal.color : MotionSpec.postAvatarRingAmber.color }
    var plate: Color { self == .teal ? Tone.celadon.badgeFill : Tone.amber.badgeFill }
    var onPlate: Color { self == .teal ? Tone.celadon.onBadge : Tone.amber.onBadge }
    /// Glifo junto al título (`text-amber-500` / `text-teal-500`).
    var glyph: String { self == .teal ? "leaf.fill" : "sparkle" }
    var glyphColor: Color { self == .teal ? Color(brand: 0x14B8A6) : Color(brand: 0xF59E0B) }
}

struct FeedLuminousPostCard: View {
    let content: FeedPostContent
    var actions = FeedPostActions()
    var isCopied: Bool = false
    /// Gota recién copiada (marca neutra durante un momento).
    var copiedColorIndex: Int?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    @State private var paletteCopies = 0

    private var tone: FeedPostTone { FeedPostTone(content.source) }
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    private var hairline: CGFloat { 1 / max(displayScale, 1) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.container.opacity(0.6)).frame(height: hairline)
            photo
            paletteBand
            FeedLuminousActionBar(verdict: content.verdict, isSaved: content.isSaved, isCopied: isCopied,
                                  onYes: actions.onYes, onNo: actions.onNo, onSave: actions.onSave,
                                  onCopy: actions.onCopyCombo, share: actions.share)
                .background(Theme.card)
        }
        .clipShape(shape)
        .background {
            shape.fill(Theme.card).shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .glowCard(shape)
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(tone.plate)
                .frame(width: Sizes.sourceIcon, height: Sizes.sourceIcon)
                .overlay {
                    Image(systemName: content.source.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tone.onPlate)
                }
                .overlay(Circle().strokeBorder(tone.ring, lineWidth: 2).padding(-2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Text(content.source.title).textRole(.labelLG).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Image(systemName: tone.glyph)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tone.glyphColor)
                        .accessibilityHidden(true)
                }
                Text(content.metadata).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: Sizes.minTouch, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Más acciones")
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xs)
        .padding(.vertical, Spacing.md)
    }

    // MARK: Foto

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
                    FeedLensChip(title: notice, tone: tone, isFallback: content.cropNoticeIsFallback)
                        .padding(Spacing.md)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let open = actions.onOpenInExtract {
                    FrostedPhotoButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Abrir en Extraer",
                                       tone: tone == .teal ? .teal : .emerald, action: open)
                        .padding(6)
                }
            }
            .accessibilityElement(children: .contain)
    }

    // MARK: Banda de paleta

    private var paletteBand: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            paletteHeader
            FeedDropletWell(colors: content.palette, selection: copiedColorIndex, onTap: actions.onCopyColor)
                .padding(.top, Spacing.xs)
            ComboMatchFooter(match: content.match, onOpen: actions.onOpenCombo)
                .feedNeutralMargin(cornerRadius: Radius.block)
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.containerLow)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.containerHigh.opacity(0.5)).frame(height: hairline)
        }
    }

    private var paletteHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tone == .teal ? Color(light: 0x0F766E, dark: 0x5EEAD4) : Color(light: 0x059669, dark: 0x6EE7B7))
                .accessibilityHidden(true)
            Text(content.paletteTitle).textRole(.overline).foregroundStyle(Theme.primary).lineLimit(1)
            Spacer(minLength: Spacing.sm)
            if let copy = actions.onCopyPalette {
                Button {
                    paletteCopies += 1
                    copy()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : paletteCopies)
                        Text("Copiar hex").textRole(.labelSM)
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Copiar hex de la paleta")
            }
        }
    }
}

// MARK: - Píldora de lente

/// Píldora esmerilada sobre la foto (F32): `bottom-3 left-3 px-2.5 py-1 rounded-full
/// bg-surface-container-lowest/90 backdrop-blur-md`, halo `0 0 12px` ámbar 30 % (verde azulado
/// en cámara), filo `amber-300/40` (`teal-300/40`) e icono de flor girando cada 8 s. Con aviso de
/// recorte fallido: triángulo quieto y texto `secondary`.
struct FeedLensChip: View {
    let title: String
    var tone: FeedPostTone = .amber
    var isFallback: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            icon
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text(title)
                .textRole(.labelSM, weight: .semibold)
                .foregroundStyle(isFallback ? Theme.secondary : Theme.onSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Theme.containerLowest.opacity(0.9))
            }
        }
        .overlay(Capsule().strokeBorder(tone == .teal ? MotionSpec.lensChipTealBorder.color : MotionSpec.lensChipAmberBorder.color,
                                        lineWidth: 1))
        .warmShadow(tone == .teal ? .lensChipTeal : .lensChipAmber, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.post.lens")
    }

    @ViewBuilder private var icon: some View {
        if isFallback {
            Image(systemName: "exclamationmark.triangle")
        } else {
            Image(systemName: "camera.macro").spinning(duration: MotionSpec.Spin.lensChip)
        }
    }
}

// MARK: - Gotas

/// Gotas de la paleta (F37) dentro del pocillo neutro: círculos planos de 44 pt con filo fino,
/// nombre y hex; `group-active:scale-90` + subida de 4 pt al pulsar (300 ms) y, tras copiar, anillo
/// de selección neutro y 2 pt arriba. Hasta 5 por fila (`grid-cols-5 gap-1.5`).
struct FeedDropletWell: View {
    let colors: [PaletteColor]
    var selection: Int?
    var onTap: ((PaletteColor) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    var body: some View {
        let reduce = systemReduceMotion || forcedReduceMotion
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: max(1, min(colors.count, 5)))
        SwatchWell(padding: Spacing.wellPadding, cornerRadius: Radius.card) {
            if colors.isEmpty {
                Text("Sin colores")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.wellTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: Sizes.droplet)
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: Spacing.sm) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { i, color in
                        droplet(color, index: i, selected: selection == i, reduce: reduce)
                    }
                }
                .animation(reduce ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                  : .timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.slowDuration), value: selection)
            }
        }
        .feedNeutralMargin(cornerRadius: Radius.card)
        .accessibilityIdentifier("feed.post.droplets")
    }

    @ViewBuilder
    private func droplet(_ color: PaletteColor, index: Int, selected: Bool, reduce: Bool) -> some View {
        let cell = VStack(spacing: Spacing.xs) {
            Circle()
                .fill(color.color)
                .overlay(SwatchHairline(shape: Circle()))
                .overlay { if selected { WellSelectionRing(shape: Circle()) } }
                .frame(width: Sizes.droplet, height: Sizes.droplet)
                .offset(y: selected && !reduce ? -2 : 0)
                .padding(.top, 4)
            if let name = color.name {
                Text(name)
                    .textRole(.labelSM)
                    .foregroundStyle(Theme.wellText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(color.hex)
                .textRole(.hex)
                .foregroundStyle(Theme.wellTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        let label = DesignFormat.accessibilityLabel(color, position: index, total: colors.count)
        if let onTap {
            Button { onTap(color) } label: { cell.contentShape(Rectangle()) }
                .buttonStyle(.pressLift(scale: MotionSpec.Press.dropletScale, lift: MotionSpec.Press.lift))
                .accessibilityLabel(label)
                .accessibilityHint("Copia el hex")
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            cell.accessibilityElement(children: .ignore).accessibilityLabel(label)
        }
    }
}

// MARK: - Barra de acciones

/// Barra de acciones reales (F40–F44) con `px-space-md py-space-sm` y 12 pt entre acciones:
/// «Sí» (el corazón rebota al votar), «No», «Guardar» (la hoja gira 12° con muelle y rebota),
/// «Copiar» (el símbolo cambia a ✓ con transición) y Compartir. Un solo voto.
struct FeedLuminousActionBar: View {
    var verdict: Verdict?
    var isSaved: Bool = false
    var isCopied: Bool = false
    var onYes: (() -> Void)?
    var onNo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var share: ShareAction = .none

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }

    var body: some View {
        // Con textos grandes que no caben, la barra pasa a solo iconos (con etiqueta de VoiceOver).
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                bar(showsLabels: true, gap: Spacing.md)
                bar(showsLabels: true, gap: Spacing.sm)
                bar(showsLabels: true, gap: Spacing.sm, copyLabel: false)
            }
            bar(showsLabels: false, gap: Spacing.md)
        }
        .accessibilityIdentifier("feed.post.actions")
    }

    private func bar(showsLabels: Bool, gap: CGFloat, copyLabel: Bool = true) -> some View {
        HStack(spacing: gap) {
            if let onYes {
                action(verdict == .yes ? "Es eso" : "Sí", tint: verdict == .yes ? Theme.secondary : Theme.onSurfaceVariant,
                       label: "Sí, es eso", id: "feed.yes", enabled: verdict == nil || verdict == .yes,
                       showsLabel: showsLabels, action: onYes) {
                    Image(systemName: verdict == .yes ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: reduceMotion ? false : verdict == .yes)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            if let onNo {
                action("No", tint: verdict == .no ? Theme.onSurface : Theme.onSurfaceVariant,
                       label: "No, no es eso", id: "feed.no", enabled: verdict == nil || verdict == .no,
                       showsLabel: showsLabels, action: onNo) {
                    Image(systemName: verdict == .no ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            if let onSave {
                action(isSaved ? "Guardado" : "Guardar", tint: isSaved ? Theme.primary : Theme.onSurfaceVariant,
                       label: isSaved ? "Guardado en tu jardín" : "Guardar en tu jardín", id: "feed.save", enabled: true,
                       showsLabel: showsLabels, action: onSave) {
                    Image(systemName: isSaved ? "leaf.fill" : "leaf")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: reduceMotion ? false : isSaved)
                        .rotationEffect(.degrees(isSaved && !reduceMotion ? -12 : 0))
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55), value: isSaved)
                }
            }
            if let onCopy {
                action(isCopied ? "Copiado" : "Copiar", tint: isCopied ? Theme.primary : Theme.onSurfaceVariant,
                       label: "Copiar hex de la combinación", id: "feed.copy", enabled: true,
                       showsLabel: showsLabels && copyLabel, action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            Spacer(minLength: 0)
            shareButton
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, 2)
        .frame(minHeight: Sizes.minTouch)
        .padding(.vertical, 2)
    }

    private func action<Icon: View>(_ title: String, tint: Color, label: String, id: String, enabled: Bool,
                                    showsLabel: Bool, action: @escaping () -> Void,
                                    @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                icon().font(.system(size: 19, weight: .regular))
                if showsLabel {
                    Text(title).textRole(.labelMD).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(tint)
            .frame(minHeight: Sizes.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .layoutPriority(1)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var shareButton: some View {
        let icon = Image(systemName: "square.and.arrow.up")
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(Theme.onSurfaceVariant)
            .frame(width: Sizes.minTouch, height: Sizes.minTouch)
            .contentShape(Rectangle())
        switch share {
        case .none:
            EmptyView()
        case .action(let run):
            Button(action: run) { icon }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        case .image(let image, let title):
            ShareLink(item: image, preview: SharePreview(title, image: image)) { icon }
                .accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        case .url(let url, let title):
            ShareLink(item: url, preview: SharePreview(title)) { icon }
                .accessibilityLabel("Compartir tarjeta").accessibilityIdentifier("feed.share")
        }
    }
}

// MARK: - Chips de filtro

/// Fila de chips del Feed (F11–F13): `pt-space-xs pb-space-sm`, 8 pt entre chips, margen 16.
/// Activo: musgo con halo `0 0 12px` musgo 30 %, filo `emerald-400/30` y sol que late. En reposo:
/// punto de tono de marca de 8 pt con halo de su color (decoración: no es un color de datos) y,
/// al pulsar, halo del tono `0 0 10px` al 30 %. Pulsación 0,95.
struct FeedFilterChips: View {
    @Binding var selection: FeedFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(FeedFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        FeedFilterChipLabel(filter: filter, isSelected: filter == selection)
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityAddTraits(filter == selection ? .isSelected : [])
                    .accessibilityIdentifier("feed.filter.\(filter.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.margin)
            // Sitio para el halo del chip activo dentro del recorte del carrusel.
            .padding(.vertical, Spacing.sm)
        }
        .accessibilityIdentifier("feed.filters")
    }
}

private struct FeedFilterChipLabel: View {
    let filter: FeedFilter
    let isSelected: Bool

    @Environment(\.solarButtonPressed) private var pressed
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isSelected {
                Image(systemName: "sun.max")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(light: 0xFCD34D, dark: 0x0B3A1D))
                    .pulse()
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(dot.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: dot.color, radius: 3)
                    .accessibilityHidden(true)
            }
            Text(filter.title).textRole(.labelMD).lineLimit(1)
        }
        .foregroundStyle(isSelected ? Theme.onPrimary : Theme.onSurfaceVariant)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.chipVertical + 1)
        .frame(minHeight: 32)
        .background { Capsule().fill(isSelected ? Theme.primary : Theme.containerHigh) }
        .overlay {
            if isSelected {
                Capsule().strokeBorder(MotionSpec.activeChipBorder.color, lineWidth: 1).allowsHitTesting(false)
            }
        }
        .background {
            if isSelected {
                OuterGlow(shape: Capsule(), shadows: [MotionSpec.activeChip])
            } else if pressed {
                OuterGlow(shape: Capsule(), shadows: [ShadowSpec(dot.opacity(0.3), blur: 10)])
            }
        }
        .contentShape(Capsule())
    }

    /// Tonos de marca de los puntos (los del ejemplo: salvia, añil, helecho, terracota y trigo).
    private var dot: MotionRGBA {
        let dark = scheme == .dark
        switch filter {
        case .all, .two: return MotionRGBA(hex: 0x81B29A)
        case .three: return MotionRGBA(hex: dark ? 0xA9AED6 : 0x3D405B)
        case .four: return MotionRGBA(hex: dark ? 0x8FBF8D : 0x588157)
        case .saved: return MotionRGBA(hex: 0xE07A5F)
        case .unvoted: return MotionRGBA(hex: 0xE9B44C)
        }
    }
}

// MARK: - Zona neutra ampliada

extension View {
    /// Registra la vista como zona neutra ampliada 8 pt por cada lado: las motas de luz nunca
    /// pasan a menos de 8 pt de un pocillo (FIDELITY §0.2). No cambia el tamaño ni el dibujo.
    func feedNeutralMargin(cornerRadius: CGFloat) -> some View {
        padding(Spacing.sm)
            .neutralZone(cornerRadius: cornerRadius + Spacing.sm)
            .padding(-Spacing.sm)
    }
}
