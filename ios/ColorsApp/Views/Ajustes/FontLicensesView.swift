// Licencias de las fuentes (SIL OFL 1.1) con el marco de las pantallas secundarias
// (FIDELITY.md §7.5): cabecera esmerilada con el logotipo ChromaSol, motas de luz y la
// tarjeta de sección con halo, en vez de la `List` blanca del sistema. El texto completo
// de cada licencia se lee del bundle (la app no abre URLs: sin red).
import SwiftUI

/// Lista de fuentes con su licencia completa.
struct FontLicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                AjustesCard(title: "Licencias de fuentes", systemImage: "textformat", tone: .celadon,
                            kicker: "SIL OFL 1.1",
                            footer: "Las fuentes tipográficas de \(AppBrand.name) se distribuyen con la SIL Open Font License 1.1. Estos son los textos completos incluidos en la app; se leen del propio bundle, sin abrir ninguna página web.") {
                    ForEach(Array(FontLicenses.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { AjustesDivider() }
                        NavigationLink {
                            FontLicenseTextView(entry: entry)
                        } label: {
                            AjustesLinkRow(title: entry.family, detail: entry.credit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fontLicenses.\(entry.id)")
                    }
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
            SecondaryHeader(section: "Licencias", identifier: "fontLicenses.header")
        }
        .tint(Theme.primary)
        .navigationTitle("Licencias de fuentes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("fontLicenses.root")
    }
}

/// Texto completo de una licencia (monoespaciado, en un pocillo de lectura `container`).
struct FontLicenseTextView: View {
    let entry: FontLicenses.Entry

    var body: some View {
        ScrollView {
            Text(FontLicenses.text(for: entry) ?? "Licencia no encontrada en el bundle.")
                .textRole(.hex)
                .foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.container)
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .secondaryAmbience()
        .safeAreaInset(edge: .top, spacing: 0) {
            SecondaryHeader(section: entry.family, identifier: "fontLicense.header")
        }
        .tint(Theme.primary)
        .navigationTitle(entry.family)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("fontLicense.\(entry.id)")
    }
}
