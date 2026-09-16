// Ajustes (PLAN §7.8), empujado desde el engranaje del Jardín (docs/design/DESIGN_SYSTEM.md
// §5.4 y §6.2) con el estilo del sistema de diseño: tarjetas del marco sobre pergamino.
// Secciones: «Recorte» (modo de personas, región y piel adaptativa: SubjectKit + motor),
// «Desbloqueo» (umbral del escaneo del carrete), «Carrete» (rehacer escaneo), «Diagnóstico»
// (zip por ShareLink), «Versiones» (app, ce_version, dict_version, GRDB, SQLite, migraciones,
// lanzamientos) y «Acerca de» con las atribuciones y las licencias OFL de las fuentes.
// Marco solarpunk de las pantallas secundarias (FIDELITY.md §7.5): cabecera esmerilada con el
// logotipo ChromaSol, motas de luz y tarjetas con halo, orbe de esquina e insignia de tono.
import SwiftUI
import SubjectKit

/// Ajustes con su propia pila (vista suelta; en la app se empuja `AjustesForm` desde el Jardín).
struct AjustesView: View {
    var body: some View {
        NavigationStack {
            AjustesForm()
        }
    }
}

/// Contenido de Ajustes (sin NavigationStack propio: lo empuja el Jardín).
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                recorteSection
                unlockSection
                librarySection
                diagnosticsSection
                versionsSection
                aboutSection
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .secondaryAmbience()
        .safeAreaInset(edge: .top, spacing: 0) {
            SecondaryHeader(section: "Ajustes", identifier: "ajustes.header")
        }
        .tint(Theme.primary)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            subject = (try? await env.settings.subjectSettings()) ?? .default
            subjectLoaded = true
            migrations = (try? env.database.appliedMigrations()) ?? []
        }
        .onChange(of: subject) { old, new in
            guard subjectLoaded else { return }
            Task { await AjustesForm.persist(old: old, new: new, settings: env.settings) }
        }
        .accessibilityIdentifier("ajustes.root")
    }

    /// Escribe solo las claves que cambiaron.
    static func persist(old: SubjectSettings, new: SubjectSettings, settings: SettingsRepository) async {
        if old.mode != new.mode { try? await settings.set(.subjectMode, new.mode.rawValue) }
        if old.region != new.region { try? await settings.set(.regionMode, new.region.rawValue) }
        if old.adaptiveSkin != new.adaptiveSkin { try? await settings.setBool(.adaptiveSkin, new.adaptiveSkin) }
        if old.unlockMaxScore != new.unlockMaxScore { try? await settings.setDouble(.unlockMaxScore, new.unlockMaxScore) }
    }

    /// Umbral con coma decimal: 12,0.
    static func thresholdText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "es_ES")))
    }

    // MARK: Secciones

    private var recorteSection: some View {
        AjustesCard(title: "Recorte", systemImage: "person.crop.rectangle", tone: .moss, kicker: "En el teléfono",
                    footer: "Antes de buscar los colores, Vision separa a las personas de la foto en el teléfono. «Persona principal» usa la más grande (en Extraer puedes elegir otra) y «Todas las personas» las une. «Solo ropa» usa la pose para quedarse con torso, brazos y piernas. «Excluir piel» aprende el tono de piel de cada cara y quita esos píxeles, salvo que la prenda se parezca demasiado a la piel. Desactivado: se analiza la foto completa.") {
            AjustesRow(title: "Personas") {
                Menu {
                    Picker("Personas", selection: $subject.mode) {
                        ForEach(SubjectSettings.settingsModes, id: \.self) { mode in
                            Text(mode.settingsTitle).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(subject.mode.settingsTitle).textRole(.labelLG).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.chipVertical + 1)
                    .background(Capsule().fill(Theme.containerHigh))
                    .fixedSize()
                }
                .accessibilityLabel("Personas: \(subject.mode.settingsTitle)")
                .accessibilityIdentifier("ajustes.subjectMode")
            }
            AjustesDivider()
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Región").textRole(.labelLG).foregroundStyle(Theme.onSurface)
                SegmentedPill(items: RegionMode.allCases.map { (id: $0, title: $0.settingsTitle) }, selection: $subject.region)
                    .accessibilityIdentifier("ajustes.regionMode")
            }
            .padding(.vertical, Spacing.sm)
            .disabled(subject.mode == .off)
            .opacity(subject.mode == .off ? 0.5 : 1)
            AjustesDivider()
            Toggle(isOn: $subject.adaptiveSkin) {
                Text("Excluir piel (adaptativo)").textRole(.labelLG).foregroundStyle(Theme.onSurface)
            }
            .tint(Theme.primary)
            .padding(.vertical, Spacing.sm)
            .disabled(subject.mode == .off)
            .opacity(subject.mode == .off ? 0.5 : 1)
            .accessibilityIdentifier("ajustes.adaptiveSkin")
        }
    }

    private var unlockSection: some View {
        AjustesCard(title: "Desbloqueo", systemImage: "lock.open", tone: .amber, kicker: "Umbral",
                    footer: "Informativo: en el escaneo del carrete, una foto desbloquea su combinación si no es ambigua y su score (ΔE00 ponderado, menor es mejor) no pasa de este valor. Por defecto 12,0.") {
            Stepper(value: $subject.unlockMaxScore, in: 1...40, step: 0.5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Umbral de desbloqueo").textRole(.labelLG).foregroundStyle(Theme.onSurface)
                    Spacer(minLength: Spacing.sm)
                    Text(Self.thresholdText(subject.unlockMaxScore))
                        .textRole(.labelLG)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityIdentifier("ajustes.unlockMaxScore")
        }
    }

    private var librarySection: some View {
        AjustesCard(title: "Carrete", systemImage: "photo.stack", tone: .celadon, kicker: "200 fotos",
                    footer: "Borra los desbloqueos y análisis del carrete y vuelve a analizar las últimas 200 fotos en el teléfono.") {
            GhostButton(title: "Rehacer escaneo del carrete", systemImage: "arrow.clockwise") {
                confirmRescan = true
            }
            .disabled(scanState == .running)
            .padding(.vertical, Spacing.xs)
            .confirmationDialog("Se borran los desbloqueos y análisis del carrete y se vuelven a analizar las últimas 200 fotos.",
                                isPresented: $confirmRescan, titleVisibility: .visible) {
                Button("Rehacer escaneo", role: .destructive) {
                    Task { await redoScan() }
                }
            }
            .accessibilityIdentifier("ajustes.rescan")
            switch scanState {
            case .idle:
                EmptyView()
            case .running:
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ProgressView(value: env.scanProgress.fraction)
                        .tint(Theme.primary)
                    Text(progressText).textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(.vertical, Spacing.xs)
            case .done(let summary):
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label {
                        Text("\(summary.scanned) fotos analizadas en \(WrappedSummaryView.durationText(summary.duration))")
                            .textRole(.labelLG)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(Theme.primary)
                    Text("\(summary.newUnlocks.count) combinaciones nuevas · \(summary.totalUnlocked)/\(env.comboCount) en tu rejilla · \(summary.skipped) omitidas · \(summary.failed) fallidas")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                    if let top = summary.topCombos.first {
                        Text("La más frecuente: \(GardenText.comboTitle(top.comboId, dictionary: env.dictionary)) (\(top.count) fotos)")
                            .textRole(.bodySM)
                            .foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .padding(.vertical, Spacing.xs)
            case .failed(let message):
                Label {
                    Text(message).textRole(.bodySM)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Theme.error)
                .accessibilityIdentifier("ajustes.scan.error")
            }
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
        AjustesCard(title: "Diagnóstico", systemImage: "doc.zipper", tone: .moss, kicker: "Zip local",
                    footer: "Zip con feedback.csv, scans.csv, times.txt y, por cada foto con veredicto, una copia PNG sRGB de 256 px con sus máscaras de recorte y sus capas. Solo se crea al pulsar el botón y lo envías tú (AirDrop, Archivos…).") {
            SolarSecondaryButton(title: "Exportar diagnóstico", systemImage: "doc.zipper") {
                Task { await exportDiagnostics() }
            }
            .disabled(exportState == .building)
            .padding(.vertical, Spacing.xs)
            .accessibilityIdentifier("ajustes.export")
            switch exportState {
            case .idle:
                EmptyView()
            case .building:
                HStack(spacing: Spacing.sm) {
                    ProgressView().tint(Theme.primary)
                    Text("Preparando el zip…").textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
                }
            case .done(let export):
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("\(export.feedbackRows) veredictos · \(export.scanRows) scans · \(export.images) fotos incluidas · \(export.omittedImages) omitidas")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                    ForEach(export.notes, id: \.self) { note in
                        Text(note).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                    }
                    ShareLink(item: export.url) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                            Text(export.url.lastPathComponent).textRole(.labelMD).lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, Spacing.margin)
                        .padding(.vertical, Spacing.buttonVertical)
                        .frame(maxWidth: .infinity, minHeight: Sizes.minTouch)
                        .background(Capsule().fill(Theme.primary))
                    }
                    .buttonStyle(.solarPress)
                    .accessibilityIdentifier("ajustes.export.share")
                }
            case .failed(let message):
                Label {
                    Text(message).textRole(.bodySM)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Theme.error)
            }
        }
    }

    private var versionsSection: some View {
        AjustesCard(title: "Versiones", systemImage: "info.circle", tone: .celadon, kicker: "Build") {
            AjustesValueRow(title: "App", value: "\(Diagnostics.appVersion) (\(Diagnostics.appBuild))")
            AjustesDivider()
            AjustesValueRow(title: "Motor (ce_version)", value: env.engineVersion)
            AjustesDivider()
            AjustesValueRow(title: "Diccionario (dict_version)", value: env.dictVersion)
            if env.engineDictVersion != env.dictVersion {
                Label {
                    Text("El motor embebe el diccionario \(env.engineDictVersion)").textRole(.bodySM)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Theme.error)
                .padding(.vertical, Spacing.xs)
            }
            AjustesDivider()
            AjustesValueRow(title: "GRDB.swift", value: Diagnostics.grdbVersion)
            AjustesDivider()
            AjustesValueRow(title: "SQLite", value: Diagnostics.sqliteVersion)
            AjustesDivider()
            AjustesValueRow(title: "Migraciones", value: migrations.isEmpty ? "—" : migrations.joined(separator: ", "))
            AjustesDivider()
            AjustesValueRow(title: "Lanzamientos", value: "\(env.launches)")
                .accessibilityIdentifier("ajustes.launches")
        }
    }

    private var aboutSection: some View {
        AjustesCard(title: "Acerca de", systemImage: "sun.max", tone: .amber, kicker: AppBrand.name) {
            NavigationLink {
                AboutView()
            } label: {
                AjustesLinkRow(title: "Acerca de \(AppBrand.name)", detail: "Qué hace con tus fotos y atribuciones")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustes.about")
            AjustesDivider()
            NavigationLink {
                FontLicensesView()
            } label: {
                AjustesLinkRow(title: "Licencias de fuentes", detail: "Literata y Plus Jakarta Sans · SIL OFL 1.1")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustes.fontLicenses")
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
        do {
            exportState = .done(try await DiagnosticsExportAction.run(env: env))
        } catch {
            exportState = .failed(ErrorText.describe(error))
        }
    }
}

// MARK: - Piezas de Ajustes

/// Tarjeta de sección de Ajustes: insignia de tono + título `headline-sm`, filas y nota al pie.
struct AjustesCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tone: Tone = .moss
    /// Rótulo en versales a la derecha del título (`text-label-sm text-secondary tracking-widest
    /// uppercase` del ejemplo); nil lo oculta.
    var kicker: String?
    var footer: String?
    private let content: Content

    init(title: String, systemImage: String, tone: Tone = .moss, kicker: String? = nil, footer: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.kicker = kicker
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                SectionBadge(systemImage: systemImage, tone: tone)
                Text(title)
                    .textRole(.headlineSM)
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                if let kicker {
                    Spacer(minLength: Spacing.sm)
                    Text(kicker)
                        .textRole(.overline)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            if let footer {
                Text(footer)
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                SectionOrb(tone: tone).offset(x: 28, y: -32)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .elevation(.rest)
        }
        .glowCard(cornerRadius: Radius.card)
    }
}

/// Fila «título · control».
struct AjustesRow<Control: View>: View {
    let title: String
    private let control: Control

    init(title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title).textRole(.labelLG).foregroundStyle(Theme.onSurface)
            Spacer(minLength: Spacing.sm)
            control
        }
        .frame(minHeight: Sizes.minTouch)
    }
}

/// Fila «título · valor» (versiones).
struct AjustesValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title).textRole(.labelMD).foregroundStyle(Theme.onSurfaceVariant)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .textRole(.hex)
                .foregroundStyle(Theme.onSurface)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// Fila de navegación con título, detalle y chevron.
struct AjustesLinkRow: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textRole(.labelLG).foregroundStyle(Theme.onSurface)
                if let detail {
                    Text(detail).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: Sizes.minTouch)
        .contentShape(Rectangle())
    }
}

/// Separador fino `outlineVariant`.
struct AjustesDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.outlineVariant.opacity(0.6))
            .frame(height: 1 / max(displayScale, 1))
    }
}
