// Estado de captura de Extraer (docs/design/DESIGN_SYSTEM.md §5.2, «Estado de captura»):
// el visor de 400 pt sin foto con el título, «Elegir foto», «Cámara» y «Escanear carrete»;
// sobre él, el recorte que se aplicará (Ajustes) y, mientras se analiza, la foto elegida con
// el progreso. Debajo, qué hace el análisis (tres pasos reales) y el progreso del escaneo
// del carrete si está en curso. Sin colores de datos: todo es marco.
// Luces del ejemplo (FIDELITY.md §4 E8, E9, E38): motas de luz y retículas de esquina en el visor,
// el sol con carita en disco (aro de ping y flotación) y «Elegir foto» luminoso (halo musgo y
// naranja, barrido de luz bajo el texto).
import SwiftUI
import SubjectKit

struct ExtractCaptureContent: View {
    let state: ExtractCaptureState
    /// Foto elegida mientras se analiza.
    var preview: CGImage?
    let onPick: () -> Void
    let onCamera: () -> Void
    let onScan: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var settings: SubjectSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            viewfinder
            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .textRole(.bodyMD)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("extraer.error")
            }
            scanProgress
            steps
        }
        .task { settings = try? await env.settings.subjectSettings() }
    }

    // MARK: Visor

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return ZStack {
            Theme.containerLow
            SolarWash(kind: .warm, diameter: 220, blur: 60).offset(x: 120, y: -150)
            SolarWash(kind: .green, diameter: 200, blur: 56).offset(x: -130, y: 160)
            if let preview, state.isWorking {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28, opaque: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: Sizes.viewfinderMaxHeight)
                    .accessibilityHidden(true)
                Color.black.opacity(0.30)
                // Mientras analiza, las motas siguen flotando sobre la foto (ambiente de «escaneo»).
                ExtractViewfinderMotes()
                ExtractReticles(color: Theme.surface.opacity(0.6))
                progress
            } else {
                ExtractViewfinderMotes()
                ExtractReticles(color: Theme.secondary.opacity(0.35))
                VStack(spacing: 0) {
                    HStack {
                        ExtractHUDChip(title: cropTitle, systemImage: "person.crop.rectangle")
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .accessibilityIdentifier("extraer.cropSettings")
                        Spacer(minLength: 0)
                    }
                    .padding(Spacing.md)
                    intro
                    Spacer(minLength: Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // Alto del visor del ejemplo (400 pt); con tamaños de accesibilidad crece con el texto.
        .frame(minHeight: Sizes.viewfinderMaxHeight)
        .clipShape(shape)
        // `shadow-md` del visor del ejemplo.
        .background {
            shape.fill(Theme.containerLow)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
        }
        .accessibilityElement(children: .contain)
    }

    private var intro: some View {
        VStack(spacing: Spacing.md) {
            ExtractSunDisc(diameter: 64)
                .accessibilityIdentifier("extraer.sunSpirit")
            VStack(spacing: Spacing.xs) {
                Text("Analiza la ropa de una foto")
                    .textRole(.headlineSM)
                    .foregroundStyle(Theme.onSurface)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Se procesa en el teléfono; nada sale del dispositivo.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Spacing.sm) {
                ExtractLuminousButton(title: "Elegir foto", icon: .symbol("photo.on.rectangle"), action: onPick)
                    .accessibilityIdentifier("extraer.pick")
                ExtractPillButton(title: "Cámara", systemImage: "camera", action: onCamera)
                    .disabled(!CameraPicker.isAvailable)
                    .accessibilityIdentifier("extraer.camera")
                if !CameraPicker.isAvailable {
                    Text("No hay cámara en este dispositivo (simulador).")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
                GhostButton(title: dynamicTypeSize.isAccessibilitySize ? "Carrete" : "Escanear carrete (200 fotos)",
                            systemImage: "photo.stack", action: onScan)
                    .disabled(env.scanRunner is NoopScanRunner || scanRunning)
                    .accessibilityIdentifier("extraer.scanLibrary")
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }

    private var progress: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().tint(Theme.primary)
            if case .working(let text) = state {
                Text(text).textRole(.labelLG).foregroundStyle(Theme.onSurface)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .parchmentFrost(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .elevation(.overPhoto)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("extraer.progress")
    }

    /// Recorte que se aplicará con los Ajustes actuales.
    private var cropTitle: String {
        guard let s = settings else { return "Recorte de sujeto" }
        if s.mode == .off { return "Recorte desactivado · foto completa" }
        var parts = [s.mode.settingsTitle, s.region == .clothing ? "solo ropa" : "persona completa"]
        if s.adaptiveSkin { parts.append("sin piel") }
        return parts.joined(separator: " · ")
    }

    // MARK: Carrete y pasos

    private var scanRunning: Bool {
        switch env.scanProgress.phase {
        case .requestingAccess, .fetching, .analyzing: true
        default: false
        }
    }

    @ViewBuilder private var scanProgress: some View {
        if scanRunning {
            let p = env.scanProgress
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label {
                    Text(p.phase == .analyzing ? "Analizando \(p.processed)/\(p.total) fotos del carrete"
                         : p.phase == .fetching ? "Buscando las últimas fotos…" : "Pidiendo acceso a Fotos…")
                        .textRole(.labelLG)
                        .foregroundStyle(Theme.onSurface)
                } icon: {
                    Image(systemName: "photo.stack").foregroundStyle(Theme.secondary)
                }
                ProgressView(value: p.phase == .analyzing ? p.fraction : nil)
                    .tint(Theme.primary)
            }
            .padding(Spacing.md)
            .solarCard(fill: Theme.container, elevation: .flat)
            .accessibilityIdentifier("extraer.scanProgress")
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Qué hace el análisis").textRole(.overline).foregroundStyle(Theme.secondary)
            step("person.crop.rectangle", "Recorta a la persona",
                 "Vision separa a cada persona; el motor se queda con su ropa y quita la piel.")
            step("drop.halffull", "Extrae los colores",
                 "Hasta 5 colores con su peso y el nombre del color de Wada más cercano.")
            step("square.grid.2x2", "Busca la combinación",
                 "Las 3 combinaciones de Sanzo Wada más parecidas, de las 348.")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solarCard(fill: Theme.card, elevation: .rest)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tone.moss.onBadge)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Tone.moss.badgeFill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textRole(.labelLG).foregroundStyle(Theme.onSurface)
                Text(detail).textRole(.bodySM).foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
