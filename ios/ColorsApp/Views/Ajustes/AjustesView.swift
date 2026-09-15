// Pestaña Ajustes (PLAN §7.8): máscara de persona, "Rehacer escaneo del
// carrete", versiones (app, ce_version, dict_version, GRDB, SQLite),
// lanzamientos, "Exportar diagnóstico" (zip por ShareLink) y "Acerca de".
import SwiftUI

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
    @State private var personMask = false
    @State private var maskLoaded = false
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
            analysisSection
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
            personMask = (try? await env.settings.bool(.personMask)) ?? false
            maskLoaded = true
            migrations = (try? env.database.appliedMigrations()) ?? []
        }
        .onChange(of: personMask) { _, value in
            guard maskLoaded else { return }
            Task { try? await env.settings.setBool(.personMask, value) }
        }
    }

    // MARK: Secciones

    private var analysisSection: some View {
        Section {
            Toggle("Máscara de persona", isOn: $personMask)
                .accessibilityIdentifier("ajustes.mask")
        } header: {
            Text("Análisis")
        } footer: {
            Text("Con Vision (segmentación de personas) el motor pondera solo a la persona de la foto. Apagado por defecto; si Vision falla, la foto se analiza sin máscara.")
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
            Text("Zip con feedback.csv, scans.csv, times.txt y copias PNG sRGB de 256 px de las fotos con veredicto. Solo se crea al pulsar el botón y lo envías tú (AirDrop, Archivos…).")
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
        let provider: Diagnostics.ImageProvider = { scan in
            if let data = store.data(scanId: scan.id) { return data }
            if let asset = scan.assetLocalId { return await PhotoLibraryImages.srgbPNG(assetLocalId: asset) }
            return nil
        }
        do {
            let export = try await Diagnostics.export(scans: env.scans, feedback: env.feedback, timings: .shared,
                                                      imageProvider: provider)
            exportState = .done(export)
        } catch {
            exportState = .failed(ErrorText.describe(error))
        }
    }
}
