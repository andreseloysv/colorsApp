// Resultado empujado en una pila de navegación (p. ej. «Abrir en Extraer» del Feed, que
// reanaliza una foto guardada): el mismo contenido que el estado de resultado de la
// pestaña Extraer (`ExtractResultContent`: foto con alfileres, recorte, personas, colores
// de la ropa, top-3, voto, desbloqueo, guardar, copiar hex, capas y tarjeta) con la barra
// la cabecera de marca de las pantallas secundarias (FIDELITY.md §7.5) y el visor de capas a
// pantalla completa.
import SwiftUI
import UIKit
import SubjectKit

struct ResultView: View {
    @StateObject private var model: ResultViewModel
    @EnvironmentObject private var env: AppEnvironment
    @State private var layersRoute: LayersRoute?
    @State private var toast: String?

    init(model: ResultViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            ExtractResultContent(model: model, onOpenLayers: { layersRoute = LayersRoute(outcome: $0) }, toast: $toast)
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .secondaryAmbience()
        .safeAreaInset(edge: .top, spacing: 0) {
            // Cabecera de marca de las pantallas secundarias (FIDELITY.md §7.5) en vez de la barra
            // del sistema: el nombre de la combinación lo canta el contenido, no el título.
            SecondaryHeader(section: "Resultado", identifier: "resultado.header")
        }
        .modifier(ExtractToastOverlay(toast: toast))
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $layersRoute) { route in
            LayersInspectorView(model: LayersInspectorModel(outcome: route.outcome, dictionary: env.dictionary),
                                initialLayer: route.initialLayer)
        }
    }
}
