// Marca visible de la app (docs/design/DESIGN_SYSTEM.md §0.2 E y §3.6). Una sola
// constante: la cabecera, «Acerca de», la tarjeta compartible y la galería leen
// de aquí. El bundle (PRODUCT_NAME, CFBundleDisplayName = ColorsApp,
// com.andreseloy.colorsapp) y los textos de permisos NO cambian con la marca.
import Foundation

enum AppBrand {
    /// Nombre de marca provisional tomado del ejemplo del usuario.
    static let name = "ChromaSol"
    /// Símbolo de la marca (SF Symbols): el sol, sin cara ni criaturas.
    static let symbol = "sun.max.fill"
}
