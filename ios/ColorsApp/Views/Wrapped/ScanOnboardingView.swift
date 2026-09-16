// Escaneo del carrete (día 0) como flujo presentable, con el estilo del sistema de diseño:
// explicación -> progreso -> resumen «Tu carrete en color». Con acceso limitado a Fotos
// ofrece PhotosPicker (hasta 200 fotos) y las procesa por la misma ruta; con acceso
// denegado, mensaje y enlace a Ajustes del sistema (URL del sistema, sin red).
// La presentan el Feed la primera vez (sin `initial_scan_done` ni `scan_onboarding_skipped`
// en settings, con «Ahora no» para saltarla), Extraer, la Rejilla y el Jardín.
// Marco solarpunk de las pantallas secundarias (FIDELITY.md §7.5): cabecera esmerilada con el
// logotipo ChromaSol y el aspa de cerrar, motas de luz y halo en las tarjetas.
import SwiftUI
import PhotosUI
import UIKit

struct ScanOnboardingView: View {
    enum Stage: Equatable {
        case intro
        case running
        case limited
        case denied
        case done(ScanSummary)
        case failed(String)
    }

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    /// Fotos del carrete a analizar (PLAN §7.6: 200).
    var limit: Int = 200
    /// Acción del botón «Ver rejilla» del resumen (cambia de pestaña o cierra la hoja).
    var onShowGrid: (() -> Void)? = nil
    /// Arranca el escaneo al aparecer (sin pantalla de introducción).
    var autoStart: Bool = false
    /// «Ahora no» en la introducción (primera vez); nil = sin ese botón.
    var onSkip: (() -> Void)? = nil

