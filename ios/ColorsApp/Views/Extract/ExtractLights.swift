// Luces y piezas de Extraer con los valores del ejemplo (docs/design/FIDELITY.md §4):
//   - `ExtractViewfinderMotes` (E8, M20): las cinco motas del visor con posición, tamaño, color,
//     `blur` y halo exactos; flotan 8 × −40 pt con `ease-out` (7 / 8,5 / 6,5 / 9 / 8,5 s) y nunca
//     pasan a menos de 8 pt de una cuenta de color.
//   - `ExtractReticles` (E9): esquinas de visor dibujadas.
//   - `ExtractLuminousButton` (E28–E31, E38): CTA musgo con halo `0 4px 16px` musgo 35 % +
//     `0 0 20px` naranja 30 %, barrido de luz de 2,5 s bajo el texto, brote que se mece con yema
//     que titila y «✦» con resplandor; al pulsar, 0,99 y fondo `primary-container`.
//   - `ExtractPillButton` (E32): secundario `bg-surface-container shadow-sm active:scale-95`.
//   - `ExtractGarmentCard` (E22–E25): tarjeta de prenda en pocillo neutro con «✦»/«✧», hex con
//     icono de copiar y respuesta al pulsar (0,98 + sombra neutra `0 6px 20px` negra 12 %).
import SwiftUI

// MARK: - Motas del visor

struct ExtractViewfinderMotes: View {
    /// Una mota: esquina superior en fracción del alto y borde izquierdo o derecho en fracción del ancho.
    struct Spec: Sendable, Identifiable {
        let id: Int
        let top: CGFloat
        let left: CGFloat?
        let right: CGFloat?
        let mote: MotionSpec.Mote

        /// Centro en reposo dentro de `size`.
        func restCenter(in size: CGSize) -> CGPoint {
            let s = mote.size
            let x = left.map { size.width * $0 + s / 2 } ?? (size.width * (1 - (right ?? 0)) - s / 2)
            return CGPoint(x: x, y: size.height * top + s / 2)
        }
    }

    /// `top-[18%] left-[22%] w-3 h-3 bg-secondary-fixed shadow-[0_0_14px_rgba(255,220,198,0.95)] blur-[0.5px] anim-float-1` …
    static let specs: [Spec] = [
        Spec(id: 0, top: 0.18, left: 0.22, right: nil,
             mote: .init(id: 0, size: 12, fill: MotionRGBA(hex: 0xFFDCC6), blur: 0.5,
                         glow: ShadowSpec(MotionRGBA(255, 220, 198, 0.95), blur: 14), left: 0, bottom: 0,
                         clock: AnimationClock(duration: 7))),
        Spec(id: 1, top: 0.35, left: nil, right: 0.16,
             mote: .init(id: 1, size: 10, fill: MotionRGBA(hex: 0xBDECDC), blur: 0.5,
                         glow: ShadowSpec(MotionRGBA(189, 236, 220, 0.9), blur: 16), left: 0, bottom: 0,
                         clock: AnimationClock(duration: 8.5))),
        Spec(id: 2, top: 0.62, left: 0.18, right: nil,
             mote: .init(id: 2, size: 14, fill: MotionRGBA(hex: 0xBCEFC7), blur: 0.5,
                         glow: ShadowSpec(MotionRGBA(188, 239, 199, 0.85), blur: 15), left: 0, bottom: 0,
                         clock: AnimationClock(duration: 6.5))),
        Spec(id: 3, top: 0.78, left: nil, right: 0.25,
             mote: .init(id: 3, size: 8, fill: MotionRGBA(hex: 0xFD933F), blur: 0.5,
                         glow: ShadowSpec(MotionRGBA(253, 147, 63, 0.9), blur: 12), left: 0, bottom: 0,
                         clock: AnimationClock(duration: 9))),
        Spec(id: 4, top: 0.48, left: 0.36, right: nil,
             mote: .init(id: 4, size: 6, fill: MotionRGBA(hex: 0xFFFFFF), blur: 0,
                         glow: ShadowSpec(MotionRGBA(hex: 0xFFFFFF), blur: 10), left: 0, bottom: 0,
                         clock: AnimationClock(duration: 8.5, delay: 1))),
    ]

