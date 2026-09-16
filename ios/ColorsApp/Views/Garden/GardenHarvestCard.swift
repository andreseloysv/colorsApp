// Cosechas del Jardín (FIDELITY.md §6, G21–G29) con las tres tarjetas del ejemplo
// my_garden_vault…/code.html, cada una con datos reales de un análisis:
//   .droplets      la más reciente: miniatura con anillo e insignia «✦», veredicto con halo,
//                  gotas que llenan el ancho con su hex (dominante marcada con anillo neutro),
//                  y la hoja «Dominante» con destello al tocar una gota y «Copiar».
//   .strip         tira de proporciones de 32 pt, etiquetas y botón «Nº 012» (abre la combinación;
//                  sustituye a «:root CSS», que no existe en la app) y menú de acciones.
//   .distribution  «Distribución de la ropa» con porcentajes, barra de 16 pt, micro-píldoras y hoja
//                  para guardar en la posición de la estrella.
// Zona neutra (DESIGN_SYSTEM.md §1.4): gotas, tiras y barras van en `SwatchWell`, planas, sin halo,
// tinte, sombra ni degradado; los halos y el rayo de sol viven fuera del pocillo (≥ 16 pt).
import SwiftUI

struct GardenHarvestCard: View {
    enum Variant: Sendable, Equatable {
        case droplets, strip, distribution

        /// Alterna las variantes del ejemplo: 1.ª gotas, luego tira y distribución.
        static func forIndex(_ index: Int) -> Variant {
            if index == 0 { return .droplets }
            return index % 2 == 1 ? .strip : .distribution
        }
    }

