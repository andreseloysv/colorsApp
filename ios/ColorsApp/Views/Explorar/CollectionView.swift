// Combinaciones de una colección (curada o por tamaño) con miniaturas de
// swatches, número y nombre curado si existe.
import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var env: AppEnvironment
    let collectionId: String

    private var collection: WadaCollection? {
        env.dictionary.collections.first { $0.id == collectionId }
    }

    var body: some View {
        Group {
            if let collection {
                List {
                    ForEach(collection.comboIds.compactMap { env.dictionary.combo(id: $0) }) { combo in
                        NavigationLink(value: combo.id) {
                            ComboRow(combo: combo, trailing: env.dictionary.curatedName(id: combo.id) == nil ? nil : WadaDictionary.numberLabel(combo.id))
                        }
                    }
                }
                .navigationTitle(collection.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Colección no encontrada", systemImage: "questionmark.folder")
            }
        }
    }
}
