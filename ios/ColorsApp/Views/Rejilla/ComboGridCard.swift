// Tarjeta de combinación de la Rejilla (docs/design/DESIGN_SYSTEM.md §4 n.º 23, captura
// «la_rejilla» del ejemplo; FIDELITY.md §5 R25–R30): franjas verticales dentro de un pocillo neutro
// con 6 pt de relleno (en claro el pocillo y la tarjeta son el mismo blanco: las franjas llegan
// ópticamente al borde, como en el ejemplo), nombre curado o propuesto (marcado con insignia con
// halo), número, estado y «Guardar» en el Jardín (rebote del icono).
// Luz (R25/R26 y §1.3 L1): halo de tarjeta tenue permanente (ámbar 12 % + musgo 7 %, filo ámbar
// 15 %) sobre el pergamino; al pulsar (`hover:` del ejemplo en táctil): escala 0,98, sombra
// `0 8px 24px -4px rgba(253,147,63,0.2)` y aura melocotón en la esquina inferior derecha (zona de
// texto, lejos de las franjas), 300 ms; con «Reducir movimiento», opacidad 0,8.
// Bloqueada: los colores se ven SIEMPRE tal cual y la tarjeta sigue siendo clara y luminosa
// (`surface-container-lowest`, como las del ejemplo); el bloqueo se marca solo con la píldora
// «Bloqueada» con candado y el número. El gris se reserva para el modo de alto contraste.
// Sin «me gusta», autores ni cifras de terceros (§0.2 B).
import SwiftUI

struct ComboGridCard: View {
    enum State: Sendable, Equatable {
        /// En tu rejilla desde `since` («14 sept»).
        case unlocked(since: String)
        case locked
    }

    let comboId: Int
    let name: ComboName
    let colors: [PaletteColor]
    let state: State
    var isSaved: Bool = false
    var onOpen: (() -> Void)?
    var onToggleSave: (() -> Void)?

    @SwiftUI.State private var isPressed = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    private var isLocked: Bool { state == .locked }
    /// Con tamaños de accesibilidad (1 columna) los textos pasan a varias líneas y el pie se apila.
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    /// Alto contraste: la bloqueada vuelve a la placa gris (la píldora sola no basta).
    private var dimsLocked: Bool { isLocked && contrast == .increased }

    /// Metadatos del pie (`font-body-sm text-[11px]`): 11 pt, mínimo de iOS.
    static let metaRole = TextRole(id: "grid-meta", family: .sans, weight: .regular, size: 11, lineHeight: 14,
                                   tracking: 0, textStyle: .caption2)

    /// Halo permanente de la tarjeta de la cuadrícula: L1 a la mitad (348 tarjetas a la vez).
    /// `0 0 18px` ámbar 12 % + `0 0 28px` musgo 7 %, filo ámbar 15 %.
    static let restGlow = GlowState(inner: ShadowSpec(TailwindColor.yellow500.opacity(0.12), blur: 18),
                                    outer: ShadowSpec(TailwindColor.moss.opacity(0.07), blur: 28),
                                    border: TailwindColor.yellow500.opacity(0.15))

