// Visor del resultado de Extraer (docs/design/DESIGN_SYSTEM.md §5.2, FIDELITY.md §4 E5–E18; ejemplo
// «clothing_extractor»): la foto ajustada SIN recorte (los alfileres caen donde toca) sobre una copia
// desenfocada de la misma foto que llena el marco de 400 pt (se ve «a sangre» como en el ejemplo), con
//   - arriba: el chip de pasos del recorte (texto real de SubjectExplanation; tocar lo
//     despliega entero) y «Ver máscara» / «Ocultar máscara»;
//   - sobre la foto: la máscara usada, las cinco motas de luz del ejemplo (M20) y un alfiler vivo
//     por color en el centroide de sus píxeles (`ExtractPinOverlay`: aro con ping, halos, glifo y
//     etiqueta con «✦»; tocar = seleccionar; mantener pulsado = aislar sus píxeles);
//   - abajo, en pergamino esmerilado: el sol mini con ping (persona detectada o re-análisis), la
//     fila «Personas» (miniaturas y «Todas» con dos o más; tocar re-analiza sin Vision) y «Ver capas».
// Viñeta solo en los bordes superior e inferior. Motas y luces de alfiler se apagan con la máscara
// visible, al aislar un color o con un alfiler seleccionado.
import SwiftUI
import SubjectKit

struct ExtractViewfinder: View {
    @ObservedObject var model: ResultViewModel
    let onOpenLayers: () -> Void

    @State private var noticeExpanded = false
    @State private var width: CGFloat = 370

    private var image: CGImage { model.outcome.image }

    /// Franjas del HUD superior (aviso y máscara) e inferior (personas y capas).
    nonisolated static let hudTop: CGFloat = 48
    nonisolated static let hudBottom: CGFloat = 68

    /// Geometría del visor para una foto de proporción `aspect` (ancho / alto) en un ancho `width`:
    /// alto del marco (300…400 pt) y márgenes de la foto. Si la foto cabe entre las dos franjas del
    /// HUD sin quedarse por debajo del 75 % del ancho, se coloca entre ellas (los alfileres no quedan
    /// bajo el HUD); si no (fotos verticales), ocupa todo el marco y el HUD va encima.
    nonisolated static func layout(aspect: CGFloat, width: CGFloat) -> (height: CGFloat, top: CGFloat, bottom: CGFloat) {
        let a = max(aspect, 0.01)
        let height = min(Sizes.viewfinderMaxHeight, max(300, width / a + hudTop + hudBottom))
        let inset = min(width, (height - hudTop - hudBottom) * a)
        if inset >= 0.75 * width { return (height, hudTop, hudBottom) }
        return (height, 0, 0)
    }

    private var geometry: (height: CGFloat, top: CGFloat, bottom: CGFloat) {
        Self.layout(aspect: CGFloat(image.width) / CGFloat(max(image.height, 1)), width: width)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let g = geometry
        GeometryReader { geo in
            let imageSize = CGSize(width: image.width, height: image.height)
            let photoSize = CGSize(width: geo.size.width, height: max(0, geo.size.height - g.top - g.bottom))
            ZStack {
                Theme.containerLow
                backdrop
                vignette
                ZStack {
                    photo
                    ExtractViewfinderMotes(beadCenters: ExtractPinOverlay.centers(pins: model.pins, imageSize: imageSize, in: photoSize),
                                           isActive: ambientLightsOn && model.selectedSwatch == nil)
                    ExtractPinOverlay(pins: model.pins, imageSize: imageSize,
                                      selectedID: model.selectedSwatch,
                                      dominantID: dominantID,
                                      lightsOn: ambientLightsOn,
                                      onSelect: { pin in
                                          model.selectedSwatch = model.selectedSwatch == pin.id ? nil : pin.id
                                      },
                                      onIsolate: { pin, active in model.setIsolation(pin.id, active: active) })
                        .accessibilityIdentifier("result.pins")
                }
                .padding(.top, g.top)
                .padding(.bottom, g.bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: g.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipShape(shape)
        .overlay(alignment: .top) { topHUD }
        .overlay(alignment: .bottom) { bottomBar }
        // `shadow-md`: `0 4px 6px -1px` y `0 2px 4px -2px` negro 10 %.
        .background {
            shape.fill(Theme.containerLow)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
        }
        // Lo que va sobre la foto (aviso, alfileres, personas) no crece más allá de xxLarge: con
        // tamaños de accesibilidad taparía la foto; los mismos datos van debajo, a tamaño completo.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.photo")
    }

    /// Luces de los alfileres y motas: apagadas con la máscara visible o un color aislado.
    private var ambientLightsOn: Bool { !(model.showMask && model.maskOverlay != nil) && model.isolatedSwatch == nil && !model.reanalyzing }

    /// Color de mayor peso (halo melocotón en su alfiler).
    private var dominantID: Int? {
        model.palette.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) })?.id
    }

