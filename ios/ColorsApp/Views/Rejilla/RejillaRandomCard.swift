// Tarjeta «Al azar» de la Rejilla con la fidelidad de la captura «la_rejilla» del ejemplo del
// usuario (docs/design/FIDELITY.md §5, filas R5–R21 y M2, M10–M13, M16):
//   · fondo `container` con E1+, orbe cálido de 160 pt con pulso arriba a la derecha, orbe verde
//     de 144 pt abajo a la izquierda, punto melocotón con ping y punto verde con pulso
//   · rótulo con estrella de ocho puntas que gira (8 s) y «✦», título y descripción al ~70 %
//   · reloj de sol (48 pt): disco con halo y filo de luz, aro discontinuo (10 s), aro exterior con
//     pulso y sol en trazo que gira +360° + [0, 180)° al barajar
//   · fichas en pocillo neutro que se aplastan a 0,4 y vuelven escalonadas (120 + 60·i ms, 500 ms)
//   · pie: punto de estado con ping + nombre + «Nº 255 · Bloqueada», y «Otra» musgo con halo,
//     barrido de luz, estrella girando (1 s) y «✦»; pulsar 0,95
//   · tras «Otra», dos ciclos de la respiración ámbar ↔ verde azulado (8 s)
// Zona neutra: los orbes se apagan en una banda de 16 pt por encima y por debajo del pocillo;
// las fichas son planas (sin sombra, halo, veladura ni escala al pulsar).
import SwiftUI

struct RejillaRandomCard: View {
    let comboId: Int
    let name: String
    let colors: [PaletteColor]
    let isUnlocked: Bool
    let isProposedName: Bool
    let total: Int
    var onShuffle: () -> Void
    var onOpen: (() -> Void)?

