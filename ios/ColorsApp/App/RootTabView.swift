// Pestañas del MVP (PLAN §7): Hoy, Rejilla, Explorar, Ajustes. Cada pestaña
// vive en su fichero bajo Views/ y la sustituyen los agentes de pantalla.
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case hoy, rejilla, explorar, ajustes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy: "Hoy"
        case .rejilla: "Rejilla"
        case .explorar: "Explorar"
        case .ajustes: "Ajustes"
        }
    }

    var systemImage: String {
        switch self {
        case .hoy: "sun.max"
        case .rejilla: "square.grid.3x3"
        case .explorar: "book"
        case .ajustes: "gearshape"
        }
    }
}

/// Acción para cambiar de pestaña desde una vista hija (p. ej. "Ver rejilla" del escaneo en Hoy).
struct SelectTabAction {
    let action: @MainActor (AppTab) -> Void

    @MainActor
    func callAsFunction(_ tab: AppTab) { action(tab) }
}

private struct SelectTabKey: EnvironmentKey {
    static var defaultValue: SelectTabAction { SelectTabAction(action: { _ in }) }
}

extension EnvironmentValues {
    var selectTab: SelectTabAction {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }
}

struct RootTabView: View {
    @State private var selection: AppTab = .hoy

    var body: some View {
        TabView(selection: $selection) {
            HoyView()
                .tabItem { Label(AppTab.hoy.title, systemImage: AppTab.hoy.systemImage) }
                .tag(AppTab.hoy)
            RejillaView()
                .tabItem { Label(AppTab.rejilla.title, systemImage: AppTab.rejilla.systemImage) }
                .tag(AppTab.rejilla)
            ExplorarView()
                .tabItem { Label(AppTab.explorar.title, systemImage: AppTab.explorar.systemImage) }
                .tag(AppTab.explorar)
            AjustesView()
                .tabItem { Label(AppTab.ajustes.title, systemImage: AppTab.ajustes.systemImage) }
                .tag(AppTab.ajustes)
        }
        .accessibilityIdentifier("root.tabs")
        .environment(\.selectTab, SelectTabAction(action: { tab in selection = tab }))
    }
}

/// Contenido provisional de una pestaña ("en construcción").
struct PlaceholderTabView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title.bold())
                Text("En construcción")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(title)
        }
    }
}
