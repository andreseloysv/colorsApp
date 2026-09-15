// Punto de entrada de la app iOS. Sin red: el motor de color corre en el
// propio dispositivo vía el paquete local ColorEngine. Crea el
// AppEnvironment una vez y lo inyecta en el árbol de vistas.
import SwiftUI

@main
struct ColorsAppApp: App {
    private let boot: Result<AppEnvironment, any Error>

    init() {
        boot = Result { try AppEnvironment.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let environment):
                RootTabView()
                    .environmentObject(environment)
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