    @State private var dialRotation: Double = 0
    @State private var breathing = false
    @State private var breathTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Distancia mínima entre un lavado difuso y el borde del pocillo (DESIGN_SYSTEM.md §1.3).
    static let washClearance: CGFloat = 16
    /// Dos ciclos de la respiración de 4 s tras «Otra» (FIDELITY.md M2).
    static let breathDuration: Double = 2 * MotionSpec.glowPulseClock.duration
    /// Giro del sol al barajar: +360° más un extra en [0, 180) (FIDELITY.md M16).
    static func nextDialRotation(from current: Double, extra: Double) -> Double {
        current + 360 + min(max(extra, 0), 179.999)
    }

    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var statusText: String {
        var parts = [WadaDictionary.numberLabel(comboId), isUnlocked ? "En tu rejilla" : "Bloqueada"]
        if isProposedName { parts.append("nombre propuesto") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            heading
            tiles
                // El marco del pocillo llega al fondo en la misma pasada de maquetación (sin estado).
                .anchorPreference(key: RejillaWellAnchorKey.self, value: .bounds) { $0 }
                .padding(.top, Spacing.margin)
            footer
                // `mt-space-md` del ejemplo (12 pt).
                .padding(.top, Spacing.md)
        }
        .padding(Spacing.md)
        .backgroundPreferenceValue(RejillaWellAnchorKey.self) { anchor in
            GeometryReader { proxy in
                background(shape, wellFrame: anchor.map { proxy[$0] } ?? .zero)
            }
        }
        .overlay {
            if breathing {
                shape.fill(Color.clear)
                    .glowPulse(shape)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: comboId) { _, _ in didShuffle() }
        .onDisappear {
            // Fuera de pantalla no queda una respiración a medias al volver.
            breathTask?.cancel()
            breathing = false
        }
    }

    // MARK: Cabecera de la tarjeta

    private var heading: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RejillaEyebrow(title: "Al azar")
                Text("Deja que el sol elija tu combinación")
                    .textRole(.headlineSM)
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Una de las \(total) de Sanzo Wada para tu próxima prenda. Toca sus colores para abrirla.")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // `max-w-[70%]`: el reloj de sol ocupa la derecha.
            .padding(.trailing, isLarge ? 0 : Spacing.xl - Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isLarge {
                Button(action: onShuffle) {
                    RejillaSunDial(rotation: dialRotation)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressScale)
                .padding(.top, -Spacing.xs)
                .padding(.trailing, -Spacing.xs)
                // Misma acción que «Otra», que es el control accesible.
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Fichas

    @ViewBuilder private var tiles: some View {
        let content = RejillaShuffleTiles(comboId: comboId, colors: colors)
        if let onOpen {
            Button(action: onOpen) { content.contentShape(Rectangle()) }
                .buttonStyle(.solarPress)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(colors.count) colores: \(colors.compactMap(\.name).joined(separator: ", "))")
                .accessibilityHint("Abre la combinación")
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    // MARK: Pie

    @ViewBuilder private var footer: some View {
        let label = HStack(alignment: .center, spacing: 6) {
            RejillaStatusPing(color: isUnlocked ? Theme.primary : Theme.secondary)
                .padding(.horizontal, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .textRole(.labelMD)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(isLarge ? 3 : 1)
                    .truncationMode(.tail)
                    .id(comboId)
                    .transition(.opacity)
                Text(statusText)
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(isLarge ? 3 : 1)
            }
            .animation(.easeOut(duration: reduceMotion ? MotionSpec.reducedFadeDuration : 0.3), value: comboId)
        }
        .accessibilityElement(children: .combine)
        if isLarge {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                label
                RejillaShuffleButton(action: onShuffle)
            }
        } else {
            HStack(alignment: .center, spacing: Spacing.sm) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                RejillaShuffleButton(action: onShuffle)
                    .fixedSize()
            }
        }
    }

    // MARK: Fondo con luces

    private func background(_ shape: RoundedRectangle, wellFrame: CGRect) -> some View {
        ZStack {
            shape.fill(Theme.container).elevation(.restStrong)
            RejillaCardWashes(wellFrame: wellFrame, clearance: Self.washClearance)
                .clipShape(shape)
            lightDots
                .clipShape(shape)
        }
    }

    /// `top-3 right-16` (8 pt, ping, 70 %) y `bottom-8 left-20` (6 pt, pulso, 80 %).
    private var lightDots: some View {
        ZStack {
            RejillaGlowDot(color: Color(brand: RejillaLight.peach), size: 8, glowBlur: 8, opacity: 0.7, motion: .ping)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, Spacing.md)
                .padding(.trailing, 64)
            RejillaGlowDot(color: Color(brand: RejillaLight.mint), size: 6, glowBlur: 6, opacity: 0.8, motion: .pulse)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, Spacing.xl)
                .padding(.leading, 80)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Barajar

    private func didShuffle() {
        guard !reduceMotion else { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
            dialRotation = Self.nextDialRotation(from: dialRotation, extra: Double.random(in: 0..<180))
        }
        breathTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) { breathing = true }
        breathTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.breathDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { breathing = false }
        }
    }
}

// MARK: - Lavados difusos

/// Marco del pocillo de fichas dentro de la tarjeta (para apagar los lavados a su alrededor).
struct RejillaWellAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Orbe cálido (`-right-8 -top-8 w-40 h-40 bg-secondary-container/30 blur-2xl animate-pulse`) y orbe
/// verde (`-left-6 -bottom-6 w-36 h-36 bg-primary-fixed/40 blur-xl`). Se apagan en la banda del
/// pocillo ampliada `clearance` pt arriba y abajo, con un fundido de 40 pt fuera de ella.
/// El desenfoque gaussiano del disco se dibuja como degradado radial con su perfil (σ = 40 y 24 pt):
/// `blur` sobre un color al 30 % produce anillos visibles (8 bits por canal).
struct RejillaCardWashes: View {
    var wellFrame: CGRect
    var clearance: CGFloat = 16

    @Environment(\.colorScheme) private var scheme

    /// Opacidad relativa de un disco de radio `r` desenfocado con σ = `sigma` a `d` pt del centro:
    /// perfil de borde ½·erfc((d − r) / σ√2), acotado por el valor del centro 1 − e^(−r²/2σ²).
    static func blurredDiscProfile(radius r: Double, sigma: Double, distance d: Double) -> Double {
        guard sigma > 0 else { return d <= r ? 1 : 0 }
        let center = 1 - exp(-(r * r) / (2 * sigma * sigma))
        let edge = 0.5 * erfc((d - r) / (sigma * 2.0.squareRoot()))
        return min(center, edge)
    }

