// Textos y colores de la paleta POR PRENDA (ADR-011, CONTEXT §13: «el pantalón es de un solo
// color»). Un único sitio para el nombre de cada región, para que la tarjeta de Extraer, la
// tira del Feed, la tarjeta compartible y la capa «Prendas» del inspector digan lo mismo, y
// para convertir los swatches de prenda (del análisis en memoria o del scan guardado) en los
// `PaletteColor` que pintan los componentes. Sin lógica de color: los colores vienen del motor.
import Foundation
import ColorEngine

enum GarmentText {
    /// Etiqueta larga de la tarjeta: «Parte de arriba», «Parte de abajo», «Prenda entera».
    /// `default` cubre los valores futuros del motor (`CE_GARMENT_REGION_*` aditivos).
    static func regionLabel(_ region: Int) -> String {
        switch region {
        case GarmentRegion.upper.rawValue: "Parte de arriba"
        case GarmentRegion.lower.rawValue: "Parte de abajo"
        case GarmentRegion.whole.rawValue: "Prenda entera"
        default: "Prenda"
        }
    }

    static func regionLabel(_ region: GarmentRegion) -> String { regionLabel(region.rawValue) }

    /// Etiqueta corta para las gotas del Feed y la tarjeta compartible: «Arriba», «Abajo»,
    /// «Prenda entera», «Prenda».
    static func shortRegionLabel(_ region: Int) -> String {
        switch region {
        case GarmentRegion.upper.rawValue: "Arriba"
        case GarmentRegion.lower.rawValue: "Abajo"
        case GarmentRegion.whole.rawValue: "Prenda entera"
        default: "Prenda"
        }
    }

    static func shortRegionLabel(_ region: GarmentRegion) -> String { shortRegionLabel(region.rawValue) }

    /// Por qué el motor juntó varios tonos en un color (capa «Prendas» y tarjetas).
    /// `mergedClusters` = clusters de Lloyd (tonos de luz y sombra) agrupados en ese color.
    static func groupingReason(mergedClusters: Int) -> String {
        guard mergedClusters > 1 else {
            return "Un solo tono: la prenda no tenía sombras que agrupar."
        }
        return "\(mergedClusters) tonos de la misma prenda (luz, sombra y pliegues) agrupados en un color; "
            + "el color que se muestra es el TONO ILUMINADO, no la media."
    }
}

/// Colores de la tira por prenda: el color del motor con la REGIÓN como nombre («Arriba»,
/// «Abajo», «Prenda entera») y su peso. Se usan en el Feed y en la tarjeta compartible, donde
/// lo informativo es de qué prenda sale cada color; en las tarjetas de Extraer el nombre sigue
/// siendo el color de Wada más cercano y la región va en su propia línea.
enum GarmentPalette {
    /// Desde los swatches del análisis en memoria (`ScanOutcome.garments`).
    static func colors(_ garments: [GarmentSwatch]) -> [PaletteColor] {
        garments.enumerated().map { i, g in
            PaletteColor(id: i, r: g.swatch.r, g: g.swatch.g, b: g.swatch.b,
                         name: GarmentText.shortRegionLabel(g.region), weight: g.swatch.weight)
        }
    }

    /// Desde lo guardado en el scan (`scans.garments_json`).
    static func colors(_ entries: [GarmentEntry]) -> [PaletteColor] {
        entries.enumerated().compactMap { i, e in
            PaletteColor(id: i, hex: e.hex, name: GarmentText.shortRegionLabel(e.region), weight: e.weight)
        }
    }
}
