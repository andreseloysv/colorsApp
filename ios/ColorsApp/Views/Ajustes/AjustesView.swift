// Pestaña Ajustes (PLAN §7.8): "Recorte" (modo de personas, región y piel
// adaptativa: SubjectKit + motor), "Desbloqueo" (umbral del escaneo del carrete),
// "Rehacer escaneo del carrete", versiones (app, ce_version, dict_version, GRDB,
// SQLite), lanzamientos, "Exportar diagnóstico" (zip por ShareLink) y "Acerca de".
import SwiftUI
import SubjectKit

struct AjustesView: View {
    var body: some View {
        NavigationStack {
            AjustesForm()
                .navigationTitle("Ajustes")
        }
    }
}

/// Contenido de Ajustes (sin NavigationStack propio: lo envuelve AjustesView o,
/// en depuración, la pila de Hoy).
struct AjustesForm: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var subject = SubjectSettings.default
    @State private var subjectLoaded = false
    @State private var scanState: ScanState = .idle
    @State private var confirmRescan = false
    @State private var exportState: ExportState = .idle
    @State private var migrations: [String] = []

    enum ScanState: Equatable {
        case idle
        case running
        case done(ScanSummary)
        case failed(String)
    }

    enum ExportState: Equatable {
        case idle
        case building
        case done(Diagnostics.Export)
        case failed(String)
    }

    var body: some View {
        Form {
            recorteSection
            unlockSection
            librarySection
            diagnosticsSection
            versionsSection
            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("Acerca de", systemImage: "info.circle")
                }
            }
        }
        .task {
            subject = (try? await env.settings.subjectSettings()) ?? .default
            subjectLoaded = true
            migrations = (try? env.database.appliedMigrations()) ?? []
        }
        .onChange(of: subject) { old, new in
            guard subjectLoaded else { return }
            Task { await AjustesForm.persist(old: old, new: new, settings: env.settings) }
        }
    }

    /// Escribe solo las claves que cambiaron.
    static func persist(old: SubjectSettings, new: SubjectSettings, settings: SettingsRepository) async {
        if old.mode != new.mode { try? await settings.set(.subjectMode, new.mode.rawValue) }
        if old.region != new.region { try? await settings.set(.regionMode, new.region.rawValue) }
        if old.adaptiveSkin != new.adaptiveSkin { try? await settings.setBool(.adaptiveSkin, new.adaptiveSkin) }
        if old.unlockMaxScore != new.unlockMaxScore { try? await settings.setDouble(.unlockMaxScore, new.unlockMaxScore) }
    }

    // MARK: Secciones

    private var recorteSection: some View {
        Section {
            Picker("Personas", selection: $subject.mode) {
                ForEach(SubjectSettings.settingsModes, id: \.self) { mode in
                    Text(mode.settingsTitle).tag(mode)
                }
            }
            .accessibilityIdentifier("ajustes.subjectMode")
            Picker("Región", selection: $subject.region) {
                ForEach(RegionMode.allCases, id: \.self) { region in
                    Text(region.settingsTitle).tag(region)
                }
            }
            .disabled(subject.mode == .off)
            .accessibilityIdentifier("ajustes.regionMode")
            Toggle("Excluir piel (adaptativo)", isOn: $subject.adaptiveSkin)
                .disabled(subject.mode == .off)
                .accessibilityIdentifier("ajustes.adaptiveSkin")
        } header: {
            Text("Recorte")
        } footer: {
            Text("Antes de buscar los colores, Vision separa a las personas de la foto en el teléfono. «Persona principal» usa la más grande (en Resultado puedes elegir otra) y «Todas las personas» las une. «Solo ropa» usa la pose para quedarse con torso, brazos y piernas. «Excluir piel» aprende el tono de piel de cada cara y quita esos píxeles, salvo que la prenda se parezca demasiado a la piel. Desactivado: se analiza la foto completa.")
        }
    }

    private var unlockSection: some View {
        Section {
            Stepper(value: $subject.unlockMaxScore, in: 1...40, step: 0.5) {
                LabeledContent("Umbral de desbloqueo", value: String(format: "%.1f", subject.unlockMaxScore))
            }
            .accessibilityIdentifier("ajustes.unlockMaxScore")
        } header: {
            Text("Desbloqueo")
        } footer: {
            Text("Informativo: en el escaneo del carrete, una foto desbloquea su combinación si no es ambigua y su score (ΔE00 ponderado, menor es mejor) no pasa de este valor. Por defecto 12,0.")
        }
    }

    private var librarySection: some View {
        Section {
            Button {
                confirmRescan = true
            } label: {
                Label("Rehacer escaneo del carrete", systemImage: "arrow.clockwise")
            }
            .disabled(scanState == .running)
            .confirmationDialog("Se borran los desbloqueos y análisis del carrete y se vuelven a analizar las últimas 200 fotos.",
                                isPresented: $confirmRescan, titleVisibility: .visible) {
                Button("Rehacer escaneo", role: .destructive) {
                    Task { await redoScan() }
                }
            }
            switch scanState {
            case .idle:
                EmptyView()
            case .running:
                ProgressView(value: env.scanProgress.fraction) {
                    Text(progressText)
                }
            case .done(let summary):
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(summary.scanned) fotos analizadas en \(String(format: "%.1f", summary.duration)) s", systemImage: "checkmark.circle")
                    Text("\(summary.newUnlocks.count) combinaciones nuevas · \(summary.totalUnlocked)/\(env.comboCount) en tu rejilla · \(summary.skipped) omitidas · \(summary.failed) fallidas")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let top = summary.topCombos.first {
                        Text("La más frecuente: \(env.dictionary.displayName(id: top.comboId)) (\(top.count) fotos)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ajustes.scan.error")
            }
        } header: {
            Text("Carrete")
        }
    }

    private var progressText: String {
        switch env.scanProgress.phase {
        case .idle: "Preparando…"
        case .requestingAccess: "Pidiendo acceso a Fotos…"
        case .fetching: "Buscando las últimas fotos…"
        case .analyzing: "Analizando \(env.scanProgress.processed)/\(env.scanProgress.total)…"
        case .finished: "Terminado"
        case .failed: "Fallido"
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button {
                Task { await exportDiagnostics() }
            } label: {
                Label("Exportar diagnóstico", systemImage: "doc.zipper")
            }
            .disabled(exportState == .building)
            .accessibilityIdentifier("ajustes.export")
            switch exportState {
            case .idle:
                EmptyView()
            case .building:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparando el zip…")
                }
            case .done(let export):
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(export.feedbackRows) veredictos · \(export.scanRows) scans · \(export.images) fotos incluidas · \(export.omittedImages) omitidas")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(export.notes, id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    ShareLink(item: export.url) {
                        Label(export.url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        } header: {
            Text("Diagnóstico")
        } footer: {
            Text("Zip con feedback.csv, scans.csv, times.txt y, por cada foto con veredicto, una copia PNG sRGB de 256 px con sus máscaras de recorte y sus capas. Solo se crea al pulsar el botón y lo envías tú (AirDrop, Archivos…).")
        }
    }

    private var versionsSection: some View {
        Section("Versiones") {
            LabeledContent("App", value: "\(Diagnostics.appVersion) (\(Diagnostics.appBuild))")
            LabeledContent("Motor (ce_version)", value: env.engineVersion)
            LabeledContent("Diccionario (dict_version)", value: env.dictVersion)
            if env.engineDictVersion != env.dictVersion {
                Label("El motor embebe el diccionario \(env.engineDictVersion)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            LabeledContent("GRDB.swift", value: Diagnostics.grdbVersion)
            LabeledContent("SQLite", value: Diagnostics.sqliteVersion)
            LabeledContent("Migraciones", value: migrations.isEmpty ? "—" : migrations.joined(separator: ", "))
            LabeledContent("Lanzamientos", value: "\(env.launches)")
                .accessibilityIdentifier("ajustes.launches")
        }
    }

    // MARK: Acciones

    private func redoScan() async {
        if env.scanRunner is NoopScanRunner {
            scanState = .failed(ErrorText.describe(ScanError.notImplemented))
            return
        }
        scanState = .running
        do {
            try await env.unlocks.deleteAll(source: .library)
            try await env.scans.deleteAll(source: .library)
            let summary = try await env.runInitialScan(limit: 200)
            scanState = .done(summary)
        } catch {
            scanState = .failed(ErrorText.describe(error))
        }
    }

    private func exportDiagnostics() async {
        exportState = .building
        let store = FeedbackImageStore.shared
        let fallbackOptions = subject.subjectOptions
        let provider: Diagnostics.PhotoProvider = { scan in
            if let attachment = store.attachment(scanId: scan.id) { return attachment }
            if let asset = scan.assetLocalId {
                return await PhotoLibraryImages.attachment(assetLocalId: asset, scan: scan, fallbackOptions: fallbackOptions)
            }
            return nil
        }
        do {
            let export = try await Diagnostics.export(scans: env.scans, feedback: env.feedback, timings: .shared,
                                                      photoProvider: provider)
            exportState = .done(export)
        } catch {
            exportState = .failed(ErrorText.describe(error))
        }
    }
}