    // MARK: Foto y capas

    /// La misma foto, desenfocada, llenando el marco detrás de la foto ajustada (sin bandas vacías).
    private var backdrop: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .blur(radius: 32, opaque: true)
            .saturation(0.8)
            .overlay(Theme.containerLow.opacity(0.3))
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var photo: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .overlay {
                if model.showMask, let overlay = model.maskOverlay {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .accessibilityIdentifier("result.maskOverlay")
                }
            }
            .overlay {
                if let overlay = model.isolationOverlay {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .accessibilityIdentifier("result.isolation")
                }
            }
            .overlay {
                if model.reanalyzing {
                    ZStack {
                        Color.black.opacity(0.25)
                        ProgressView().tint(.white)
                    }
                }
            }
    }

    /// Viñeta del ejemplo (`from-on-surface/40 via-transparent to-on-surface/20`) solo en los bordes
    /// superior e inferior, bajo el HUD: el centro de la foto no se oscurece (juicio de color).
    private var vignette: some View {
        let ink = Color(rgb8: 0x1C, 0x1C, 0x17)
        return VStack(spacing: 0) {
            LinearGradient(colors: [ink.opacity(0.20), ink.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 56)
            Spacer(minLength: 0)
            LinearGradient(colors: [ink.opacity(0), ink.opacity(0.40)], startPoint: .top, endPoint: .bottom)
                .frame(height: 76)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: HUD

    private var topHUD: some View {
        let notice = model.maskNotice
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { noticeExpanded.toggle() }
                } label: {
                    ExtractHUDChip(title: notice.text,
                                   systemImage: notice.isFallback ? "exclamationmark.triangle" : notice.systemImage,
                                   textColor: notice.isFallback ? Theme.secondary : Theme.onSurface)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Recorte: \(notice.text)")
                .accessibilityHint(noticeExpanded ? "Oculta el detalle" : "Muestra el texto completo")
                .accessibilityIdentifier("result.subjectNotice")
                .layoutPriority(1)
                Spacer(minLength: 0)
                maskToggle
            }
            if noticeExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(notice.text)
                        .textRole(.labelMD)
                        .foregroundStyle(notice.isFallback ? Theme.secondary : Theme.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SubjectExplanation.stepTitles(result: model.outcome.subject).joined(separator: " → "))
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("«Ver capas» explica cada paso.")
                        .textRole(.bodySM)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .parchmentFrost(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .elevation(.overPhoto)
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { noticeExpanded = false } }
                .accessibilityIdentifier("result.subjectNotice.detail")
            }
            if model.isExample {
                SolarBadge(title: "Ejemplo", systemImage: "flask", fill: Theme.tertiaryFixed, foreground: Theme.onTertiaryFixed)
                    .accessibilityIdentifier("result.example")
            }
        }
        .padding(Spacing.md)
    }

    private var maskToggle: some View {
        let available = model.maskOverlay != nil
        let on = model.showMask && available
        return Button {
            model.showMask.toggle()
        } label: {
            if available {
                ExtractHUDChip(title: on ? "Ocultar máscara" : "Ver máscara",
                               systemImage: on ? "eye.slash" : "theatermask.and.paintbrush",
                               tint: Theme.primary, textColor: Theme.primary, isOn: on)
            } else {
                // Sin máscara: solo el icono, apagado, para dejar sitio al aviso del recorte.
                Image(systemName: "theatermask.and.paintbrush")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(width: 30, height: 26)
                    .background {
                        ZStack {
                            Capsule().fill(.ultraThinMaterial)
                            Capsule().fill(Theme.surface.opacity(0.85))
                        }
                    }
                    .opacity(0.7)
            }
        }
        .buttonStyle(.pressScale)
        .disabled(!available)
        .fixedSize()
        .accessibilityLabel(on ? "Ocultar máscara" : "Ver máscara")
        .accessibilityIdentifier("result.showMask")
    }

    // MARK: Personas y capas

    private var bottomBar: some View {
        HStack(spacing: Spacing.sm) {
            peopleSun
            if model.showsPeopleRow {
                peopleStrip
            } else {
                Text(peopleSummary)
                    .textRole(.labelSM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier("result.peopleSummary")
            }
            Spacer(minLength: 0)
            Button(action: onOpenLayers) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.container))
                    .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .disabled(model.reanalyzing)
            .accessibilityLabel("Ver capas")
            .accessibilityIdentifier("result.layers")
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .frame(minHeight: 48)
        // `p-2 rounded-xl bg-surface/90 backdrop-blur-lg shadow-sm`, a 12 pt de los bordes.
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.surface.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
        }
        .padding(Spacing.md)
    }

    /// Sol mini de la barra (E18): `w-6 h-6` con aro `bg-secondary-fixed-dim/50 animate-ping opacity-50` y
    /// sol de 20 pt (núcleo `#954A00`, rayos `#FD933F` de 2 pt, ojos blancos, `drop-shadow 8px` naranja 80 %).
    /// El aro late mientras hay personas detectadas o se re-analiza; sin personas, quieto.
    private var peopleSun: some View {
        let live = model.reanalyzing || !model.people.isEmpty
        return ZStack {
            if live {
                Circle()
                    .fill(Color(brand: 0xFFB785, opacity: 0.5))
                    .frame(width: 24, height: 24)
                    .pingDot()
                    .opacity(0.5)
            }
            SunSpiritMark(size: 20, core: Color(brand: 0x954A00), rays: Color(brand: 0xFD933F), face: .white,
                          rayWidth: 2, coreRadius: 5,
                          glow: ShadowSpec(TailwindColor.secondaryContainer.opacity(0.8), blur: 8), bobs: false)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
        .accessibilityIdentifier("result.peopleSun")
    }

    private var peopleSummary: String {
        let n = model.people.count
        if n == 0 {
            return model.outcome.subjectOptions.mode == .off ? "Recorte desactivado" : "Sin personas · foto completa"
        }
        return "1 persona"
    }

    /// Fila «Personas»: miniatura de cada persona (bbox de su instancia) y «Todas».
    private var peopleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(model.personThumbnails.enumerated()), id: \.offset) { index, thumb in
                    personButton(.person(index), label: index == 0 ? "Persona 1, principal" : "Persona \(index + 1)") {
                        Image(decorative: thumb, scale: 1).resizable().scaledToFill()
                    }
                }
                personButton(.all, label: "Todas las personas") {
                    Text("Todas").textRole(.labelSM).foregroundStyle(Theme.primary)
                        .padding(.horizontal, Spacing.sm)
                        .frame(maxHeight: .infinity)
                        .background(Theme.container)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("result.people")
    }

    private func personButton<Content: View>(_ choice: ResultViewModel.PersonChoice, label: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        let selected = model.currentChoice == choice
        let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        let isAll = choice == .all
        return Button {
            Task { await model.choose(choice) }
        } label: {
            content()
                .frame(width: isAll ? nil : 30, height: 36)
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? Theme.primary : Theme.outlineVariant, lineWidth: selected ? 2 : 1))
                .frame(minWidth: 36, minHeight: Sizes.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .disabled(!model.canChangePerson && !selected)
        .opacity(!model.canChangePerson && !selected ? 0.5 : 1)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier({
            switch choice {
            case .all: return "result.person.all"
            case .person(let i): return "result.person.\(i)"
            }
        }())
    }
}
