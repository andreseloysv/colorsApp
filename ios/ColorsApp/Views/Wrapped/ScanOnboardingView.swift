// Escaneo del carrete (día 0) como flujo presentable: explicación -> progreso
// -> resumen Wrapped. Con acceso limitado a Fotos ofrece PhotosPicker (hasta
// 200 fotos) y las procesa por la misma ruta; con acceso denegado, mensaje y
// enlace a Ajustes del sistema (URL del sistema, sin red).
// Hoy la presenta la primera vez (sin `initial_scan_done` ni
// `scan_onboarding_skipped` en settings) con "Ahora no" para saltarla y la ofrece
// después con "Escanear carrete"; Rejilla la enlaza con "Escanear carrete".
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
    /// Acción del botón "Ver rejilla" del resumen (Hoy cambia de pestaña; Rejilla cierra la hoja).
    var onShowGrid: (() -> Void)? = nil
    /// Arranca el escaneo al aparecer (sin pantalla de introducción).
    var autoStart: Bool = false
    /// "Ahora no" en la introducción (Hoy, primera vez); nil = sin ese botón.
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
            .navigationTitle(stage == .intro ? "Escanear carrete" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(stage == .running ? "Cancelar" : "Cerrar") {
                        scanTask?.cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("scan.close")
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Tus últimas \(limit) fotos, en color")
                .font(.title2.bold())
            Text("ColorsApp analiza en el propio teléfono las últimas \(limit) fotos del carrete y busca en cada una la combinación de Sanzo Wada más parecida. Ninguna foto sale del dispositivo; solo se guardan los colores.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                start()
            } label: {
                Text("Escanear ahora")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.start")
            if let onSkip {
                Button {
                    onSkip()
                } label: {
                    Text("Ahora no")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("scan.skip")
                Text("Puedes hacerlo más tarde desde Hoy > Carrete o la Rejilla.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var running: some View {
        let p = env.scanProgress
        return VStack(spacing: 16) {
            Spacer()
            ProgressView(value: p.total > 0 ? p.fraction : nil)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            Text(phaseText(p))
                .font(.headline)
                .accessibilityIdentifier("scan.progress")
            if let startedAt = p.startedAt {
                Text(startedAt, style: .timer)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if p.skipped > 0 {
                Text("\(p.skipped) omitidas (solo en iCloud o no legibles)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if p.unlocked > 0 {
                Text(p.unlocked == 1 ? "1 combinación desbloqueada" : "\(p.unlocked) combinaciones desbloqueadas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Acceso limitado a Fotos")
                .font(.title2.bold())
            Text("Solo podemos ver las fotos que elijas. Selecciona hasta \(limit) y las analizamos igual, en el propio teléfono.")
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: limit, matching: .images, photoLibrary: .shared()) {
                Text("Elegir fotos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.picker")
            Spacer()
        }
        .padding()
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sin acceso a Fotos")
                .font(.title2.bold())
            Text("Para escanear el carrete, permite el acceso a Fotos en Ajustes > ColorsApp. Las fotos se analizan solo en el teléfono.")
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("Abrir Ajustes")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.openSettings")
            Button("Reintentar") { start() }
            Spacer()
        }
        .padding()
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("El escaneo no ha terminado", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            Button("Reintentar") { start() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
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