    let thumbnail: Image?
    let title: String
    /// «hoy, 21:07».
    let date: String
    /// «Carrete» (+ «· Ejemplo»), en `secondary` medium como «Natural Daylight».
    let origin: String
    var verdict: Verdict?
    let palette: [PaletteColor]
    var variant: Variant = .droplets
    /// «Nº 012» si hay combinación.
    var comboLabel: String?
    var ambiguous = false
    /// La cosecha más reciente lleva la insignia «✦» en la miniatura.
    var isLatest = false
    var isSaved = false
    var isCopied = false
    var onCopyColor: ((PaletteColor) -> Void)?
    var onCopyAll: (() -> Void)?
    var onOpenCombo: (() -> Void)?
    var onToggleSave: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            switch variant {
            case .droplets: dropletsBody
            case .strip: stripBody
            case .distribution: distributionBody
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Theme.card).gardenShadow(GardenShadow.harvest)
                if variant == .droplets {
                    // Rayo de sol `-right-6 -bottom-6 w-24 h-24 bg-secondary-fixed/30 blur-xl`: arriba a la
                    // derecha, detrás del veredicto (abajo tocaría el pocillo de gotas).
                    GeometryReader { geo in
                        Circle().fill(Color(light: 0xFFDCC6, dark: 0x713700, lightOpacity: 0.3, darkOpacity: 0.3))
                            .frame(width: 96, height: 96)
                            .blur(radius: 24)
                            .position(x: geo.size.width + 24 - 48, y: -16)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                thumb
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .textRole(.headlineSM)
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    (Text(date + " · ").foregroundStyle(Theme.onSurfaceVariant)
                        + Text(origin).fontWeight(.medium).foregroundStyle(Theme.secondary))
                        .textRole(.bodySM)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Spacing.xs)
            trailing
        }
    }

    /// `img.w-12.h-12.rounded-lg.object-cover.shadow-sm.ring-1.ring-primary/20` + insignia `-top-1 -left-1` «✦».
    private var thumb: some View {
        let r = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return Group {
            if let thumbnail {
                thumbnail.resizable().scaledToFill()
            } else {
                Theme.containerLow.overlay {
                    Image(systemName: "photo").foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
        .frame(width: Sizes.harvestThumb, height: Sizes.harvestThumb)
        .clipShape(r)
        .background { r.fill(Theme.card).gardenShadow(GardenShadow.sm) }
        .overlay {
            if variant == .droplets {
                r.strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1).padding(-1)
            }
        }
        .overlay(alignment: .topLeading) {
            if isLatest {
                GardenSparkBadge(diameter: 14, glyph: 7).offset(x: -4, y: -4)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var trailing: some View {
        switch variant {
        case .droplets:
            VStack(alignment: .trailing, spacing: 2) {
                GardenVerdictPill(verdict: verdict, glows: true)
                saveButton(size: 17)
            }
        case .strip:
            actionsMenu
        case .distribution:
            saveButton(size: 20)
        }
    }

    private func saveButton(size: CGFloat) -> some View {
        Button {
            onToggleSave?()
        } label: {
            Image(systemName: isSaved ? "leaf.fill" : "leaf")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isSaved ? Theme.primary : Theme.secondary)
                .symbolEffect(.bounce, value: reduceMotion ? false : isSaved)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(isSaved ? "Guardada: quitar del jardín" : "Guardar en tu jardín")
        .accessibilityIdentifier("jardin.harvest.save")
    }

    /// `button.w-8.h-8.rounded-full.bg-surface-container … more_vert` con las acciones reales de la cosecha.
    private var actionsMenu: some View {
        Menu {
            if let onCopyAll {
                Button(action: onCopyAll) { Label("Copiar hex de la paleta", systemImage: "doc.on.doc") }
            }
            if let onOpenCombo, let comboLabel {
                Button(action: onOpenCombo) { Label("Ver combinación \(comboLabel)", systemImage: "square.grid.2x2") }
            }
            if let onToggleSave {
                Button(action: onToggleSave) {
                    Label(isSaved ? "Quitar del Jardín" : "Guardar en el Jardín", systemImage: isSaved ? "leaf.fill" : "leaf")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .rotationEffect(.degrees(90))
                .foregroundStyle(Theme.onSurfaceVariant)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.container))
                .overlay(alignment: .bottomTrailing) {
                    if isSaved {
                        Image(systemName: "leaf.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.primary)
                            .offset(x: 2, y: 2)
                    }
                }
                .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                .contentShape(Rectangle())
        }
        .padding(-6)
        .accessibilityLabel(isSaved ? "Acciones de la cosecha (guardada)" : "Acciones de la cosecha")
        .accessibilityIdentifier("jardin.harvest.menu")
    }

    // MARK: Gotas

    /// `div.pt-1.flex.items-center.justify-between.gap-1.5` > gota `w-full aspect-square rounded-full` + hex.
    private var dropletsBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SwatchWell(padding: Spacing.sm, cornerRadius: Radius.block) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(palette.enumerated()), id: \.offset) { i, c in
                        droplet(c, index: i)
                    }
                }
            }
            if let dominant = palette.first {
                dominantSheet(dominant)
            }
        }
    }

    private func droplet(_ c: PaletteColor, index: Int) -> some View {
        let isDominant = index == 0
        return Button {
            onCopyColor?(c)
            flashSheet()
        } label: {
            VStack(spacing: Spacing.xs) {
                Circle()
                    .fill(c.color)
                    .overlay(SwatchHairline(shape: Circle()))
                    .padding(3)
                    // Dominante: anillo neutro del pocillo (el `ring-secondary/30` del ejemplo tintaría el borde).
                    .overlay { if isDominant { Circle().strokeBorder(Theme.wellText, lineWidth: 1.5) } }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 68)
                Text(c.hex)
                    .textRole(.hex, weight: isDominant ? .semibold : nil)
                    .foregroundStyle(isDominant ? Theme.wellText : Theme.wellTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressLift(scale: MotionSpec.Press.scale, lift: 0))
        .accessibilityLabel(DesignFormat.accessibilityLabel(c, position: index, total: palette.count))
        .accessibilityHint("Copia el hex")
    }

    /// `div#hex-sheet-1.p-space-sm.bg-surface-container-low.rounded-lg.flex.justify-between.border.border-primary-fixed/20
    /// .shadow-sm` + `flare` 16 px `text-secondary` + «Dominant: …» + «Copy»; al tocar una gota, `bg-secondary-fixed/50` 400 ms.
    private func dominantSheet(_ dominant: PaletteColor) -> some View {
        let r = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: "sun.max")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text(GardenText.dominantLine(dominant))
                .textRole(.labelMD)
                .foregroundStyle(Theme.onSurface)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Spacer(minLength: Spacing.xs)
            if let onCopyColor {
                Button {
                    onCopyColor(dominant)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(isCopied ? "Copiado" : "Copiar").textRole(.labelSM)
                    }
                    .foregroundStyle(Theme.primary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Copiar hex dominante \(dominant.hex)")
                .accessibilityIdentifier("jardin.harvest.copyDominant")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background {
            ZStack {
                r.fill(Theme.containerLow).gardenShadow(GardenShadow.sm)
                r.fill(Color(light: 0xFFDCC6, dark: 0x713700, lightOpacity: 0.5, darkOpacity: 0.5)).opacity(flash ? 1 : 0)
            }
        }
        .overlay(r.strokeBorder(Color(light: 0xBCEFC7, dark: 0xBCEFC7, lightOpacity: 0.2, darkOpacity: 0.12), lineWidth: 1))
    }

    private func flashSheet() {
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.duration)) { flash = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.slowDuration)) { flash = false }
        }
    }

    // MARK: Tira

    /// Tira `div.w-full.h-8.rounded-lg.overflow-hidden.flex` (proporcional al peso real) + etiquetas y botón.
    private var stripBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SwatchWell(padding: 6, cornerRadius: Radius.block + 4) {
                GardenWeightStrip(colors: palette, height: Sizes.harvestStrip, cornerRadius: Radius.block)
            }
            HStack(spacing: 6) {
                GardenVerdictPill(verdict: verdict, glows: false)
                if ambiguous {
                    GardenTag(title: "Ambigua", fill: Theme.secondaryFixed, foreground: Theme.onSecondaryFixedVariant)
                }
                Spacer(minLength: Spacing.xs)
                if let comboLabel, let onOpenCombo {
                    // `button.flex.items-center.gap-1.px-2.5.py-1.rounded-full.bg-primary-container.text-on-primary
                    // .font-label-sm.shadow-sm.active:scale-95` (en el ejemplo «:root CSS»).
                    Button(action: onOpenCombo) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(comboLabel).textRole(.labelSM).monospacedDigit()
                        }
                        .foregroundStyle(Color(light: 0xFFFFFF, dark: 0xBCEFC7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Theme.primaryContainer).gardenShadow(GardenShadow.sm) }
                        .frame(minHeight: 32)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel("Ver combinación \(comboLabel)")
                    .accessibilityIdentifier("jardin.harvest.combo")
                }
            }
        }
    }

    // MARK: Distribución

    private var distributionBody: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Distribución de la ropa")
                    .textRole(GardenType.micro)
                    .foregroundStyle(Theme.onSurfaceVariant)
                Spacer(minLength: Spacing.xs)
                Text(GardenText.distribution(palette))
                    .textRole(GardenType.micro)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SwatchWell(padding: 6, cornerRadius: 14) {
                GardenWeightStrip(colors: palette, height: Sizes.weightBar, cornerRadius: Sizes.weightBar / 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    GardenVerdictPill(verdict: verdict, glows: false)
                    ForEach(palette.prefix(3)) { c in MicroColorPill(color: c, showsHex: false) }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, Spacing.xs)
        }
    }
}

