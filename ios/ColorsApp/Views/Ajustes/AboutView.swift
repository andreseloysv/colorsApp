// «Acerca de» con el estilo del sistema de diseño: qué hace la app con las fotos (nada sale
// del dispositivo), atribuciones (Sanzo Wada, Seigensha, dblodorn, mattdesl, GRDB, Unity,
// musl, CIEDE2000 y las fuentes Literata y Plus Jakarta Sans con su SIL OFL 1.1, cuyo
// texto completo se lee del bundle en FontLicensesView) y la build instalada.
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var env: AppEnvironment
    /// Atajo de capturas (solo DEBUG): `-uiAjustesPage licencias` empuja las licencias de fuentes.
    @State private var showFontLicenses = false

    struct Credit: Identifiable {
        let id: String
        let text: String
    }

    static let credits: [Credit] = [
        Credit(id: "wada", text: "Sanzo Wada (和田三造, 1883–1967): «A Dictionary of Color Combinations» (配色事典, 1933–1934), 348 combinaciones del Vol. 1. Obra en dominio público en Japón."),
        Credit(id: "seigensha", text: "Seigensha Art Publishing: edición moderna del diccionario (2011), referencia de los valores del libro."),
        Credit(id: "dblodorn", text: "dblodorn: transcripción digital sanzo-wada (valores CMYK y combinaciones)."),
        Credit(id: "mattdesl", text: "mattdesl: paquete dictionary-of-colour-combinations 1.0.2 (licencia MIT), fuente exacta de data/wada/source/colors.json."),
        Credit(id: "grdb", text: "GRDB.swift (Gwendal Roué, licencia MIT): base de datos SQLite de la app."),
        Credit(id: "unity", text: "Unity (ThrowTheSwitch, licencia MIT): framework de tests del motor de color en C."),
        Credit(id: "musl", text: "musl libc (licencia MIT): funciones matemáticas portables del motor (cbrt, pow, exp, atan2, sin, cos) para que iOS y WASM den los mismos bits."),
        Credit(id: "ciede", text: "CIEDE2000: Sharma, Wu y Dalal (2005), implementación y test set de referencia."),
    ] + FontLicenses.entries.map { Credit(id: "font-\($0.id)", text: $0.credit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                intro
                AjustesCard(title: "Atribuciones", systemImage: "books.vertical", tone: .amber, kicker: "Fuentes") {
                    ForEach(Array(Self.credits.enumerated()), id: \.element.id) { i, credit in
                        if i > 0 { AjustesDivider() }
                        Text(credit.text)
                            .textRole(.bodySM)
                            .foregroundStyle(Theme.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, Spacing.sm)
                    }
                    AjustesDivider()
                    NavigationLink {
                        FontLicensesView()
                    } label: {
                        AjustesLinkRow(title: "Licencias de fuentes (SIL OFL 1.1)",
                                       detail: "Texto completo de Literata y Plus Jakarta Sans")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("about.fontLicenses")
                }
                AjustesCard(title: "Esta build", systemImage: "hammer", tone: .celadon, kicker: "Local") {
                    AjustesValueRow(title: "App", value: "\(Diagnostics.appVersion) (\(Diagnostics.appBuild))")
                    AjustesDivider()
                    AjustesValueRow(title: "Motor", value: env.engineVersion)
                    AjustesDivider()
                    AjustesValueRow(title: "Diccionario", value: "\(env.dictVersion) · \(env.dictionary.status)")
                    AjustesDivider()
                    AjustesValueRow(title: "Fuente del diccionario", value: env.dictionary.source)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .secondaryAmbience()
        .safeAreaInset(edge: .top, spacing: 0) {
            SecondaryHeader(section: "Acerca de", identifier: "about.header")
        }
        .tint(Theme.primary)
        .navigationTitle("Acerca de")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showFontLicenses) {
            FontLicensesView()
        }
        .task {
            #if DEBUG
            if let page = SecondaryLaunch.page, page.hasPrefix("licencia") { showFontLicenses = true }
            #endif
        }
        .accessibilityIdentifier("about.root")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Portada con el emblema vectorial de ChromaSol (72 pt, destello solar de 12 s) en vez
            // del antiguo SF Symbol `sun.max` de `BrandMark` (FIDELITY.md §2.1).
            ChromaSolLockup(size: .display, showsDot: true, animated: true)
            Text("Colores de la ropa · combinaciones de Sanzo Wada")
                .textRole(.labelLG)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(AppBrand.name) reconoce en una foto la combinación de colores de Sanzo Wada más parecida a la ropa. Todo el análisis ocurre en el teléfono: la app no usa red, no tiene cuentas y ninguna foto sale del dispositivo. Los nombres de color en inglés siguen la nomenclatura de Ridgway tal como aparecen en el diccionario.")
                .textRole(.bodyMD)
                .foregroundStyle(Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
                SolarWash(kind: .warm, diameter: 140, blur: 38).offset(x: 50, y: -60)
                SolarWash(kind: .green, diameter: 120, blur: 34).offset(x: -190, y: 150)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .elevation(.restStrong)
        }
        .glowCard(cornerRadius: Radius.card)
        .sunGlint(cornerRadius: Radius.card)
    }
}
