// Pantalla Resultado (PLAN §7.3): foto, paleta con pesos, top-1 grande
// (nombre curado o "Nº 012", tamaño/colección, swatches), top-2 y top-3,
// "Entre A y B" si es ambiguo, "Sí, es eso" / "No", "Desbloquear" y
// "Compartir tarjeta" (ShareLink con la tarjeta de 1080 x 1350).
import SwiftUI
import UIKit

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
                if let note = model.outcome.maskNote {
                    Label(note, systemImage: model.outcome.maskApplied ? "person.crop.rectangle" : "person.crop.rectangle.badge.xmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                Text("Motor \(model.outcome.scan.engineVersion) · diccionario \(model.outcome.scan.dictVersion) · \(model.outcome.elapsedMs) ms")
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
    }

    private var photo: some View {
        Image(decorative: model.outcome.image, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("result.photo")
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
            .disabled(model.verdict != nil || model.busy)
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
