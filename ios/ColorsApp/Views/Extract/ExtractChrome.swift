// Cabecera y luces del marco de Extraer (docs/design/FIDELITY.md §2.2 y §4 E1–E4, E10–E11,
// E17–E18, E34; ejemplo del usuario `clothing_extractor…/code.html`):
//   - `ExtractHeader`: cabecera esmerilada de Extraer (`bg-surface/85 backdrop-blur-xl
//     shadow-[0_1px_8px_rgba(0,0,0,0.04)]`, sin filo), emblema sin resplandor y palabra «ChromaSol»
//     con el rótulo «EXTRAER» (`ChromaSolLogo` + `ChromaSolWordmark`), el sol en disco con aro de
//     ping y flotación (acción contextual real) y el avatar del jardín con anillo, filo de luz e
//     insignia «✦» solo si hay combinaciones nuevas desde la última visita al Jardín.
//   - `SunSpiritGlyph`: sol genérico con carita dibujado de nuevo (8 rayos, núcleo, ojos,
//     mejillas y sonrisa), en `Canvas`.
//   - `ExtractHUDChip`: píldora sobre la foto `bg-surface/85 backdrop-blur-md shadow-sm`.
// Todo es marco: ningún color de datos. Movimiento con `AmbientTimeline` (≤ 30 fps, pausa en
// segundo plano, fuera de pantalla y con `.ambientMotion(false)`; quieto con «Reducir movimiento»).
import SwiftUI

// MARK: - Tiempos propios de Extraer

enum ExtractMotion {
    /// Flotación suave (FIDELITY M19, `anim-spirit-bob` sin definir en el ejemplo): `translateY`
    /// 0 → −1,5 → 0 en 3,2 s `ease-in-out` (los tiempos del cabeceo del Feed, sin rotación).
    static let bobClock = AnimationClock(duration: 3.2)
    static let bobOffset = CSSKeyframes<Double>([(0, 0), (0.5, -1.5), (1, 0)], curve: .easeInOut)

    /// Desplazamiento vertical de la flotación en `time` (nil = reposo).
    static func bob(at time: Double?) -> CGFloat {
        guard let time, let p = bobClock.progress(at: time) else { return 0 }
        return CGFloat(bobOffset.value(at: p))
    }

    /// Vaivén del brote (`sprout-sway 2.6s ease-in-out`, origen abajo al centro).
    static let swayClock = AnimationClock(duration: 2.6)
    static let swayRotation = CSSKeyframes<Double>([(0, 0), (0.35, 6), (0.75, -5), (1, 0)], curve: .easeInOut)
    static let swayOffset = CSSKeyframes<Double>([(0, 0), (0.35, -1), (0.75, 0.5), (1, 0)], curve: .easeInOut)

    /// Aleteo (`wing-vibrate 0.18s linear`): opacidad 0,7 → 0,3 → 0,7 y escala Y 1 → 0,55 → 1.
    static let wingClock = AnimationClock(duration: 0.18)
    static let wingOpacity = CSSKeyframes<Double>([(0, 0.7), (0.5, 0.3), (1, 0.7)], curve: .linear)
    static let wingScaleY = CSSKeyframes<Double>([(0, 1), (0.5, 0.55), (1, 1)], curve: .linear)

    /// Duración de los toasts de Extraer (`setTimeout(…, 2400)`).
    static let toastSeconds: Double = 2.4
}

// MARK: - Sol con carita

/// Sol genérico con carita (viewBox 24): 8 rayos (largos y cortos), núcleo, ojos ovalados,
/// mejillas y sonrisa. Colores de ilustración del marco.
struct SunSpiritGlyph: View {
    var core: Color = Color(brand: 0x954A00)
    var rays: Color = Color(brand: 0x954A00)
    var face: Color = Color(brand: 0xFFDCC6)
    var rayWidth: CGFloat = 1.8
    var coreRadius: CGFloat = 4.5