    private static func stops(color: UInt32, alpha: Double, radius: Double, sigma: Double, extent: Double) -> [Gradient.Stop] {
        (0...8).map { i in
            let t = Double(i) / 8
            let a = alpha * blurredDiscProfile(radius: radius, sigma: sigma, distance: t * extent)
            return .init(color: Color(brand: color, opacity: a), location: t)
        }
    }

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            ZStack {
                RadialGradient(stops: Self.stops(color: RejillaLight.solarOrange, alpha: dark ? 0.16 : 0.3,
                                                 radius: 80, sigma: 40, extent: 170),
                               center: .center, startRadius: 0, endRadius: 170)
                    .frame(width: 340, height: 340)
                    .pulse()
                    .position(x: geo.size.width + 32 - 80, y: -32 + 80)
                RadialGradient(stops: Self.stops(color: dark ? 0x2D5A3C : RejillaLight.mint, alpha: dark ? 0.45 : 0.4,
                                                 radius: 72, sigma: 24, extent: 130),
                               center: .center, startRadius: 0, endRadius: 130)
                    .frame(width: 260, height: 260)
                    .position(x: -24 + 72, y: geo.size.height + 24 - 72)
            }
        }
        .mask { RejillaWellBandMask(wellFrame: wellFrame, clearance: clearance, feather: 40) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Máscara opaca salvo en la banda horizontal del pocillo ± `clearance` (sin pocillo medido: opaca).
struct RejillaWellBandMask: View {
    var wellFrame: CGRect
    var clearance: CGFloat
    var feather: CGFloat = 20

    /// Límites de la banda sin luz dentro de una altura `height` (tests).
    static func band(wellFrame: CGRect, clearance: CGFloat, height: CGFloat) -> ClosedRange<CGFloat>? {
        guard wellFrame.height > 0, height > 0 else { return nil }
        let top = min(max(0, wellFrame.minY - clearance), height)
        let bottom = min(max(top, wellFrame.maxY + clearance), height)
        return top...bottom
    }

    var body: some View {
        GeometryReader { geo in
            if let band = Self.band(wellFrame: wellFrame, clearance: clearance, height: geo.size.height) {
                VStack(spacing: 0) {
                    fade(height: band.lowerBound, opaqueAtTop: true)
                    Color.clear.frame(height: band.upperBound - band.lowerBound)
                    fade(height: geo.size.height - band.upperBound, opaqueAtTop: false)
                }
            } else {
                Rectangle()
            }
        }
    }

    @ViewBuilder private func fade(height: CGFloat, opaqueAtTop: Bool) -> some View {
        let f = height > 0 ? min(1, feather / height) : 1
        LinearGradient(stops: opaqueAtTop
                       ? [.init(color: .black, location: 0), .init(color: .black, location: 1 - f), .init(color: .clear, location: 1)]
                       : [.init(color: .clear, location: 0), .init(color: .black, location: f), .init(color: .black, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: max(0, height))
    }
}

// MARK: - Fichas que se barajan

/// Fichas planas de la combinación en un pocillo neutro (6 pt de relleno y de separación, radio 8,
/// 48 pt de alto). Al cambiar `comboId` reproducen `generateRandomPalette()` del ejemplo: todas
/// pasan a `scaleY(0.4)` y, a los 120 + 60·i ms, cada una toma su color nuevo y vuelve a 1, con la
/// transición de 500 ms `cubic-bezier(0.4, 0, 0.2, 1)`. Con «Reducir movimiento»: fundido de 150 ms.
struct RejillaShuffleTiles: View {
    let comboId: Int
    let colors: [PaletteColor]
    var height: CGFloat = Sizes.randomTile

    @State private var shown: [PaletteColor]
    @State private var squash: [CGFloat]
    @State private var task: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    static let squashScale: CGFloat = 0.4
    static let duration: Double = 0.5

    /// Instante (s) en que la ficha `index` toma su color nuevo y vuelve a escala 1.
    static func swapDelay(index: Int) -> Double { 0.12 + 0.06 * Double(max(index, 0)) }

    static var curve: Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }

    init(comboId: Int, colors: [PaletteColor], height: CGFloat = Sizes.randomTile) {
        self.comboId = comboId
        self.colors = colors
        self.height = height
        _shown = State(initialValue: colors)
        _squash = State(initialValue: Array(repeating: 1, count: colors.count))
    }

    var body: some View {
        SwatchWell(padding: Spacing.wellPaddingCompact, cornerRadius: Radius.block) {
            HStack(spacing: Spacing.wellPaddingCompact) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, c in
                    let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                    shape.fill(c.color)
                        .overlay(SwatchHairline(shape: shape))
                        .scaleEffect(x: 1, y: squash.indices.contains(i) ? squash[i] : 1, anchor: .center)
                        .accessibilityElement()
                        .accessibilityLabel(DesignFormat.accessibilityLabel(c, position: i, total: shown.count))
                }
            }
            .frame(height: height)
        }
        .onChange(of: comboId) { _, _ in run(to: colors) }
        .onDisappear {
            // Un barajado interrumpido (se desplaza fuera) termina en su estado final, sin fichas aplastadas.
            task?.cancel()
            if shown != colors || squash.contains(where: { $0 != 1 }) {
                shown = colors
                squash = Array(repeating: 1, count: colors.count)
            }
        }
    }

    private func run(to target: [PaletteColor]) {
        task?.cancel()
        if systemReduceMotion || forcedReduceMotion {
            withAnimation(.easeOut(duration: MotionSpec.reducedFadeDuration)) {
                shown = target
                squash = Array(repeating: 1, count: target.count)
            }
            return
        }
        let sameCount = target.count == shown.count
        withAnimation(Self.curve) {
            squash = Array(repeating: Self.squashScale, count: shown.count)
        }
        task = Task { @MainActor in
            var elapsed = 0.0
            func wait(until t: Double) async -> Bool {
                if t > elapsed { try? await Task.sleep(for: .seconds(t - elapsed)) }
                elapsed = max(elapsed, t)
                return !Task.isCancelled
            }
            if sameCount {
                for i in target.indices {
                    guard await wait(until: Self.swapDelay(index: i)) else { return }
                    withAnimation(Self.curve) {
                        if shown.indices.contains(i) { shown[i] = target[i] }
                        if squash.indices.contains(i) { squash[i] = 1 }
                    }
                }
            } else {
                // Cambia el número de fichas: el juego nuevo entra aplastado y crece escalonado.
                guard await wait(until: Self.swapDelay(index: 0)) else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    shown = target
                    squash = Array(repeating: Self.squashScale, count: target.count)
                }
                for i in target.indices {
                    guard await wait(until: Self.swapDelay(index: i)) else { return }
                    withAnimation(Self.curve) {
                        if squash.indices.contains(i) { squash[i] = 1 }
                    }
                }
            }
        }
    }
}

