// Pantalla única del stub: versión del motor, ΔE2000 del par 1 de Sharma y el
// contador de lanzamientos leído del fichero de Documents.
import SwiftUI

struct ContentView: View {
    @State private var launches: Int = 0
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ColorsApp — stub F0")
                .font(.title.bold())

            LabeledContent("Motor (ce_version)", value: EngineFacts.engineVersion)
            LabeledContent("ΔE2000 Sharma par 1",
                           value: String(format: "%.4f (esperado 2.0425)", EngineFacts.sharmaPair1DeltaE))
            LabeledContent("Lanzamientos", value: "\(launches)")

            if let launchError {
                Text("Error al escribir el contador: \(launchError)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("Documents/\(LaunchCounter.fileName)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("stub.root")
        .task {
            do {
                launches = try LaunchCounter.increment()
            } catch {
                launchError = error.localizedDescription
                launches = LaunchCounter.read()
            }
        }
    }
}

#Preview {
    ContentView()
}
