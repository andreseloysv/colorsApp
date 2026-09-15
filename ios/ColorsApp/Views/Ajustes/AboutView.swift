// "Acerca de": atribuciones (Sanzo Wada, Seigensha, dblodorn, mattdesl, GRDB,
// Unity) y qué hace la app con las fotos (nada sale del dispositivo).
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var env: AppEnvironment

    private struct Credit: Identifiable {
        let id: String
        let text: String
    }

    private let credits: [Credit] = [
        Credit(id: "wada", text: "Sanzo Wada (和田三造, 1883–1967): «A Dictionary of Color Combinations» (配色事典, 1933–1934), 348 combinaciones del Vol. 1. Obra en dominio público en Japón."),
        Credit(id: "seigensha", text: "Seigensha Art Publishing: edición moderna del diccionario (2011), referencia de los valores del libro."),
        Credit(id: "dblodorn", text: "dblodorn: transcripción digital sanzo-wada (valores CMYK y combinaciones)."),
        Credit(id: "mattdesl", text: "mattdesl: paquete dictionary-of-colour-combinations 1.0.2 (licencia MIT), fuente exacta de data/wada/source/colors.json."),
        Credit(id: "grdb", text: "GRDB.swift (Gwendal Roué, licencia MIT): base de datos SQLite de la app."),
        Credit(id: "unity", text: "Unity (ThrowTheSwitch, licencia MIT): framework de tests del motor de color en C."),
        Credit(id: "musl", text: "musl libc (licencia MIT): funciones matemáticas portables del motor (cbrt, pow, exp, atan2, sin, cos) para que iOS y WASM den los mismos bits."),
        Credit(id: "ciede", text: "CIEDE2000: Sharma, Wu y Dalal (2005), implementación y test set de referencia."),
    ]

    var body: some View {
        List {
            Section {
                Text("ColorsApp reconoce en una foto la combinación de colores de Sanzo Wada más parecida. Todo el análisis ocurre en el teléfono: la app no usa red y ninguna foto sale del dispositivo. Los nombres de color en inglés siguen la nomenclatura de Ridgway tal como aparecen en el diccionario.")
            }
            Section("Atribuciones") {
                ForEach(credits) { credit in
                    Text(credit.text)
                        .font(.footnote)
                }
            }
            Section("Esta build") {
                LabeledContent("App", value: "\(Diagnostics.appVersion) (\(Diagnostics.appBuild))")
                LabeledContent("Motor", value: env.engineVersion)
                LabeledContent("Diccionario", value: "\(env.dictVersion) · \(env.dictionary.status)")
                LabeledContent("Fuente del diccionario", value: env.dictionary.source)
                    .font(.footnote)
            }
        }
        .navigationTitle("Acerca de")
        .navigationBarTitleDisplayMode(.inline)
    }
}
