// Resultado de Extraer (docs/design/DESIGN_SYSTEM.md §5.2, «Estado de resultado»; ejemplo
// «clothing_extractor»): visor con la foto sin recortar y los alfileres de cada color,
// aviso con los pasos reales del recorte, «Ver máscara», fila de personas y «Ver capas»;
// «Colores de la ropa» con tarjetas de prenda en pocillos neutros y la cinta de pesos; las 3
// combinaciones más parecidas con «Sí, es eso» / «No» y «Desbloquear»; «Guardar en el
// jardín», «Copiar hex», «Ver capas» y «Compartir tarjeta». Todo color de datos va en un
// pocillo (§1.4); el pergamino y los tintes cálidos quedan en el marco. La usan la pestaña
// (ExtractView) y la pantalla empujada (ResultView, p. ej. «Abrir en Extraer» del Feed).
// Orden y densidad del ejemplo (FIDELITY.md §4): visor → 16 pt → título y píldora (4) → tarjetas
// (12) → cinta (20) → «Guardar en el jardín» luminoso (20) → secundarios (8); después, «Se parece a»
// con halo que respira (M2 + L2), «También se parece a», «Compartir tarjeta» y el pie técnico.
import SwiftUI
import UIKit
import SubjectKit

struct ExtractResultContent: View {
    @ObservedObject var model: ResultViewModel
    /// Abre el visor de capas del análisis actual.
    let onOpenLayers: (ScanOutcome) -> Void
    /// Toast del contenedor (se pinta fuera del desplazamiento: `ExtractToastOverlay`).
    @Binding var toast: String?

    @State private var shareImage: UIImage?
    @State private var toastTask: Task<Void, Never>?
    @State private var copiedSwatch: Int?
    @State private var copiedPalette = false
    @State private var comboSheet: ComboSheetItem?
    @State private var feedbackTrigger = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tarjetas de prenda: 2 columnas; 1 con tamaños de accesibilidad (§2.4 regla 3).
    private var grid: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Spacing.gutter), GridItem(.flexible(), spacing: Spacing.gutter)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = model.banner {
                Label(banner, systemImage: "arrow.triangle.2.circlepath")
                    .textRole(.labelMD)
                    .foregroundStyle(Theme.onSecondaryContainer)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(Theme.secondaryContainer))
                    .padding(.bottom, Spacing.md)
                    .accessibilityIdentifier("result.banner")
            }
            ExtractViewfinder(model: model, onOpenLayers: { onOpenLayers(model.outcome) })
            if model.showsPeopleRow, model.verdict != nil {
                Text("Ya has votado este resultado: para usar otra persona, analiza la foto de nuevo.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.top, Spacing.sm)
            }
            // `pb-space-xs` del visor + `mt-space-md` del cajón.
            colorsSection.id("extract.colors")
                .padding(.top, Spacing.xs + Spacing.md)
            actions.id("extract.actions")
                .padding(.top, Spacing.lg)
            matchSection.id("extract.match")
                .padding(.top, Spacing.xl)
            shareButton
                .padding(.top, Spacing.md)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.error)
                    .padding(.top, Spacing.md)
                    .accessibilityIdentifier("result.error")
            }
            Text(model.technicalFooter)
                .textRole(.bodySM)
                .monospacedDigit()
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.top, Spacing.md)
                .accessibilityIdentifier("result.footer")
                .id("extract.footer")
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .sheet(item: $comboSheet) { item in
            ExtractComboSheet(comboId: item.id)
        }
        .task {
            await model.load()
            if shareImage == nil { shareImage = model.makeShareImage() }
        }
        .onChange(of: model.outcome.scan.rev) { _, _ in
            shareImage = model.makeShareImage()
        }
    }

    // MARK: Colores de la ropa

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.paletteTitle)
                        .textRole(.headlineSM)
                        .foregroundStyle(Theme.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "paintpalette")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityHidden(true)
                }
                summaryPill
            }
            LazyVGrid(columns: grid, spacing: Spacing.gutter) {
                ForEach(model.palette) { color in
                    ExtractGarmentCard(index: color.id + 1, color: color, isSelected: model.selectedSwatch == color.id,
                                       isCopied: copiedSwatch == color.id) {
                        flash(model.copy(color))
                        copiedSwatch = color.id
                    }
                    .accessibilityIdentifier("result.garment.\(color.id)")
                }
            }
            .padding(.top, Spacing.md)
            if !model.palette.isEmpty {
                PaletteRibbon(colors: model.palette, style: .weights, height: Sizes.extractRibbon,
                              wellCornerRadius: Radius.card)
                    .padding(.top, Spacing.lg)
                    .accessibilityIdentifier("result.ribbon")
            }
        }
    }

    private var summaryPill: some View {
        let parts = model.paletteSummary.components(separatedBy: " · ")
        let shape = RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? Radius.card : 100, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Circle().fill(Theme.secondaryContainer).frame(width: 8, height: 8).accessibilityHidden(true)
            (Text(parts.first ?? "").foregroundStyle(Theme.onSurface)
                + Text(parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : "")
                    .foregroundStyle(Theme.onSurfaceVariant))
                .textRole(.labelMD)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.chipVertical)
        .background(shape.fill(Theme.container))
        .insetSunGlint(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.paletteSummary")
    }

    // MARK: Combinaciones

    @ViewBuilder private var matchSection: some View {
        let matches = model.matches
        if let top = matches.first, let hit = model.topHit {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ExtractTopMatchCard(model: model, match: top, score: hit.score,
                                    onOpen: { comboSheet = ComboSheetItem(id: top.comboId) },
                                    onVoted: { feedbackTrigger += 1 })
                if matches.count > 1 {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("También se parece a").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
                        ForEach(Array(matches.dropFirst().enumerated()), id: \.element.comboId) { i, match in
                            ExtractMatchRow(rank: i + 2, match: match, score: model.hits[i + 1].score,
                                            isProposedName: model.comboName(match.comboId).isProposed) {
                                comboSheet = ComboSheetItem(id: match.comboId)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .solarCard(fill: Theme.card, elevation: .rest)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Se parece a").textRole(.overline).foregroundStyle(Theme.onSurfaceVariant)
                Text("El motor no ha encontrado ninguna combinación.")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .solarCard()
        }
    }

    // MARK: Acciones

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            ExtractLuminousButton(title: model.isSaved ? "Guardado en el jardín" : "Guardar en el jardín",
                                  icon: .sprout, sparkle: true) {
                flash(model.toggleSave())
            }
            .accessibilityIdentifier("result.save")
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.sm))
                                                  : AnyLayout(HStackLayout(spacing: Spacing.gutter))) {
                ExtractPillButton(title: copiedPalette ? "Copiados" : "Copiar hex", systemImage: "doc.on.doc",
                                  isDone: copiedPalette) {
                    flash(model.copyPalette())
                    copiedPalette = true
                }
                .disabled(model.palette.isEmpty)
                .accessibilityIdentifier("result.copyHex")
                ExtractPillButton(title: "Ver capas", systemImage: "square.3.layers.3d") {
                    onOpenLayers(model.outcome)
                }
                .disabled(model.reanalyzing)
                .accessibilityIdentifier("result.layersButton")
            }
        }
    }

    @ViewBuilder private var shareButton: some View {
        if let image = shareImage {
            ShareLink(item: Image(uiImage: image), preview: SharePreview(model.shareTitle, image: Image(uiImage: image))) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .medium))
                    Text("Compartir tarjeta").textRole(.labelLG).lineLimit(1)
                }
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, minHeight: Sizes.minTouch)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Color(light: 0xC29B38, dark: 0xC29B38, lightOpacity: 0.35, darkOpacity: 0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("result.share")
        } else {
            HStack(spacing: Spacing.sm) {
                ProgressView().tint(Theme.primary)
                Text("Preparando la tarjeta…").textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, minHeight: Sizes.minTouch)
        }
    }

    private func flash(_ text: String) {
        toastTask?.cancel()
        feedbackTrigger += 1
        toast = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ExtractMotion.toastSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) {
                toast = nil
                copiedSwatch = nil
                copiedPalette = false
            }
        }
    }
}