// MARK: - Piezas

/// Tira proporcional al peso con esquinas redondeadas, segmentos planos y filo de swatch.
struct GardenWeightStrip: View {
    let colors: [PaletteColor]
    var height: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let total = max(colors.reduce(0) { $0 + max(0, $1.weight ?? 0) }, .leastNonzeroMagnitude)
        let equal = colors.allSatisfy { ($0.weight ?? 0) <= 0 }
        GeometryReader { geo in
            let available = max(0, geo.size.width - Spacing.swatchDivider * CGFloat(max(colors.count - 1, 0)))
            HStack(spacing: Spacing.swatchDivider) {
                ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                    let fraction = equal ? 1 / CGFloat(max(colors.count, 1)) : CGFloat(max(0, c.weight ?? 0) / total)
                    Rectangle()
                        .fill(c.color)
                        .overlay(SwatchHairline(shape: Rectangle()))
                        .frame(width: max(1, available * fraction))
                        .accessibilityElement()
                        .accessibilityLabel(DesignFormat.accessibilityLabel(c, position: i, total: colors.count))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Etiqueta `span.px-2.py-0.5.rounded-full.font-label-sm`.
struct GardenTag: View {
    let title: String
    var fill: Color = Theme.container
    var foreground: Color = Theme.primary

    var body: some View {
        Text(title)
            .textRole(.labelSM)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}

/// Veredicto como la píldora «Synced» del ejemplo: `inline-flex gap-1 px-2.5 py-0.5 rounded-full bg-primary-fixed
/// text-on-primary-fixed font-label-sm shadow-[0_0_8px_rgba(188,239,199,0.5)]` + `verified` 13 px.
struct GardenVerdictPill: View {
    let verdict: Verdict?
    /// Halo del tono (solo en la cabecera de la cosecha, lejos del pocillo).
    var glows = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            }
            Text(title).textRole(.labelSM).lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(Capsule().fill(fill))
        .background {
            if glows, let halo {
                OuterGlow(shape: Capsule(), shadows: [halo])
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch verdict {
        case .yes: "Sí, es eso"
        case .no: "No"
        case nil: "Sin votar"
        }
    }

    private var icon: String? {
        switch verdict {
        case .yes: "checkmark.seal.fill"
        case .no: "hand.thumbsdown.fill"
        case nil: nil
        }
    }

    private var fill: Color {
        switch verdict {
        case .yes: Theme.primaryFixed
        case .no: Theme.secondaryFixed
        case nil: Theme.containerHigh
        }
    }

    private var foreground: Color {
        switch verdict {
        case .yes: Theme.onPrimaryFixed
        case .no: Theme.onSecondaryFixed
        case nil: Theme.onSurfaceVariant
        }
    }

    private var halo: ShadowSpec? {
        switch verdict {
        case .yes: ShadowSpec(TailwindColor.primaryFixed.opacity(0.5), blur: 8)
        case .no: ShadowSpec(MotionRGBA(hex: 0xFFDCC6, alpha: 0.6), blur: 8)
        case nil: nil
        }
    }
}
