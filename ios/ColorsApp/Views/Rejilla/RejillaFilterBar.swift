// Chips de la Rejilla (docs/design/DESIGN_SYSTEM.md §5.3; FIDELITY.md §5 R22): grupo de tamaño
// (Todas, 2, 3 y 4 colores) · separador · grupo de estado (Desbloqueadas, Bloqueadas; se
// desactivan al tocarlos otra vez). Chips compactos del ejemplo (`px-3.5 py-1.5 label-sm`, reposo
// `surface-container`); el activo, musgo con el halo `0 0 12px rgba(45,90,60,0.3)`, filo
// `emerald-400/30` e icono con pulso. Debajo, «12 de 120 desbloqueadas» con su barra de progreso.
import SwiftUI

struct RejillaFilterBar: View {
    @Binding var size: Int?
    @Binding var status: RejillaModel.StatusFilter?

    @Environment(\.displayScale) private var displayScale

    static let sizes = [2, 3, 4]

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                RejillaChip(title: "Todas", isSelected: size == nil) { size = nil }
                    .accessibilityIdentifier("rejilla.filter.all")
                ForEach(Self.sizes, id: \.self) { n in
                    RejillaChip(title: "\(n) colores", isSelected: size == n) { size = size == n ? nil : n }
                        .accessibilityIdentifier("rejilla.filter.size\(n)")
                }
                Rectangle()
                    .fill(Theme.outlineVariant)
                    .frame(width: max(1 / max(displayScale, 1), 1), height: 20)
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)
                ForEach(RejillaModel.StatusFilter.allCases, id: \.self) { s in
                    RejillaChip(title: s.title, systemImage: s == .unlocked ? "checkmark.seal.fill" : "lock.fill",
                               isSelected: status == s) { status = status == s ? nil : s }
                        .accessibilityIdentifier("rejilla.filter.\(s.rawValue)")
                        .id("status-\(s.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.margin)
            // `py-1` + margen para el halo del chip activo (no se recorta en el carrusel).
            .padding(.vertical, Spacing.xs)
        }
        // El grupo de estado queda fuera de pantalla en un iPhone: si está activo, se muestra.
        .modifier(RevealOnAppear(active: status != nil) { reveal(status, proxy: proxy, animated: false) })
        .onChange(of: status) { _, new in reveal(new, proxy: proxy, animated: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rejilla.filter")
    }

    private func reveal(_ status: RejillaModel.StatusFilter?, proxy: ScrollViewProxy, animated: Bool) {
        guard let status else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("status-\(status.rawValue)", anchor: .trailing) }
            } else {
                proxy.scrollTo("status-\(status.rawValue)", anchor: .trailing)
            }
        }
    }
}

/// `onAppear` solo cuando hace falta (sin modificadores de ciclo de vida en capturas con ImageRenderer).
private struct RevealOnAppear: ViewModifier {
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if active {
            content.onAppear(perform: action)
        } else {
            content
        }
    }
}

/// Chip compacto de la Rejilla: `label-sm` (11 pt), relleno 14 × 6, reposo `container`; activo
/// `primary` con halo musgo, filo esmeralda al 30 % e icono con pulso. Área táctil de 36 pt de alto.
struct RejillaChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Color(light: 0xFBBF24, dark: 0x0B3A1D) : Theme.onSurfaceVariant)
                        .modifier(RejillaChipIconPulse(active: isSelected))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .textRole(.labelSM)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.onPrimary : Theme.onSurfaceVariant)
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.chipVertical)
            .background { Capsule().fill(isSelected ? Theme.primary : Theme.container) }
            .modifier(RejillaChipLight(active: isSelected))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RejillaChipLight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(Capsule().strokeBorder(MotionSpec.activeChipBorder.color, lineWidth: 1).allowsHitTesting(false))
                .warmShadow(.activeChip, in: Capsule())
        } else {
            content
        }
    }
}

private struct RejillaChipIconPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.pulse() } else { content }
    }
}

/// «12 de 120 desbloqueadas» + barra musgo sobre carril `containerHighest`. Densidad del ejemplo:
/// rótulo `label-sm` (11 pt) y carril de 4 pt (el ejemplo no tiene esta fila: cuanto menos ocupe,
/// más tarjetas caben en la primera pantalla).
struct RejillaProgressRow: View {
    let text: String
    let value: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .textRole(.labelSM)
                .monospacedDigit()
                .foregroundStyle(Theme.onSurfaceVariant)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.containerHighest)
                    Capsule()
                        .fill(Theme.primary)
                        .frame(width: total > 0 && value > 0 ? max(6, geo.size.width * CGFloat(min(value, total)) / CGFloat(total)) : 0)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("rejilla.filter.counter")
    }
}