    /// Respuesta al pulsar: escala, desplazamiento vertical de la sombra cálida y opacidad (tests).
    static func pressEffect(pressed: Bool, reduceMotion: Bool) -> (scale: CGFloat, glowOpacity: Double, opacity: Double) {
        guard pressed else { return (1, 0, 1) }
        return reduceMotion ? (1, 0, 0.8) : (MotionSpec.Press.wideScale, 0.2, 1)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let effect = Self.pressEffect(pressed: isPressed, reduceMotion: reduceMotion)
        ZStack(alignment: .bottomTrailing) {
            Button {
                onOpen?()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    stripes
                    details
                }
                .contentShape(shape)
            }
            .buttonStyle(RejillaCardPressReporter(isPressed: $isPressed))
            .disabled(onOpen == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
            .accessibilityHint(onOpen == nil ? "" : "Abre la combinación")
            if let onToggleSave {
                saveButton(onToggleSave)
            }
        }
        .background { shape.fill(dimsLocked ? Theme.containerLow : Theme.card).grayscale(dimsLocked ? 1 : 0) }
        .clipShape(shape)
        // Las luces van FUERA del recorte: `clipShape` se come cualquier sombra dibujada dentro.
        .background { background(shape, glowOpacity: effect.glowOpacity) }
        .overlay(shape.strokeBorder(borderColor, lineWidth: dimsLocked ? 1 / max(displayScale, 1) : 1)
            .allowsHitTesting(false))
        .scaleEffect(effect.scale)
        .opacity(effect.opacity)
        .animation(reduceMotion ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                                : .timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.slowDuration),
                   value: isPressed)
    }

    // MARK: Partes

    /// Franjas de la combinación en pocillo neutro (colores exactos, sin sombra ni filtro).
    private var stripes: some View {
        PaletteRibbon(colors: colors, style: .stripes,
                      height: Sizes.gridStripes - 2 * Spacing.wellPaddingCompact, inWell: false)
            .padding(Spacing.wellPaddingCompact)
            .frame(maxWidth: .infinity)
            .background(Theme.wellFill)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.wellEdge).frame(height: 1 / max(displayScale, 1))
            }
            // Las motas de luz (si la pantalla las usa) no pasan por encima de las franjas.
            .neutralZone()
    }

    /// Marco: nombre, origen del nombre, estado y número. Se desatura si está bloqueada.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name.text)
                .textRole(.cardTitle)
                .foregroundStyle(dimsLocked ? Theme.onSurfaceVariant : Theme.onSurface)
                .lineLimit(isLarge ? 3 : 1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ComboNameKindBadge(kind: name.kind)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(name.kind == .number ? DesignFormat.comboSubtitle(id: comboId, size: colors.count) : name.kindLabel)
                    .textRole(Self.metaRole)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(isLarge ? 2 : 1)
            }
            .padding(.top, 3)
            footer
                .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs + 2)
        .grayscale(dimsLocked ? 1 : 0)
        .background(alignment: .bottomTrailing) { pressAura }
    }

    /// Aura `w-16 h-16 bg-secondary-fixed/20 blur-xl` que aparece al pulsar, en la zona de texto.
    @ViewBuilder private var pressAura: some View {
        if isPressed && !reduceMotion {
            Circle()
                .fill(Color(brand: RejillaLight.peach, opacity: scheme == .dark ? 0.12 : 0.2))
                .frame(width: 64, height: 64)
                .blur(radius: 24)
                .offset(x: 16, y: 16)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var footer: some View {
        if isLarge {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                statusLabel
                numberText
                if onToggleSave != nil { Color.clear.frame(height: Sizes.minTouch - 8) }
            }
        } else {
            HStack(spacing: 2) {
                statusLabel
                Spacer(minLength: 2)
                numberText.fixedSize()
                if onToggleSave != nil {
                    // Hueco para el botón de guardar (se dibuja encima, fuera del área de apertura).
                    Color.clear.frame(width: 26, height: 1)
                }
            }
            .frame(minHeight: 24)
        }
    }

    private var numberText: some View {
        Text(WadaDictionary.numberLabel(comboId))
            .textRole(.labelSM)
            .monospacedDigit()
            .foregroundStyle(Theme.onSurfaceVariant)
            .lineLimit(1)
    }

    @ViewBuilder private var statusLabel: some View {
        switch state {
        case .unlocked(let since):
            Label {
                Text(since).textRole(.labelSM).lineLimit(1)
            } icon: {
                Image(systemName: "checkmark.seal.fill").font(.caption.weight(.semibold))
            }
            .labelStyle(TightLabelStyle())
            .foregroundStyle(Theme.primary)
        case .locked:
            // Píldora de bloqueo: marca el estado sin apagar la tarjeta (la placa gris solo en alto contraste).
            Label {
                Text("Bloqueada").textRole(.labelSM).lineLimit(1)
            } icon: {
                Image(systemName: "lock").font(.caption2.weight(.semibold))
            }
            .labelStyle(TightLabelStyle())
            .foregroundStyle(Theme.onSurfaceVariant)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.containerHigh))
            .fixedSize()
        }
    }

    private func saveButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSaved ? "leaf.fill" : "leaf")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSaved ? Theme.primary : Theme.onSurfaceVariant)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : isSaved)
                .grayscale(isLocked && !isSaved ? 1 : 0)
                .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .padding(.trailing, -4)
        .padding(.bottom, -6)
        .accessibilityLabel(isSaved ? "Guardada en tu jardín" : "Guardar en tu jardín")
        .accessibilityValue(name.text)
        .accessibilityIdentifier("rejilla.save.\(comboId)")
    }

    /// Luces de la tarjeta, por detrás del recorte (`clipShape` se come toda sombra dibujada dentro):
    /// misma forma opaca con E1 sepia, halo tenue permanente (L1 a la mitad) y
    /// `hover:shadow-[0_8px_24px_-4px_rgba(253,147,63,0.2)]` solo mientras se pulsa.
    @ViewBuilder private func background(_ shape: RoundedRectangle, glowOpacity: Double) -> some View {
        if dimsLocked {
            // Alto contraste: sombra neutra, sin halo de color.
            shape.fill(Theme.containerLow).grayscale(1).elevation(.rest, neutral: true)
        } else {
            ZStack {
                shape.fill(Theme.card)
                    .elevation(.rest)
                    .shadow(color: Color(brand: RejillaLight.solarOrange, opacity: glowOpacity), radius: 12, x: 0, y: 8)
                OuterGlow(shape: shape, shadows: [Self.restGlow.inner, Self.restGlow.outer])
            }
        }
    }

    /// Filo ámbar 15 % del halo de tarjeta (`border: 1px solid rgba(234,179,8,.25)` a la mitad);
    /// en oscuro sube un poco para que la tarjeta tenga contorno sobre la tierra oscura.
    private var borderColor: Color {
        if dimsLocked { return Theme.wellEdge }
        return Color(brand: 0xEAB308, opacity: scheme == .dark ? 0.24 : 0.15)
    }

    private var accessibilityText: String {
        var parts = [name.text]
        if name.kind == .proposed { parts.append("nombre propuesto") }
        parts.append(WadaDictionary.numberLabel(comboId))
        parts.append("\(colors.count) colores")
        parts.append(colors.compactMap(\.name).joined(separator: ", "))
        switch state {
        case .unlocked(let since): parts.append("en tu rejilla desde \(since)")
        case .locked: parts.append("bloqueada")
        }
        return parts.joined(separator: ", ")
    }
}