    var body: some View {
        let core = core, ray = rays, faceColor = face, width = rayWidth, r = coreRadius
        Canvas { ctx, size in
            var c = ctx
            c.scaleBy(x: size.width / 24, y: size.width / 24)
            var path = Path()
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4 - .pi / 2
                let long = i % 2 == 0
                let r0 = long ? 7.2 : 6.9
                let r1 = long ? 10.4 : 9.0
                path.move(to: CGPoint(x: 12 + cos(angle) * r0, y: 12 + sin(angle) * r0))
                path.addLine(to: CGPoint(x: 12 + cos(angle) * r1, y: 12 + sin(angle) * r1))
            }
            c.stroke(path, with: .color(ray), style: StrokeStyle(lineWidth: width, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: 12 - r, y: 12 - r, width: 2 * r, height: 2 * r)), with: .color(core))
            let k = r / 4.5
            for dx in [-1.55, 1.55] {
                c.fill(Path(ellipseIn: CGRect(x: 12 + dx * k - 0.62 * k, y: 12 - 0.8 * k - 0.8 * k, width: 1.24 * k, height: 1.6 * k)),
                       with: .color(faceColor))
            }
            for dx in [-2.75, 2.75] {
                c.fill(Path(ellipseIn: CGRect(x: 12 + dx * k - 0.65 * k, y: 12.9 * 1 - 0.45 * k + (k - 1) * 0.9,
                                              width: 1.3 * k, height: 0.9 * k)),
                       with: .color(Color(brand: 0xF87171, opacity: 0.55)))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: 12 - 1.1 * k, y: 12 + 1.35 * k))
            smile.addQuadCurve(to: CGPoint(x: 12 + 1.1 * k, y: 12 + 1.35 * k), control: CGPoint(x: 12, y: 12 + 2.35 * k))
            c.stroke(smile, with: .color(faceColor), style: StrokeStyle(lineWidth: 0.8 * k, lineCap: .round))
        }
    }
}

/// Sol del marco listo para usar: dibujo + resplandor `drop-shadow` + flotación opcional.
struct SunSpiritMark: View {
    var size: CGFloat = 24
    var core: Color = Color(brand: 0x954A00)
    var rays: Color = Color(brand: 0x954A00)
    var face: Color = Color(brand: 0xFFDCC6)
    var rayWidth: CGFloat = 1.8
    var coreRadius: CGFloat = 4.5
    /// Resplandor `drop-shadow(0 0 Bpx rgba(253,147,63,α))`.
    var glow: ShadowSpec? = ShadowSpec(TailwindColor.secondaryContainer.opacity(0.8), blur: 6)
    var bobs: Bool = true

    var body: some View {
        let glyph = SunSpiritGlyph(core: core, rays: rays, face: face, rayWidth: rayWidth, coreRadius: coreRadius)
            .frame(width: size, height: size)
            .shadow(color: glow?.color.color ?? .clear, radius: glow?.radius ?? 0)
        Group {
            if bobs {
                AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
                    glyph.offset(y: ExtractMotion.bob(at: t) * size / 24)
                }
            } else {
                glyph
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Cabecera

struct ExtractHeader: View {
    /// true = estado de resultado («Nueva foto»); false = captura («Escanear carrete»).
    let isResult: Bool
    let onSun: () -> Void
    let onAvatar: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    /// Recuento de combinaciones que el Jardín vio por última vez (lo escribe el Jardín al abrirse).
    @AppStorage(ExtractHeader.lastSeenUnlockKey) private var lastSeenUnlocks = 0
    @State private var unlockCount = 0

    nonisolated static let lastSeenUnlockKey = "jardin.lastSeenUnlockCount"

    /// Cabecera de Extraer del ejemplo: pergamino al 85 % y sombra negra `0 1px 8px` al 4 %, sin filo.
    nonisolated static let bar = MotionSpec.FrostedBar(tintOpacity: 0.85,
                                                       shadow: ShadowSpec(MotionRGBA(0, 0, 0, 0.04), blur: 8, y: 1),
                                                       hairline: MotionRGBA(0, 0, 0, 0))

    /// Combinaciones nuevas desde la última visita al Jardín (0 = sin insignia).
    nonisolated static func newUnlocks(count: Int, lastSeen: Int) -> Int { max(0, count - max(0, lastSeen)) }

    var body: some View {
        let fresh = Self.newUnlocks(count: unlockCount, lastSeen: lastSeenUnlocks)
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                // `img.h-8.w-auto` sin `drop-shadow` (solo el Feed lo lleva) y sin punto con ping.
                ChromaSolLogo(size: Sizes.brandMark, glow: false)
                ChromaSolWordmark(section: "EXTRAER", showsDot: false, animated: false)
            }
            Spacer(minLength: Spacing.sm)
            ExtractSunSpiritButton(actionSymbol: isResult ? "arrow.counterclockwise" : "photo.stack",
                                   accessibilityLabel: isResult ? "Nueva foto" : "Escanear carrete",
                                   action: onSun)
                .accessibilityIdentifier("extraer.header.sun")
            Button(action: onAvatar) {
                ExtractGardenAvatar(newUnlocks: fresh)
                    .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel(fresh > 0 ? "Tu jardín, \(fresh) \(fresh == 1 ? "combinación nueva" : "combinaciones nuevas")" : "Tu jardín")
            .accessibilityIdentifier("extraer.header.avatar")
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { FrostedBarBackground(spec: Self.bar, hairlineEdge: .bottom) }
        .task {
            do {
                for try await count in env.unlocks.observeCount() { unlockCount = count }
            } catch {
                unlockCount = 0
            }
        }
    }
}

/// Sol en disco de la cabecera (E3): `button.w-11.h-11 active:scale-95` + aro `inset-1`
/// `bg-secondary-container/20 animate-ping opacity-40` + disco `inset-1.5 bg-secondary-fixed
/// shadow-[0_0_12px_rgba(253,147,63,0.5)]` + sol 24 pt con flotación y `drop-shadow 6px` naranja 80 %.
/// Un glifo de 9 pt en la esquina indica la acción real.
struct ExtractSunSpiritButton: View {
    let actionSymbol: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ExtractSunDisc(diameter: 32)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(brand: 0x713700))
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color(brand: 0xFFF8EC)))
                        .overlay(Circle().strokeBorder(Color(brand: 0xFD933F, opacity: 0.45), lineWidth: 1))
                        .offset(x: 5, y: 5)
                        .accessibilityHidden(true)
                }
                .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Disco melocotón con halo naranja, aro de ping y el sol con carita (cabecera 32 pt, portada 64 pt).
