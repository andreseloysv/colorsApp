// Punto de entrada de la app iOS. Sin red: el motor de color corre en el
// propio dispositivo vía el paquete local ColorEngine. Crea el
// AppEnvironment una vez y lo inyecta en el árbol de vistas.
// En DEBUG, los atajos `-uiScreen` que analizan una foto de ejemplo arrancan con una base de
// datos EN MEMORIA (como `feed-demo` y `jardin-demo`): sus análisis de muestra no deben
// aparecer luego en el Jardín ni en el Feed del usuario.
import SwiftUI

@main
struct ColorsAppApp: App {
    private let boot: Result<AppEnvironment, any Error>

    init() {
        boot = Result {
            #if DEBUG
            if DebugLaunch.requested?.analyzesFixture == true {
                // Base en memoria: la cosecha de ejemplo no ensucia los datos reales.
                return try AppEnvironment.forTesting()
            }
            #endif
            return try AppEnvironment.bootstrap()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let environment):
                RootTabView()
                    .environmentObject(environment)
                    .designSystemRoot()
            case .failure(let error):
                BootErrorView(message: String(describing: error))
            }
        }
    }
}

/// Pantalla de error de arranque (diccionario o base de datos inservibles).
struct BootErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ColorsApp no ha podido arrancar")
                .font(.title2.bold())
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityIdentifier("boot.error")
    }
}

#if DEBUG
extension DebugLaunch.Screen {
    /// true si el atajo analiza una foto de ejemplo (escena sintética o foto de `harness/people`)
    /// y guardaría ese análisis: esas pantallas usan una base de datos en memoria. Las pestañas
    /// normales (`feed`, `extraer`, `rejilla`, `jardin`, `ajustes`) usan la base real, y
    /// `feed-demo`/`feed-empty` ya crean la suya.
    var analyzesFixture: Bool {
        switch self {
        case .resultDemo, .resultPeople, .resultPeopleMask, .layersPeople, .layersDemo,
             .resultDemoPerson, .resultDemoPeople, .resultDemoPeopleMask:
            true
        case .explorar, .ajustes, .feed, .feedDemo, .feedEmpty, .extraer, .rejilla, .jardin:
            false
        }
    }
}
#endif