/// Círculo de 16 pt con halo que dice de dónde sale el nombre (en el ejemplo: el autor de la paleta).
struct ComboNameKindBadge: View {
    let kind: ComboName.Kind

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 16

    @Environment(\.colorScheme) private var scheme

    /// Halo `shadow-[0_0_4px_…]` del tono de la insignia (marco, lejos de las franjas).
    static func haloColor(kind: ComboName.Kind, dark: Bool) -> Color {
        let alpha = dark ? 0.35 : 0.6
        switch kind {
        case .curated: return Color(brand: 0xBCEFC7, opacity: dark ? 0.35 : 0.7)
        case .proposed: return Color(brand: 0xFFB785, opacity: alpha)
        case .number: return Color(brand: 0xBDECDC, opacity: alpha)
        }
    }

    var body: some View {
        Circle()
            .fill(tone?.badgeFill ?? Theme.containerHigh)
            .shadow(color: Self.haloColor(kind: kind, dark: scheme == .dark), radius: 2)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size / 2, weight: .bold))
                    .foregroundStyle(tone?.onBadge ?? Theme.onSurfaceVariant)
            }
            .accessibilityHidden(true)
    }

    private var tone: Tone? {
        switch kind {
        case .curated: .moss
        case .proposed: .amber
        case .number: nil
        }
    }

    private var symbol: String {
        switch kind {
        case .curated: "checkmark"
        case .proposed: "lightbulb.fill"
        case .number: "number"
        }
    }
}

/// Casilla compacta (resumen del escaneo del carrete, `WrappedSummaryView`): franjas de la
/// combinación en un pocillo neutro cuadrado; bloqueada = relleno rayado con candado.
struct ComboTile: View {
    let combo: WadaCombo
    let colors: [WadaColor]
    let unlocked: Bool

    var body: some View {
        SwatchWell(padding: Spacing.xs, cornerRadius: Radius.block) {
            GeometryReader { geo in
                PaletteRibbon(colors: colors.enumerated().map { PaletteColor(id: $0.offset, wada: $0.element) },
                              style: .stripes, height: max(geo.size.height, 1), locked: !unlocked, inWell: false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked ? "Combinación \(combo.id), desbloqueada" : "Combinación \(combo.id), bloqueada")
    }
}

/// Estilo de botón que no dibuja nada y publica si está pulsado: la tarjeta entera (con el botón
/// de guardar encima) aplica la escala, la sombra cálida y el aura.
struct RejillaCardPressReporter: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if isPressed != pressed { isPressed = pressed }
            }
    }
}