struct ExtractSunDisc: View {
    var diameter: CGFloat = 32
    var pings: Bool = true

    var body: some View {
        let ring = diameter * 36 / 32
        ZStack {
            if pings {
                Circle()
                    .fill(Color(brand: 0xFD933F, opacity: 0.2))
                    .frame(width: ring, height: ring)
                    .pingDot()
                    .opacity(0.4)
            }
            Circle()
                .fill(Color(brand: 0xFFDCC6))
                .frame(width: diameter, height: diameter)
                .background {
                    OuterGlow(shape: Circle(), shadows: [ShadowSpec(TailwindColor.secondaryContainer.opacity(0.5), blur: 12 * diameter / 32)])
                }
            SunSpiritMark(size: diameter * 24 / 32,
                          glow: ShadowSpec(TailwindColor.secondaryContainer.opacity(0.8), blur: 6 * diameter / 32))
        }
        .frame(width: ring, height: ring)
        .accessibilityHidden(true)
    }
}

/// Avatar del jardín (E4): brote en maceta sobre musgo, placa `secondary-fixed` de 2 pt con filo de
/// luz interior, anillo `amber-300/60` e insignia «✦» 14 pt `secondary-container` (`shadow-sm`) solo
/// si hay combinaciones nuevas.
struct ExtractGardenAvatar: View {
    var newUnlocks: Int = 0
    var size: CGFloat = Sizes.avatar

    var body: some View {
        Circle()
            .fill(Tone.moss.badgeFill)
            .overlay {
                BrandTabIconFrame(kind: .jardin, pose: .rest, size: size * 0.72)
                    .offset(y: 1)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(2)
            .background(Circle().fill(Theme.secondaryFixed))
            .insetSunGlint(Circle())
            .overlay(Circle().strokeBorder(MotionSpec.headerAvatarRing.color, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if newUnlocks > 0 {
                    Circle()
                        .fill(Theme.secondaryContainer)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Text("✦").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(light: 0xFFFFFF, dark: 0xFFDCC6))
                        }
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                        .offset(x: 2, y: -2)
                        .accessibilityIdentifier("extraer.header.avatarBadge")
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Píldoras sobre la foto

/// Píldora del HUD (E10–E11): `px-space-sm py-1 rounded-full bg-surface/85 backdrop-blur-md shadow-sm`,
/// icono 13 pt y `label-sm`. `isOn` = conmutador activo (musgo).
struct ExtractHUDChip: View {
    let title: String
    var systemImage: String?
    var tint: Color = Theme.secondary
    var textColor: Color = Theme.onSurface
    var isOn: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.onPrimary : tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(.labelSM)
                .foregroundStyle(isOn ? Theme.onPrimary : textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.xs + 1)
        .background {
            if isOn {
                Capsule().fill(Theme.primary)
            } else {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Theme.surface.opacity(0.85))
                }
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Toast

/// Toast inferior de Extraer y Resultado (E34): luminoso (halo ámbar, filo e icono de destello que
/// gira 3 s), aparece subiendo 8 pt en 300 ms; con «Reducir movimiento», solo fundido.
struct ExtractToastOverlay: ViewModifier {
    let toast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                SolarToast(title: toast, systemImage: "sparkles", luminous: true)
                    .padding(.bottom, Spacing.lg + Sizes.tabBar)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    .accessibilityIdentifier("result.toast")
                    .allowsHitTesting(false)
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: toast)
    }
}
