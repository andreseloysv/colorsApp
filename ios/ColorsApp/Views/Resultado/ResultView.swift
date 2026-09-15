// Pantalla Resultado (PLAN §7.3): foto (con "Ver máscara"), aviso con los pasos
// del recorte de sujeto, fila "Personas" si hay dos o más (miniaturas y "Todas";
// tocar una re-analiza sin volver a ejecutar Vision), "Ver capas" (inspector de
// las 11 capas del análisis), paleta con pesos, top-1 grande (nombre curado o
// "Nº 012", tamaño/colección, swatches), top-2 y top-3, "Entre A y B" si es
// ambiguo, "Sí, es eso" / "No", "Desbloquear" y "Compartir tarjeta" (ShareLink
// con la tarjeta de 1080 x 1350).
import SwiftUI
import UIKit
import SubjectKit

struct ResultView: View {
    @StateObject private var model: ResultViewModel
    @State private var shareImage: UIImage?

    init(model: ResultViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photo
                subjectSection
                if model.showsPeopleRow {
                    peopleSection
                }
                paletteSection
                topSection
                feedbackSection
                unlockSection
                shareSection
                if !model.otherHits.isEmpty {
                    othersSection
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("result.error")
                }
                Text(String(format: "Motor %@ · diccionario %@ · %d ms (Vision %.0f · máscara %.0f · motor %.0f)",
                            model.outcome.scan.engineVersion, model.outcome.scan.dictVersion, model.outcome.elapsedMs,
                            model.outcome.timings.visionMs, model.outcome.timings.maskMs, model.outcome.timings.engineMs))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if shareImage == nil {
                shareImage = model.makeShareImage()
            }
        }
        .onChange(of: model.outcome.scan.rev) { _, _ in
            shareImage = model.makeShareImage()
        }
    }

    private var photo: some View {
        Image(decorative: model.outcome.image, scale: 1)
            .resizable()
            .scaledToFit()
            .overlay {
                if model.showMask, let overlay = model.maskOverlay {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .accessibilityIdentifier("result.maskOverlay")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                if model.reanalyzing {
                    ProgressView()
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                        .padding(8)
                }
            }
            .accessibilityIdentifier("result.photo")
    }

    /// Aviso con los pasos aplicados y los botones "Ver máscara" / "Ver capas".
    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let notice = model.maskNotice
            Label(notice.text, systemImage: notice.systemImage)
                .font(.footnote)
                .foregroundStyle(notice.isFallback ? Color.orange : Color.secondary)
                .accessibilityIdentifier("result.subjectNotice")
            HStack(spacing: 12) {
                Button {
                    model.showMask.toggle()
                } label: {
                    Label(model.showMask ? "Ocultar máscara" : "Ver máscara",
                          systemImage: model.showMask ? "eye.slash" : "theatermask.and.paintbrush")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.maskOverlay == nil)
                .accessibilityIdentifier("result.showMask")
                NavigationLink(value: LayersRoute(outcome: model.outcome)) {
                    Label("Ver capas", systemImage: "square.3.layers.3d")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.reanalyzing)
                .accessibilityIdentifier("result.layers")
            }
            .font(.subheadline)
        }
    }

    /// Fila "Personas": miniatura de cada persona (bbox de su instancia) y "Todas".
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personas")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.personThumbnails.enumerated()), id: \.offset) { index, thumb in
                        personButton(.person(index)) {
                            Image(decorative: thumb, scale: 1)
                                .resizable()
                                .scaledToFill()
                        } caption: {
                            index == 0 ? "1 · principal" : "\(index + 1)"
                        }
                    }
                    personButton(.all) {
                        ZStack {
                            Color(.secondarySystemBackground)
                            Image(systemName: "person.3.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    } caption: {
                        "Todas"
                    }
                }
                .padding(.vertical, 2)
            }
            if model.verdict != nil {
                Text("Ya has votado este resultado: para usar otra persona, analiza la foto de nuevo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("result.people")
    }

    private func personButton<Content: View>(_ choice: ResultViewModel.PersonChoice,
                                             @ViewBuilder content: () -> Content,
                                             caption: () -> String) -> some View {
        let selected = model.currentChoice == choice
        let label = caption()
        return Button {
            Task { await model.choose(choice) }
        } label: {
            VStack(spacing: 4) {
                content()
                    .frame(width: 64, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.canChangePerson && !selected)
        .accessibilityIdentifier({
            switch choice {
            case .all: return "result.person.all"
            case .person(let i): return "result.person.\(i)"
            }
        }())
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paleta de la foto")
                .font(.headline)
            PaletteBars(entries: PaletteBars.entries(from: model.outcome.result.swatches))
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Combinación más parecida")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let combo = model.top1Combo, let hit = model.topHit {
                SwatchStrip(colors: model.dictionary.colors(of: combo).map { Color(wada: $0) }, height: 96, cornerRadius: 12)
                Text(model.dictionary.displayName(id: combo.id))
                    .font(.title.bold())
                    .accessibilityIdentifier("result.top1")
                Text(model.comboHeadline(combo))
                    .foregroundStyle(.secondary)
                Text(String(format: "Score %.2f (menor es mejor)", hit.score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if let ambiguity = model.ambiguityText {
                    Label(ambiguity, systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("result.ambiguous")
                }
                NavigationLink(value: combo.id) {
                    Label("Ver en el diccionario", systemImage: "book")
                }
                .font(.subheadline)
            } else {
                Text("El motor no ha encontrado ninguna combinación.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var othersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("También se parece a")
                .font(.headline)
            ForEach(model.otherHits, id: \.comboId) { hit in
                if let combo = model.dictionary.combo(id: hit.comboId) {
                    NavigationLink(value: combo.id) {
                        ComboRow(combo: combo, trailing: String(format: "%.2f", hit.score))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("¿Es esta la combinación?")
                .font(.headline)
            if let verdict = model.verdict {
                Label(verdict == .yes ? "Gracias. Marcado como acierto." : "Gracias. Marcado como fallo; nos sirve para mejorar el motor.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("result.thanks")
            }
            HStack(spacing: 12) {
                Button {
                    Task { await model.vote(.yes) }
                } label: {
                    Label("Sí, es eso", systemImage: "hand.thumbsup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("result.yes")
                Button {
                    Task { await model.vote(.no) }
                } label: {
                    Label("No", systemImage: "hand.thumbsdown")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("result.no")
            }
            .disabled(model.verdict != nil || model.busy || model.reanalyzing)
        }
    }

    @ViewBuilder
    private var unlockSection: some View {
        switch model.unlockState {
        case .unknown, .locked:
            Button {
                Task { await model.unlock() }
            } label: {
                Label("Desbloquear", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.topHit == nil || model.busy || model.unlockState == .unknown)
            .accessibilityIdentifier("result.unlock")
        case .unlockedNow:
            Label("Desbloqueada: ya está en tu rejilla.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("result.unlocked")
        case .alreadyUnlocked:
            Label("Ya en tu rejilla.", systemImage: "checkmark.seal")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("result.already")
        }
    }

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = shareImage {
                HStack(alignment: .top, spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tarjeta 1080 × 1350")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview(model.shareTitle, image: Image(uiImage: image))) {
                            Label("Compartir tarjeta", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("result.share")
                    }
                }
            } else {
                ProgressView("Preparando la tarjeta…")
            }
        }
    }
}