/// Id de la hoja de una combinación.
struct ComboSheetItem: Identifiable, Hashable {
    let id: Int
}

// MARK: - Top-1

/// La combinación más parecida (§5.2 «MatchCard»): tira de Wada en pocillo, nombre, número y
/// score, «Entre A y B», «Sí, es eso» / «No» (un solo voto) y «Desbloquear».
struct ExtractTopMatchCard: View {
    @ObservedObject var model: ResultViewModel
    let match: ComboMatchSummary
    let score: Double
    let onOpen: () -> Void
    var onVoted: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Fila en horizontal; en vertical con tamaños de accesibilidad.
    private func row(spacing: CGFloat) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
                                            : AnyLayout(HStackLayout(spacing: spacing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            (row(spacing: 6)) {
                // Destello que gira (8 s), como la estrella de la adivinación del ejemplo.
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .spinning(duration: MotionSpec.Spin.lensChip)
                    .accessibilityHidden(true)
                Text("Se parece a").textRole(.overline).foregroundStyle(Theme.secondary)
                Spacer(minLength: Spacing.sm)
                SolarBadge(title: WadaDictionary.numberLabel(match.comboId))
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    PaletteRibbon(colors: match.colors, style: .strip, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.name)
                            .textRole(.headlineLGMobile)
                            .foregroundStyle(Theme.onSurface)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("result.top1")
                        HStack(spacing: Spacing.xs) {
                            Text(match.subtitle + (model.comboName(match.comboId).isProposed ? " · nombre propuesto" : ""))
                                .textRole(.bodySM)
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .accessibilityHidden(true)
                        }
                        Text("Score \(DesignFormat.score(score)) (menor es mejor)")
                            .textRole(.bodySM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressScaleWide)
            .accessibilityHint("Abre la combinación en el diccionario")
            .accessibilityIdentifier("result.openCombo")
            if let ambiguity = match.ambiguityText {
                SolarBadge(title: ambiguity, systemImage: "arrow.left.arrow.right",
                           fill: Theme.secondaryFixed, foreground: Theme.onSecondaryFixedVariant)
                    .accessibilityIdentifier("result.ambiguous")
            }
            Rectangle().fill(Theme.outlineVariant.opacity(0.5)).frame(height: 1).accessibilityHidden(true)
            voteRow
            unlockRow
        }
        // ≥ 16 pt entre la tira (pocillo) y el borde con halo (FIDELITY §0.2).
        .padding(Spacing.margin)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
        // Halo que respira ámbar ↔ verde azulado con borde que cambia de color (M2 + L2, 4 s), solo por fuera.
        .glowPulse(cornerRadius: Radius.card)
        .accessibilityIdentifier("result.topCard")
    }

    private var voteRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("¿Es esta la combinación?").textRole(.labelLG).foregroundStyle(Theme.onSurface)
            (row(spacing: Spacing.sm)) {
                voteButton(.yes, title: model.verdict == .yes ? "Es eso" : "Sí, es eso",
                           icon: model.verdict == .yes ? "heart.fill" : "heart", id: "result.yes")
                voteButton(.no, title: "No", icon: model.verdict == .no ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                           id: "result.no")
            }
            if let verdict = model.verdict {
                Label(verdict == .yes ? "Gracias. Marcado como acierto." : "Gracias. Marcado como fallo; nos sirve para mejorar el motor.",
                      systemImage: "checkmark.circle.fill")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("result.thanks")
            }
        }
    }

    private func voteButton(_ verdict: FeedbackVerdict, title: String, icon: String, id: String) -> some View {
        let chosen = model.verdict == verdict
        let enabled = model.verdict == nil && !model.busy && !model.reanalyzing
        return Button {
            Task {
                await model.vote(verdict)
                if model.verdict == verdict { onVoted() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(verdict == .yes && chosen ? Theme.secondary : Theme.primary)
                Text(title).textRole(.labelMD).foregroundStyle(chosen ? Theme.onPrimaryFixed : Theme.primary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Sizes.minTouch)
            .background(Capsule().fill(chosen ? (verdict == .yes ? Theme.primaryFixed : Theme.secondaryFixed) : Theme.container))
            .opacity(enabled || chosen ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
        .disabled(!enabled)
        .accessibilityLabel(verdict == .yes ? "Sí, es eso" : "No, no es eso")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var unlockRow: some View {
        switch model.unlockState {
        case .unknown, .locked:
            (row(spacing: Spacing.sm)) {
                Label("Todavía no está en tu rejilla", systemImage: "lock")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Spacing.sm) }
                SolarPrimaryButton(title: "Desbloquear", systemImage: "lock.open", size: .compact, fullWidth: false,
                                   elevated: false) {
                    Task { await model.unlock() }
                }
                .disabled(model.topHit == nil || model.busy || model.unlockState == .unknown)
                .accessibilityIdentifier("result.unlock")
            }
        case .unlockedNow:
            Label("Desbloqueada: ya está en tu rejilla.", systemImage: "checkmark.seal.fill")
                .textRole(.labelMD)
                .foregroundStyle(Theme.primary)
                .accessibilityIdentifier("result.unlocked")
        case .alreadyUnlocked:
            Label("Ya en tu rejilla.", systemImage: "checkmark.seal")
                .textRole(.labelMD)
                .foregroundStyle(Theme.primary)
                .accessibilityIdentifier("result.already")
        }
    }
}

// MARK: - Top-2 y top-3

struct ExtractMatchRow: View {
    let rank: Int
    let match: ComboMatchSummary
    let score: Double
    var isProposedName = false
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        Button(action: onOpen) {
            (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm)) : AnyLayout(HStackLayout(spacing: Spacing.md))) {
                PaletteRibbon(colors: match.colors, style: .strip, height: 28)
                    .frame(width: ax ? nil : 104)
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.name)
                        .textRole(.cardTitle)
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(ax ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Text("\(match.subtitle) · score \(DesignFormat.score(score))")
                        .textRole(.bodySM)
                        .monospacedDigit()
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(ax ? nil : 1)
                        .minimumScaleFactor(0.85)
                }
                if !ax { Spacer(minLength: 0) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Sizes.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScaleWide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank)º: \(match.name), \(match.subtitle), score \(DesignFormat.score(score))")
        .accessibilityIdentifier("result.match.\(rank)")
    }
}

// MARK: - Hoja de combinación

/// Detalle de una combinación en hoja (el de la Rejilla/diccionario).
struct ExtractComboSheet: View {
    let comboId: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ComboDetailView(comboId: comboId)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.sheet)
    }
}