    /// Recorrido de la flotación del visor (M20).
    static let travel = CSSKeyframes<CGPoint>([(0, .zero), (1, CGPoint(x: 8, y: -40))], curve: .easeOut)
    /// Distancia mínima entre una mota (con su halo) y una cuenta de color.
    static let beadClearance: CGFloat = 8

    /// Centro y opacidad de una mota a `time` s en un visor de `size`.
    static func frame(of spec: Spec, at time: Double, in size: CGSize) -> MoteFrame {
        let rest = spec.restCenter(in: size)
        guard let p = spec.mote.clock.progress(at: time) else { return MoteFrame(center: rest, opacity: 0) }
        let d = travel.value(at: p)
        return MoteFrame(center: CGPoint(x: rest.x + d.x, y: rest.y + d.y), opacity: MotionSpec.moteOpacity.value(at: p))
    }

    /// Centros de las cuentas de color (pt, espacio de esta capa) que las motas no pisan.
    var beadCenters: [CGPoint] = []
    var beadDiameter: CGFloat = Sizes.pinBead
    /// false = se desvanecen (150 ms) y su reloj se pausa.
    var isActive: Bool = true

    @Environment(\.ambientMotionEnabled) private var parentEnabled

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            AmbientTimeline { time in
                if let time {
                    ZStack(alignment: .topLeading) {
                        ForEach(Self.specs) { spec in
                            let f = Self.frame(of: spec, at: time, in: size)
                            MoteSprite(mote: spec.mote)
                                .opacity(f.opacity)
                                .position(f.center)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
            }
            .ambientMotion(parentEnabled && isActive)
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                    ForEach(Array(beadCenters.enumerated()), id: \.offset) { _, c in
                        let d = beadDiameter + 2 * Self.beadClearance + 12
                        Circle()
                            .frame(width: d, height: d)
                            .position(c)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: MotionSpec.reducedFadeDuration), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Retículas

/// Esquinas de visor (E9): trazo 2 pt de 14 pt a 12 pt de cada esquina.
struct ExtractReticles: View {
    var color: Color = Theme.surface.opacity(0.6)
    var inset: CGFloat = 12
    var length: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let i = inset, l = length, w = size.width, h = size.height
            for (x, y, dx, dy) in [(i, i, 1.0, 1.0), (w - i, i, -1.0, 1.0), (i, h - i, 1.0, -1.0), (w - i, h - i, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x, y: y + dy * l))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + dx * l, y: y))
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Brote del CTA

/// Brote en línea (E30): tallo y dos hojas que se mecen (2,6 s, origen en la base) y una yema que
/// titila (0,18 s); resplandor `drop-shadow(0 0 6px rgba(253,147,63,0.8))`.
struct SproutGlyph: View {
    var ink: Color
    var bud: Color = Color(brand: 0xFFDCC6)
    var size: CGFloat = 20
    var animated: Bool = true

    struct Pose: Equatable {
        var rotation: Double = 0
        var offsetY: Double = 0
        var budOpacity: Double = 1
        var budScaleY: Double = 1
    }

    static func pose(at time: Double?) -> Pose {
        guard let time else { return Pose() }
        var pose = Pose()
        if let p = ExtractMotion.swayClock.progress(at: time) {
            pose.rotation = ExtractMotion.swayRotation.value(at: p)
            pose.offsetY = ExtractMotion.swayOffset.value(at: p)
        }
        if let w = ExtractMotion.wingClock.progress(at: time) {
            // La yema titila entre 0,7 y 0,3 sobre un punto base que no desaparece.
            pose.budOpacity = 0.3 + ExtractMotion.wingOpacity.value(at: w)
            pose.budScaleY = ExtractMotion.wingScaleY.value(at: w)
        }
        return pose
    }

    var body: some View {
        Group {
            if animated {
                AmbientTimeline { t in drawing(Self.pose(at: t)) }
            } else {
                drawing(Pose())
            }
        }
        .frame(width: size, height: size)
        .shadow(color: TailwindColor.secondaryContainer.opacity(0.8).color, radius: 3)
        .accessibilityHidden(true)
    }

    private func drawing(_ pose: Pose) -> some View {
        let ink = ink, bud = bud
        return Canvas { ctx, canvas in
            var c = ctx
            c.scaleBy(x: canvas.width / 24, y: canvas.width / 24)
            // Origen de la transformación: base del tallo (12, 21).
            c.translateBy(x: 12, y: 21)
            c.rotate(by: .degrees(pose.rotation))
            c.translateBy(x: -12, y: -21 + pose.offsetY)
            var stem = Path()
            stem.move(to: CGPoint(x: 12, y: 21))
            stem.addCurve(to: CGPoint(x: 12, y: 9.5), control1: CGPoint(x: 11.4, y: 17), control2: CGPoint(x: 12.6, y: 12.5))
            c.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            var left = Path()
            left.move(to: CGPoint(x: 11.8, y: 15))
            left.addQuadCurve(to: CGPoint(x: 4.2, y: 9.6), control: CGPoint(x: 5.2, y: 15.6))
            left.addQuadCurve(to: CGPoint(x: 11.8, y: 15), control: CGPoint(x: 10.8, y: 8.6))
            var right = Path()
            right.move(to: CGPoint(x: 12.2, y: 12.8))
            right.addQuadCurve(to: CGPoint(x: 19.8, y: 7.4), control: CGPoint(x: 18.8, y: 13.4))
            right.addQuadCurve(to: CGPoint(x: 12.2, y: 12.8), control: CGPoint(x: 13.2, y: 6.4))
            for leaf in [left, right] {
                c.fill(leaf, with: .color(ink.opacity(0.22)))
                c.stroke(leaf, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
            var budCtx = c
            budCtx.translateBy(x: 12, y: 6.6)
            budCtx.scaleBy(x: 1, y: pose.budScaleY)
            budCtx.fill(Path(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4)), with: .color(bud.opacity(min(1, pose.budOpacity))))
        }
    }
}

// MARK: - CTA luminoso

struct ExtractLuminousButton: View {
    enum Icon: Sendable, Equatable {
        case sprout
        case symbol(String)
    }

    let title: String
    var icon: Icon = .sprout
    var sparkle: Bool = true
    let action: () -> Void

    /// Ancho relativo de la banda de luz del barrido.
    nonisolated static let shimmerBand: CGFloat = 0.4

    /// Borde izquierdo de la banda para un desplazamiento del barrido de −1 (fuera por la izquierda) a 1
    /// (fuera por la derecha).
    nonisolated static func shimmerX(offset: Double, width: CGFloat, band: CGFloat) -> CGFloat {
        CGFloat((offset + 1) / 2) * (width + band) - band
    }

    var body: some View {
        Button(action: action) {
            ExtractLuminousLabel(title: title, icon: icon, sparkle: sparkle)
        }
        // `active:scale-[0.99]`.
        .buttonStyle(PressScaleButtonStyle(scale: 0.99))
    }
}

/// `label-lg` con `tracking-wide` (0,025 em = 0,35 pt) y `font-semibold`.
private let ctaRole = TextRole(id: "extract-cta", family: .sans, weight: .semibold, size: 14, lineHeight: 18,
                               tracking: 0.35, textStyle: .subheadline)

private struct ExtractLuminousLabel: View {
    let title: String
    let icon: ExtractLuminousButton.Icon
    let sparkle: Bool

    @Environment(\.solarButtonPressed) private var pressed
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = scheme == .dark ? Theme.onPrimary : Color(brand: 0xFFDCC6)
        HStack(spacing: Spacing.sm) {
            switch icon {
            case .sprout:
                SproutGlyph(ink: accent, bud: accent, animated: isEnabled)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .shadow(color: TailwindColor.secondaryContainer.opacity(0.8).color, radius: 3)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(ctaRole)
                .foregroundStyle(isEnabled ? Theme.onPrimary : Theme.onSurface.opacity(0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if sparkle {
                Text("✦")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .shadow(color: TailwindColor.secondaryContainer.color, radius: 2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.ctaVertical)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            ZStack {
                Capsule().fill(fill)
                if isEnabled {
                    // Barrido de luz (2,5 s, blanco 30 %) BAJO el texto: no le quita contraste. Banda del 40 %
                    // del ancho (sobre el musgo, una banda a todo el ancho se lee como un degradado de fondo).
                    AmbientTimeline { t in
                        if let x = ShimmerSweepModifier<Capsule>.offset(at: t) {
                            GeometryReader { proxy in
                                let band = proxy.size.width * ExtractLuminousButton.shimmerBand
                                LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                       .init(color: .white.opacity(MotionSpec.shimmerPeakOpacity), location: 0.5),
                                                       .init(color: .white.opacity(0), location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: band, height: proxy.size.height)
                                    .offset(x: ExtractLuminousButton.shimmerX(offset: x, width: proxy.size.width, band: band))
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .modifier(CTAHalo(active: isEnabled))
        }
        .contentShape(Capsule())
    }

    private var fill: Color {
        guard isEnabled else { return Theme.onSurface.opacity(0.12) }
        // `hover:bg-primary-container` mientras se pulsa (en oscuro, musgo claro un punto más apagado).
        return pressed ? Color(light: 0x2D5A3C, dark: 0x8FC39C) : Theme.primary
    }
}

private struct CTAHalo: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.warmShadow(.extractCTA, in: Capsule()) } else { content }
    }
}

// MARK: - Secundario en píldora

/// E32: `flex-1 py-2.5 px-space-md rounded-full bg-surface-container text-primary font-label-md gap-1.5
/// shadow-sm active:scale-95` + icono 17 pt `text-secondary`.
struct ExtractPillButton: View {
    let title: String
    let systemImage: String
    var isDone: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isDone ? "checkmark" : systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDone ? Theme.primary : Theme.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(title).textRole(.labelMD).foregroundStyle(Theme.primary).lineLimit(1)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.buttonVertical)
            .frame(maxWidth: .infinity, minHeight: Sizes.minTouch)
            .background {
                Capsule().fill(Theme.container)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
    }
}

// MARK: - Tarjeta de prenda

/// E22–E25: `swatch-card p-space-sm rounded-xl` en pocillo neutro (blanco/gris, sin halos ni tintes):
/// bloque de color de 64 pt, rótulo «01 · 67 %» con «✦»/«✧» a la derecha, nombre de Wada, hex con
/// icono de copiar y «ΔE». Al pulsar: 0,98 y sombra neutra `0 6px 20px` negra 12 %.
struct ExtractGarmentCard: View {
    let index: Int
    let color: PaletteColor
    var isSelected: Bool = false
    var isCopied: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ExtractGarmentCardBody(index: index, color: color, isSelected: isSelected, isCopied: isCopied)
        }
        .buttonStyle(PressScaleButtonStyle(scale: MotionSpec.Press.wideScale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Copia el hex")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var parts = ["Color \(index)"]
        if let w = color.weight { parts.append("\(Int((w * 100).rounded())) por ciento") }
        if let name = color.name { parts.append(name) }
        parts.append(color.hex)
        if let de = color.deltaE { parts.append(DesignFormat.deltaE(de)) }
        return parts.joined(separator: ", ")
    }
}

private struct ExtractGarmentCardBody: View {
    let index: Int
    let color: PaletteColor
    let isSelected: Bool
    let isCopied: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.solarButtonPressed) private var pressed

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let blockShape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        let hairline = 1 / max(displayScale, 1)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            blockShape
                .fill(color.color)
                .overlay(SwatchHairline(shape: blockShape))
                .frame(height: Sizes.garmentBlock)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(eyebrow)
                        .textRole(.overline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ExtractPinTone.of(color).sparkle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.wellTextSecondary)
                        .accessibilityHidden(true)
                }
                Text(color.name ?? color.hex)
                    .textRole(.headlineSM)
                    .foregroundStyle(Theme.wellText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: Spacing.xs) {
                    Text(color.hex)
                        .textRole(.hex)
                        .foregroundStyle(Theme.wellTextSecondary)
                        .lineLimit(1)
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.wellTextSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if let de = color.deltaE {
                        Text(DesignFormat.deltaE(de))
                            .textRole(.labelSM)
                            .foregroundStyle(Theme.wellText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).fill(Theme.wellFillAlt))
                            .overlay(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                                .strokeBorder(Theme.wellEdge, lineWidth: hairline))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Spacing.sm)
        .background {
            shape.fill(Theme.wellFill)
                .shadow(color: .black.opacity(pressed ? 0.12 : 0.05), radius: pressed ? 10 : 1, x: 0, y: pressed ? 6 : 1)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.duration), value: pressed)
        }
        .overlay(shape.strokeBorder(Theme.wellEdge, lineWidth: hairline))
        .neutralZone(cornerRadius: Radius.card)
        .overlay { if isSelected { WellSelectionRing(shape: shape) } }
        .contentShape(shape)
    }

    private var eyebrow: String {
        let n = String(format: "%02d", index)
        guard let w = color.weight else { return n }
        return "\(n) · \(DesignFormat.percent(w))"
    }
}
