// Pestaña Rejilla (PLAN §7.5): las 348 combinaciones de Wada en un LazyVGrid,
// en orden de id; casilla gris si no está desbloqueada y con los swatches de la
// combinación si lo está (observación de `unlocks`); contador "41/348" arriba;
// filtro por tamaño (2/3/4 colores); tap -> hoja con el detalle de Explorar
// (`ComboDetailView`, vía `RejillaComboDetailView`);
// botón "Escanear carrete" que presenta `ScanOnboardingView` (día 0).
import SwiftUI

struct RejillaView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = RejillaModel()
    @State private var selected: WadaCombo?
    @State private var showScan = false

    var body: some View {
        NavigationStack {
            RejillaContentView(model: model, dictionary: env.dictionary) { combo in
                selected = combo
            }
            .navigationTitle("Rejilla")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScan = true
                    } label: {
                        Label("Escanear carrete", systemImage: "photo.on.rectangle.angled")
                    }
                    .accessibilityIdentifier("rejilla.scan")
                }
            }
            .sheet(item: $selected) { combo in
                RejillaComboDetailView(combo: combo)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showScan) {
                ScanOnboardingView(onShowGrid: { showScan = false })
                    .environmentObject(env)
            }
        }
        .task { await model.observe(env.unlocks) }
    }
}

/// Contenido de la rejilla sin NavigationStack (reutilizable en capturas y tests).
struct RejillaContentView: View {
    @ObservedObject var model: RejillaModel
    let dictionary: WadaDictionary
    var onSelect: ((WadaCombo) -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 58, maximum: 90), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                header
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.combos(in: dictionary)) { combo in
                        ComboTile(combo: combo, colors: dictionary.colors(of: combo), unlocked: model.isUnlocked(combo.id))
                            .onTapGesture { onSelect?(combo) }
                            .accessibilityIdentifier("rejilla.tile.\(combo.id)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("rejilla.grid")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.counterText(total: dictionary.combinations.count))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("rejilla.counter")
                Text("combinaciones desbloqueadas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(model.unlockedCount), total: Double(max(1, dictionary.combinations.count)))
                .tint(.primary)
            Picker("Tamaño", selection: $model.sizeFilter) {
                Text("Todas").tag(Int?.none)
                ForEach([2, 3, 4], id: \.self) { size in
                    Text("\(size) colores").tag(Int?.some(size))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("rejilla.filter")
            if model.sizeFilter != nil {
                Text("\(model.unlockedCount(in: dictionary)) de \(model.combos(in: dictionary).count) desbloqueadas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rejilla.filter.counter")
            }
        }
        .padding(.top, 4)
    }
}

/// Casilla de la rejilla: ligera (solo rectángulos de color y un número).
struct ComboTile: View {
    let combo: WadaCombo
    let colors: [WadaColor]
    let unlocked: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if unlocked {
                HStack(spacing: 0) {
                    ForEach(colors) { color in
                        Color(wada: color)
                    }
                }
            } else {
                Color(.systemGray5)
            }
            Text(String(combo.id))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(unlocked ? Color.white : Color.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(unlocked ? Color.black.opacity(0.35) : Color.clear, in: Capsule())
                .padding(3)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(unlocked ? 0.12 : 0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(unlocked ? "Combinación \(combo.id), desbloqueada" : "Combinación \(combo.id), bloqueada")
    }
}

/// Detalle de una combinación desde la rejilla: el mismo `ComboDetailView` de
/// Explorar (nombre, colores con hex/RGB/Lab y fecha y origen del desbloqueo)
/// dentro de la hoja, con su propia pila de navegación.
struct RejillaComboDetailView: View {
    let combo: WadaCombo

    var body: some View {
        NavigationStack {
            ComboDetailView(comboId: combo.id)
        }
        .accessibilityIdentifier("rejilla.detail.\(combo.id)")
    }

    static func sourceLabel(_ source: ScanSource) -> String { source.label }
}