    @State private var stage: Stage = .intro
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .intro: intro
                case .running: running
                case .limited: limited
                case .denied: denied
                case .done(let summary):
                    WrappedSummaryView(summary: summary, dictionary: env.dictionary, totalCombos: env.comboCount,
                                       onShowGrid: onShowGrid ?? { dismiss() })
                case .failed(let message): failed(message)
                }
            }
            .secondaryAmbience()
            .safeAreaInset(edge: .top, spacing: 0) {
                // Cabecera de marca de las pantallas secundarias (FIDELITY.md §7.5): el aspa cierra
                // la hoja y cancela el escaneo en curso (antes «Cerrar»/«Cancelar» de la barra del sistema).
                SecondaryHeader(section: stage == .running ? "Escaneando" : "Carrete",
                                leading: .close,
                                onLeading: {
                                    scanTask?.cancel()
                                    dismiss()
                                },
                                identifier: "scan.header",
                                leadingIdentifier: "scan.close")
            }
            .navigationTitle(stage == .intro ? "Escanear carrete" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.primary)
        .onAppear {
            if autoStart, stage == .intro { start() }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            startPicker(items)
        }
    }

    // MARK: Etapas

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        ChromaSolLogo(size: 56, animated: true)
                        Spacer(minLength: Spacing.sm)
                        StageBadge(systemImage: "photo.stack", tone: .amber, size: 44)
                    }
                    Text("Tus últimas \(limit) fotos, en color")
                        .textRole(.headlineXLMobile)
                        .foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(AppBrand.name) analiza en el propio teléfono las últimas \(limit) fotos del carrete y busca en la ropa de cada una la combinación de Sanzo Wada más parecida. Ninguna foto sale del dispositivo; solo se guardan los colores.")
                        .textRole(.bodyLG)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Spacing.sm) {
                        SolarBadge(title: "Sin red", systemImage: "wifi.slash", fill: Theme.primaryFixed, foreground: Theme.onPrimaryFixed)
                        SolarBadge(title: "Sin cuenta", systemImage: "person.crop.circle.badge.xmark", fill: Theme.secondaryFixed,
                                   foreground: Theme.onSecondaryFixed)
                        SolarBadge(title: "En el teléfono", systemImage: "iphone", fill: Theme.tertiaryFixed, foreground: Theme.onTertiaryFixed)
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                        SolarWash(kind: .warm, diameter: 160, blur: 42).offset(x: 60, y: -70)
                        SolarWash(kind: .green, diameter: 130, blur: 34).offset(x: -200, y: 120)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .elevation(.restStrong)
                }
                .glowCard(cornerRadius: Radius.card)
                .sunGlint(cornerRadius: Radius.card)
                SolarPrimaryButton(title: "Escanear ahora", systemImage: "sparkles", luminous: true) {
                    start()
                }
                .accessibilityIdentifier("scan.start")
                if let onSkip {
                    GhostButton(title: "Ahora no") {
                        onSkip()
                    }
                    .accessibilityIdentifier("scan.skip")
                    Text("Puedes hacerlo más tarde desde Extraer, la Rejilla o tu Jardín.")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var running: some View {
        let p = env.scanProgress
        return VStack(spacing: Spacing.lg) {
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    StageBadge(systemImage: "photo.stack", tone: .moss, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Escaneando el carrete").textRole(.overline).foregroundStyle(Theme.secondary)
                        Text(phaseText(p))
                            .textRole(.headlineSM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.onSurface)
                            .accessibilityIdentifier("scan.progress")
                    }
                }
                ProgressView(value: p.total > 0 ? p.fraction : nil)
                    .progressViewStyle(.linear)
                    .tint(Theme.primary)
                HStack(spacing: Spacing.md) {
                    if let startedAt = p.startedAt {
                        Label {
                            Text(startedAt, style: .timer).textRole(.labelMD).monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .foregroundStyle(Theme.onSurfaceVariant)
                    }
                    if p.unlocked > 0 {
                        Label {
                            Text(p.unlocked == 1 ? "1 combinación desbloqueada" : "\(p.unlocked) combinaciones desbloqueadas")
                                .textRole(.labelMD)
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        .foregroundStyle(Theme.primary)
                    }
                }
                if p.skipped > 0 {
                    Text("\(p.skipped) omitidas (solo en iCloud o no legibles)")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
                Text("Todo ocurre en el teléfono: puedes seguir usando la app.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .solarCard(fill: Theme.container, elevation: .restStrong)
            .glowPulse(cornerRadius: Radius.card)
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
    }

    private func phaseText(_ p: ScanProgress) -> String {
        switch p.phase {
        case .idle: "Preparando…"
        case .requestingAccess: "Pidiendo acceso a Fotos…"
        case .fetching: "Buscando las últimas fotos…"
        case .analyzing: "Analizando \(p.processed)/\(p.total)"
        case .finished: "Listo"
        case .failed: "Error"
        }
    }

    private var limited: some View {
        stageCard(systemImage: "photo.badge.checkmark", tone: .amber, title: "Acceso limitado a Fotos",
                  message: "Solo podemos ver las fotos que elijas. Selecciona hasta \(limit) y las analizamos igual, en el propio teléfono.") {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: limit, matching: .images, photoLibrary: .shared()) {
                PickerButtonLabel(title: "Elegir fotos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.solarPress)
            .accessibilityIdentifier("scan.picker")
        }
    }

    private var denied: some View {
        stageCard(systemImage: "photo.badge.exclamationmark", tone: .amber, title: "Sin acceso a Fotos",
                  message: "Para escanear el carrete, permite el acceso a Fotos en Ajustes > ColorsApp. Las fotos se analizan solo en el teléfono.") {
            SolarPrimaryButton(title: "Abrir Ajustes", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .accessibilityIdentifier("scan.openSettings")
            GhostButton(title: "Reintentar", systemImage: "arrow.clockwise") { start() }
        }
    }

    private func failed(_ message: String) -> some View {
        stageCard(systemImage: "exclamationmark.triangle", tone: .amber, title: "El escaneo no ha terminado",
                  message: message, monospacedMessage: true) {
            SolarPrimaryButton(title: "Reintentar", systemImage: "arrow.clockwise") { start() }
        }
    }

    private func stageCard<Actions: View>(systemImage: String, tone: Tone, title: String, message: String,
                                          monospacedMessage: Bool = false,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    StageBadge(systemImage: systemImage, tone: tone)
                    Text(title).textRole(.headlineMD).foregroundStyle(Theme.primary)
                    Text(message)
                        .textRole(monospacedMessage ? .hex : .bodyLG)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .solarCard(elevation: .rest)
                .glowCard(cornerRadius: Radius.card)
                actions()
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Acciones

    private func start() {
        stage = .running
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            env.installPhotoKitScanRunner()
            do {
                let summary = try await env.runInitialScan(limit: limit)
                stage = summary.needsPicker ? .limited : .done(summary)
            } catch ScanError.accessDenied {
                stage = .denied
            } catch ScanError.cancelled {
                stage = .intro
            } catch {
                stage = .failed(String(describing: error))
            }
        }
    }

    private func startPicker(_ items: [PhotosPickerItem]) {
        stage = .running
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            let runner = env.installPhotoKitScanRunner()
            do {
                let summary = try await runner.scan(pickerItems: items)
                pickerItems = []
                stage = .done(summary)
            } catch ScanError.cancelled {
                stage = .limited
            } catch {
                stage = .failed(String(describing: error))
            }
        }
    }
}

/// Etiqueta en cápsula musgo para el botón de PhotosPicker (su cierre no está aislado al MainActor).
struct PickerButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
            Text(title).textRole(.labelLG)
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.vertical, Spacing.ctaVertical)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Capsule().fill(Theme.primary))
        .contentShape(Capsule())
    }
}

/// Insignia circular de una etapa del escaneo (icono de tono sobre su relleno).
struct StageBadge: View {
    let systemImage: String
    var tone: Tone = .moss
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(tone.badgeFill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tone.onBadge)
            }
            .accessibilityHidden(true)
    }
}