// MARK: - Punto de estado y botón «Otra»

/// Punto de estado de 8 pt con `animate-ping` exacto (el propio punto crece ×2 y se apaga) sobre un
/// punto fijo tenue para que se lea también en reposo.
struct RejillaStatusPing: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35))
            Circle().fill(color).pingDot()
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}

/// «Otra» (`#surprise-btn`): cápsula musgo `px-4 py-2`, halo `0 0 14px rgba(20,66,38,0.4)` +
/// `0 2px 4px rgba(0,0,0,0.15)`, barrido de luz blanca al 20 % bajo el texto, estrella que gira
/// (`animate-spin`, 1 s) y «✦»; `active:scale-95`.
struct RejillaShuffleButton: View {
    var title: String = "Otra"
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(light: RejillaLight.peach, dark: 0x713700))
                    .spinning(duration: MotionSpec.Spin.tailwindDefault)
                    .accessibilityHidden(true)
                Text(title)
                    .textRole(.labelMD)
                    .lineLimit(1)
                Text("✦")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, Spacing.margin)
            .padding(.vertical, Spacing.sm)
            .background {
                Capsule()
                    .fill(Theme.primary)
                    .shimmerSweep(Capsule(), peakOpacity: 0.2)
            }
            .background { OuterGlow(shape: Capsule(), shadows: glow) }
            .frame(minHeight: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Otra combinación al azar")
        .accessibilityIdentifier("rejilla.random.shuffle")
    }

    private var glow: [ShadowSpec] {
        let moss = scheme == .dark ? MotionRGBA(hex: RejillaLight.mossNight, alpha: 0.3) : MotionRGBA(hex: RejillaLight.moss, alpha: 0.4)
        return [ShadowSpec(moss, blur: 14), ShadowSpec(MotionRGBA(0, 0, 0, scheme == .dark ? 0.3 : 0.15), blur: 4, y: 2)]
    }
}
