// Buscador fijo de la Rejilla con la densidad del ejemplo (FIDELITY.md §5 R4): barra
// `sticky top-16 py-space-sm bg-surface/90 backdrop-blur-md` y campo
// `bg-surface-container-lowest` (`card`: blanco / #1C1913) `rounded-full px-space-md py-2.5` con sombra E1, lupa de 20 pt
// `secondary`, texto `body-sm` (placeholder `onSurfaceVariant` por AA) y botón de ajustes de 18 pt
// (`tune` → «Buscar por color»).
import SwiftUI

struct RejillaSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var onFilter: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.onSurfaceVariant))
                .textRole(.bodySM)
                .foregroundStyle(Theme.onSurface)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Buscar combinaciones")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Borrar búsqueda")
            }
            if let onFilter {
                Button(action: onFilter) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Buscar por color")
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xs + 2)
        .padding(.vertical, 5)
        .frame(minHeight: 40)
        .background { Capsule().fill(Theme.card).elevation(.rest) }
        .overlay { if focused { Capsule().strokeBorder(Theme.primary.opacity(0.4), lineWidth: 1) } }
    }
}

/// Fondo de la barra fija: pergamino al 90 % sobre el material del sistema (`backdrop-blur-md`).
struct RejillaStickyBarBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.surface.opacity(0.9))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
