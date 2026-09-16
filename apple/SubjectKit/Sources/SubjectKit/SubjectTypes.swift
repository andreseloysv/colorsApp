// Tipos públicos de SubjectKit: opciones, personas detectadas, resultado de la
// cadena de máscaras y sus capas visuales (lo que la app pinta para explicar de
// dónde sale cada color).
//
// Convenciones (las mismas que ce.h):
//   - Todas las máscaras son width * height bytes empaquetados sin stride, fila
//     a fila desde arriba-izquierda, 0...255 (0 = fuera, 255 = peso pleno).
//   - Coordenadas en píxeles del raster que ve el motor, origen arriba-izquierda,
//     y hacia abajo; el centro del píxel (i, j) es (i + 0.5, j + 0.5).
//   - "Cobertura" = fracción de píxeles del raster con valor >= 128.
//   - La máscara de instancia de Vision es blanda (valores 1...127 en un halo
//     que cae sobre otras personas y el fondo). La cadena trabaja siempre con
//     la máscara BINARIA de la persona (>= 128 -> 255, resto 0): ni el halo ni
//     el bbox de `cutHead` ni la máscara que recibe el motor dependen de él.
import CoreGraphics
import ColorEngine

/// Qué personas alimentan la máscara.
public enum SubjectMode: String, CaseIterable, Sendable {
    /// Sin máscara: se analiza la foto entera (no se ejecuta Vision en `compute`).
    case off
    /// Unión (máximo por píxel) de la cadena aplicada a cada persona.
    case allPeople
    /// La persona con más cobertura (por defecto).
    case largestPerson
    /// La persona `SubjectOptions.selectedIndex` (índice en `people`).
    case selectedPerson
}

/// Qué parte de la persona se usa.
public enum RegionMode: String, CaseIterable, Sendable {
    /// La máscara binaria de la persona.
    case wholePerson
    /// Solo la ropa: regiones de la pose (torso, brazos, piernas; sin cabeza ni
    /// manos; con caderas estimadas si solo se ven los hombros; sin brazos si
    /// están desnudos), la silueta de la pose si esas regiones son demasiado
    /// pequeñas frente a ella, o, sin pose utilizable, la persona sin la franja
    /// de la cabeza (`cutHead`). Con pose nunca se vuelve a la máscara cruda de
    /// Vision: la silueta deja fuera objetos pegados (cochecito, bici, bolso).
    case clothing
}

/// Opciones de la cadena de máscaras. Los valores por defecto son los de la app
/// (decisión del usuario): persona más grande + solo ropa + piel adaptativa.
public struct SubjectOptions: Equatable, Sendable {
    public var mode: SubjectMode = .largestPerson
    public var region: RegionMode = .clothing
    /// Excluir la piel con un modelo gaussiano ajustado a la cara de cada persona.
    public var adaptiveSkin = true
    /// Con `adaptiveSkin`, una persona sin muestra de cara utilizable (de espaldas,
    /// sin landmarks, < 50 muestras) usa la muestra de la persona de la foto con más
    /// muestras (`PersonLayers.skinSampleSource`). La salvaguarda del 35 % sigue
    /// protegiendo prendas de ese tono.
    public var shareSkinModel = true
    /// Índice en `SubjectMaskResult.people` (ordenadas por cobertura descendente)
    /// para `.selectedPerson`. nil o fuera de rango: se usa la persona más grande.
    public var selectedIndex: Int? = nil
    /// Opciones de `clothingRegions` (defecto del motor: ce_region_opts_default).
    public var regionOptions: RegionOptions = .default
    /// Opciones de `excludeSkin`. Preajuste de SubjectKit `SubjectOptions.defaultSkinOptions`
    /// (Mahalanobis 2,75, salvaguarda 35 %), no el del motor (2,5): con 2,5 la piel en
    /// sombra de manos y brazos quedaba en la paleta (harness/people 05; ADR-010).
    public var skinOptions: SkinOptions = SubjectOptions.defaultSkinOptions
    /// Suelo ABSOLUTO (fracción del raster, 0...1) que debe cubrir la silueta de
    /// la pose, una región candidata y la máscara final de cada persona. Por
    /// defecto 0,0005 (≈ 350 px en un raster de 1024 x 683, ≈ 20 píxeles de la
    /// imagen reducida del motor): solo descarta máscaras sin estadística
    /// suficiente, no personas pequeñas. Si la máscara final no llega se usa la
    /// silueta de la pose (con pose) o la persona completa y, si tampoco, sin máscara.
    public var minCoverage = 0.0005
    /// Fracción mínima (0...1) de la silueta de la pose de la PROPIA persona que
    /// deben conservar las regiones de ropa para usarlas; si no llegan se usa la
    /// silueta. Relativa a la persona que describe la pose, no al raster ni a la
    /// máscara de Vision: una persona pequeña (un bebé, alguien al fondo) conserva
    /// su región de ropa, y un objeto grande pegado a ella en la misma instancia
    /// (el cochecito) no la hace «insuficiente».
    public var minRegionFraction = 0.15
    /// Con modelo de piel y brazos en las regiones: si al menos esta fracción
    /// (0...1) de los píxeles de los brazos (regiones con brazos menos regiones sin
    /// ellos) es piel según el modelo (sin salvaguarda), los brazos se quitan de la
    /// región (manga corta o sin mangas: la piel en sombra que el modelo no
    /// alcanza también se va). 1 = nunca.
    public var bareArmsSkinFraction = 0.25
    /// Piel del cuerpo aprendida (con modelo de piel, región de ropa y pose): si los brazos
    /// o las piernas de la región son desnudos (>= `bareArmsSkinFraction` de sus píxeles es
    /// piel con el modelo de la cara), la muestra se amplía hasta este número de veces con
    /// los píxeles de la región con brazos que el modelo vigente marca como piel a
    /// Mahalanobis <= `skinLearningMahalanobis`, y el modelo se reajusta (el motor:
    /// `fitSkinModel`). Así la piel del cuerpo con la luz del cuerpo (hombros al sol,
    /// escote y piernas en sombra: harness/people 07 y 02) entra en el modelo aunque la
    /// cara esté iluminada de otra forma. Se detiene si una pasada no añade nada, si marcaría
    /// más de `skinOptions.maxExcludedFraction` de la zona (prenda color piel) o si el modelo
    /// ampliado dispararía la salvaguarda en la región (esa pasada no se acepta). 0 = nunca.
    public var skinLearningIterations = 2
    /// Umbral de Mahalanobis de los píxeles que amplían la muestra (ver `skinLearningIterations`).
    public var skinLearningMahalanobis = 3.0
    /// Tras excluir piel (y crecerla), se quitan además los píxeles de la máscara a distancia de
    /// Chebyshev <= este radio de un píxel de piel quitado: los bordes piel/prenda mezclan
    /// los dos colores (desenfoque, JPEG, reescalado) y arrastran un swatch hacia la piel; el
    /// motor además promedia bloques de 4 x 4 px del raster de 1024 (ce_image_reduce) con los
    /// píxeles fuera de la máscara incluidos. 0 = sin halo. No se aplica con la salvaguarda.
    /// Defecto 2 (antes 1): con 1 px la piel de los bordes seguía formando un swatch en
    /// harness/people 05 y 07 (ADR-010).
    public var skinHaloRadius = 2
    /// (Nuevo) Crecimiento de la piel en sombra: tras `excludeSkin`, los píxeles que quedan en la
    /// máscara a Mahalanobis <= este umbral del mismo modelo y CONECTADOS (vecindad de 8, a lo
    /// sumo `skinGrowRadius` pasos) con la piel quitada también se quitan (histéresis: el
    /// umbral estricto siembra, este deja crecer). La piel en sombra del cuello, la axila, el
    /// canto de la mano o los dedos queda fuera del elipsoide estrecho de las mejillas pero
    /// pegada a la piel iluminada; una prenda de color piel lejos de la piel no se toca. Si
    /// piel + crecimiento superan `skinOptions.maxExcludedFraction` de la máscara o el crecimiento supera
    /// `skinGrowMaxRatio` de la piel quitada, no se crece.
    /// Umbral <= `skinOptions.maxMahalanobis` o radio 0 = sin crecimiento.
    public var skinGrowMahalanobis = 5.0
    /// (Nuevo) Pasos máximos (Chebyshev, px del raster) del crecimiento desde la piel quitada.
    public var skinGrowRadius = 12
    /// (Nuevo) El crecimiento no se aplica si añade más de esta fracción de los píxeles que quitó
    /// `excludeSkin` (0...1). La sombra de la piel es un borde de la piel iluminada (harness/people:
    /// 0,19 en 02, 0,34 en 05, 0,25 en 07); una prenda de color piel con unos pocos píxeles dentro del
    /// umbral estricto crecería mucho más que su semilla (simulación de riesgo, ADR-010).
    public var skinGrowMaxRatio = 0.5
    /// Sin modelo de piel (se pidió piel y no hay cara utilizable): los brazos se quitan
    /// salvo que sean mangas de la prenda del torso: si al menos `sleeveMatchFraction` de
    /// los píxeles de los brazos está a Mahalanobis <= `sleeveMatchMahalanobis` del modelo
    /// gaussiano del torso (`fitSkinModel` con el torso como muestra), se quedan
    /// (harness/people 03: camisa de rayas de espaldas). 1 = quitarlos siempre.
    public var sleeveMatchFraction = 0.7
    /// Umbral de Mahalanobis de la prueba de mangas (ver `sleeveMatchFraction`).
    public var sleeveMatchMahalanobis = 2.0
    /// Evidencia corporal para aceptar una instancia de Vision como persona (`compute`).
    public var phantomOptions: PhantomOptions = .default
    /// (Nuevo, aditivo) Calcular el mapa de regiones de prenda (`SubjectMaskResult.garmentRegions`,
    /// `PersonLayers.garmentRegions`) para la paleta por prenda del motor (`analyzeGarments`,
    /// ADR-011): con `region == .clothing` y una persona cuya región sale de la pose
    /// (`RegionDecision.source` `.poseRegions` o `.poseSilhouette`), `ce_mask_garment_regions` con
    /// la pose del motor, las opciones de la silueta (`garmentRegionOptions`) y la máscara que
    /// recibe el motor para esa persona; añade el paso `.garmentRegions`. Sin pose (recorte de
    /// cabeza), con `wholePerson`, sin máscara o con CE_ERR_POSE, el mapa es nil y la app sigue con
    /// el camino clásico (`analyze`). Por defecto false: los pasos, la máscara y lo que guarda la
    /// app no cambian hasta que la app lo active al integrar la paleta por prenda.
    public var computeGarmentRegions = false
    /// (Nuevo, aditivo) Separación de instancias que Vision fusiona (`PersonSplitter`,
    /// `ce_mask_split_instance`): personas nuevas con `splitFrom` y paso `.splitByPose` /
    /// `.splitByFace`. `SplitOptions.enabled = false` devuelve el comportamiento anterior
    /// (una persona por instancia de Vision).
    public var splitOptions: SplitOptions = .default

    /// Preajuste de piel de SubjectKit: Mahalanobis 2,75 y salvaguarda 0,35.
    public static var defaultSkinOptions: SkinOptions {
        SkinOptions(maxMahalanobis: 2.75, maxExcludedFraction: SkinOptions.default.maxExcludedFraction)
    }

    public init(mode: SubjectMode = .largestPerson, region: RegionMode = .clothing, adaptiveSkin: Bool = true,
                selectedIndex: Int? = nil, regionOptions: RegionOptions = .default,
                skinOptions: SkinOptions = SubjectOptions.defaultSkinOptions, minCoverage: Double = 0.0005,
                minRegionFraction: Double = 0.15, shareSkinModel: Bool = true, bareArmsSkinFraction: Double = 0.25,
                skinLearningIterations: Int = 2, skinLearningMahalanobis: Double = 3.0, skinHaloRadius: Int = 2,
                sleeveMatchFraction: Double = 0.7, sleeveMatchMahalanobis: Double = 2.0,
                phantomOptions: PhantomOptions = .default, skinGrowMahalanobis: Double = 5.0, skinGrowRadius: Int = 12,
                skinGrowMaxRatio: Double = 0.5, computeGarmentRegions: Bool = false,
                splitOptions: SplitOptions = .default) {
        self.mode = mode
        self.region = region
        self.adaptiveSkin = adaptiveSkin
        self.shareSkinModel = shareSkinModel
        self.selectedIndex = selectedIndex
        self.regionOptions = regionOptions
        self.skinOptions = skinOptions
        self.minCoverage = minCoverage
        self.minRegionFraction = minRegionFraction
        self.bareArmsSkinFraction = bareArmsSkinFraction
        self.skinLearningIterations = skinLearningIterations
        self.skinLearningMahalanobis = skinLearningMahalanobis
        self.skinHaloRadius = skinHaloRadius
        self.sleeveMatchFraction = sleeveMatchFraction
        self.sleeveMatchMahalanobis = sleeveMatchMahalanobis
        self.phantomOptions = phantomOptions
        self.skinGrowMahalanobis = skinGrowMahalanobis
        self.skinGrowRadius = skinGrowRadius
        self.skinGrowMaxRatio = skinGrowMaxRatio
        self.computeGarmentRegions = computeGarmentRegions
        self.splitOptions = splitOptions
    }

    /// Persona más grande, solo ropa, piel adaptativa (compartida si la persona no
    /// tiene cara utilizable; Mahalanobis 2,75, piel del cuerpo aprendida con brazos o
    /// piernas desnudos, piel en sombra conectada hasta Mahalanobis 5, 12 px y 0,5 de la piel quitada,
    /// halo de 2 px),
    /// regiones >= 15 % de la silueta de la pose, brazos
    /// fuera si >= 25 % es piel (sin modelo: si no son mangas del torso), suelo absoluto
    /// 0,05 % del raster, personas fantasma descartadas, instancias fusionadas separadas.
    public static var `default`: SubjectOptions { SubjectOptions() }
}

/// Una persona detectada (o construida a mano en los tests).
public struct PersonInstance: Equatable, Sendable, Identifiable {
    /// Índice de instancia de Vision (1...n; 0 es el fondo en la máscara de
    /// instancias) o, en una persona separada de una instancia que juntaba a
    /// varias (`splitFrom` != nil), un id nuevo mayor que todos los de Vision.
    public let id: Int
    /// Máscara de la persona reescalada al raster tal como la da Vision
    /// (width * height bytes, 0...255, blanda). La cadena usa su versión binaria
    /// (`MaskOps.binarize`).
    public let mask: [UInt8]
    /// Fracción del raster con máscara >= 128.
    public let coverage: Double
    /// Rectángulo que contiene los píxeles >= 128, en píxeles del raster
    /// (origen arriba-izquierda); `.zero` si la máscara está vacía.
    public let bbox: CGRect
    /// Pose asociada (15 puntos en píxeles del raster), nil si ninguna pose de
    /// Vision cae dentro de esta persona.
    public let pose: Pose?
    /// Muestra de piel: 255 en mejillas y frente (polígonos derivados de los
    /// landmarks, sin ojos, cejas, labios ni pelo) dentro de la persona; nil si
    /// no hay cara con landmarks asociada.
    public let faceSampleMask: [UInt8]?
    /// Rectángulo de la cara asociada (píxeles del raster), nil sin cara. Sin pose
    /// utilizable fija la altura del recorte de cabeza (`SubjectExtractor.cutHeadFraction(bodyBox:faceBox:)`).
    public let faceBox: CGRect?
    /// (Nuevo, aditivo) Id de la instancia de Vision de la que se separó esta
    /// persona (Vision juntó a varias personas que se tocaban; ver
    /// `PersonSplitter`), nil si la persona es una instancia de Vision tal cual.
    public let splitFrom: Int?

    public init(id: Int, mask: [UInt8], coverage: Double, bbox: CGRect, pose: Pose?, faceSampleMask: [UInt8]?,
                faceBox: CGRect? = nil, splitFrom: Int? = nil) {
        self.id = id
        self.mask = mask
        self.coverage = coverage
        self.bbox = bbox
        self.pose = pose
        self.faceSampleMask = faceSampleMask
        self.faceBox = faceBox
        self.splitFrom = splitFrom
    }

    /// Calcula `coverage` y `bbox` a partir de la máscara (`width` x `height`).
    public init(id: Int, mask: [UInt8], width: Int, height: Int, pose: Pose? = nil, faceSampleMask: [UInt8]? = nil,
                faceBox: CGRect? = nil, splitFrom: Int? = nil) {
        let stats = MaskOps.stats(mask, width: width, height: height)
        self.init(id: id, mask: mask, coverage: stats.coverage, bbox: stats.bbox, pose: pose,
                  faceSampleMask: faceSampleMask, faceBox: faceBox, splitFrom: splitFrom)
    }

    /// (Nuevo, aditivo) Paso de separación de esta persona: `.splitByPose` si su
    /// semilla fue una pose (la persona separada lleva esa pose), `.splitByFace`
    /// si fue una cara sin pose; nil si no se separó.
    public var splitStep: MaskFallback? {
        guard splitFrom != nil else { return nil }
        return pose != nil ? .splitByPose : .splitByFace
    }
}

/// Pasos y salidas de la cadena, en el orden en que ocurrieron.
public enum MaskFallback: String, Sendable {
    /// Sin máscara: modo `off` o ni la persona completa llega al suelo `minCoverage`.
    case none
    /// Vision no encontró personas: sin máscara.
    case noPeople
    /// Región de ropa calculada con la pose (`clothingRegions`): las regiones
    /// normales o, si eran demasiado pequeñas frente a la silueta de la pose, la
    /// silueta (ver `PersonLayers.regionDecision`).
    case poseRegions
    /// Persona sin la franja de la cabeza (`cutHead`): sin pose utilizable o con
    /// una silueta de la pose por debajo del suelo `minCoverage` (la pose no
    /// describe a esta persona; entonces va detrás de `poseRegions`).
    case headCut
    /// La máscara final no llegaba al suelo `minCoverage`: se usa la persona
    /// completa, que con pose es su silueta (`PersonLayers.fallbackSource`) y sin
    /// pose la persona binaria.
    case wholePerson
    /// Piel excluida con el modelo adaptativo (`excludeSkin`): se quitó al menos un píxel.
    case skinExcluded
    /// La salvaguarda de piel saltó (se habría quitado > 35 %): máscara intacta.
    case skinGuard
    /// Vision lanzó un error (p. ej. simulador sin soporte): sin máscara.
    case visionUnavailable
    /// (Nuevo, aditivo) Vision devolvió al menos una instancia sin evidencia corporal
    /// (sin pose con torso dentro, sin cara y sin silueta plausible: `PersonEvidence`) y se
    /// descartó. Va PRIMERO en los pasos: le siguen los de las personas que quedan o
    /// `.noPeople` (foto completa) si no queda ninguna. Las instancias descartadas están
    /// en `SubjectMaskResult.rejectedPhantoms`. Los `switch` exhaustivos sobre
    /// `MaskFallback` deben añadir este caso (p. ej. «Persona fantasma descartada»).
    case rejectedPhantom
    /// (Nuevo, aditivo) Mapa de regiones de prenda calculado con la pose
    /// (`SubjectOptions.computeGarmentRegions`, `SubjectMaskResult.garmentRegions`: 1 arriba,
    /// 2 abajo). Va AL FINAL de los pasos (después de la piel y del respaldo): no cambia la
    /// máscara, solo reparte sus píxeles en prendas. Sin pose no aparece (mapa nil: camino
    /// clásico). Los `switch` exhaustivos sobre `MaskFallback` deben añadir este caso (p. ej.
    /// «Regiones de prenda»).
    case garmentRegions
    /// (Nuevo, aditivo) La persona sale de una instancia de Vision que juntaba a varias,
    /// separada con su POSE como semilla (`ce_mask_split_instance`). Va PRIMERO en los
    /// pasos de esa persona. Los `switch` exhaustivos sobre `MaskFallback` deben añadir
    /// este caso (p. ej. «Persona separada por su pose»).
    case splitByPose
    /// (Nuevo, aditivo) Idem con su CARA como semilla (cara sin pose utilizable). Los
    /// `switch` exhaustivos deben añadir este caso (p. ej. «Persona separada por su cara»).
    case splitByFace
}

/// (Nuevo, aditivo) Recuentos del mapa de regiones de prenda de una persona
/// (`PersonLayers.garmentRegionStats`).
public struct GarmentRegionStats: Equatable, Sendable {
    /// Píxeles con 1 (arriba: torso y brazos) en el mapa final.
    public let upperPixels: Int
    /// Píxeles con 2 (abajo: caderas a tobillos) en el mapa final.
    public let lowerPixels: Int
    /// Píxeles > 0 de la máscara con la que se calculó el mapa (la que recibe el motor para esta
    /// persona). Con la silueta de la pose como opciones, upper + lower == maskPixels.
    public let maskPixels: Int
    /// true si la pose tenía las caderas ESTIMADAS (plano medio, `RegionDecision.hipsEstimated`):
    /// no se ve la parte de abajo y los píxeles que el motor etiquetó 2 (franja del torso más
    /// allá de las caderas inventadas) pasan a 1 (una sola prenda, la de arriba).
    public let lowerMergedIntoUpper: Bool
    /// Píxeles que el motor etiquetó 2 antes de unirlos a la parte de arriba (0 si no se unieron).
    public let mergedLowerPixels: Int
    /// Opciones de `ce_mask_garment_regions` usadas (`SubjectExtractor.garmentRegionOptions`).
    public let options: RegionOptions
    /// Pose entregada al motor (`RegionDecision.regionPose`).
    public let pose: Pose

    public init(upperPixels: Int, lowerPixels: Int, maskPixels: Int, lowerMergedIntoUpper: Bool, mergedLowerPixels: Int,
                options: RegionOptions, pose: Pose) {
        self.upperPixels = upperPixels
        self.lowerPixels = lowerPixels
        self.maskPixels = maskPixels
        self.lowerMergedIntoUpper = lowerMergedIntoUpper
        self.mergedLowerPixels = mergedLowerPixels
        self.options = options
        self.pose = pose
    }
}

/// De dónde sale la región de una persona.
public enum RegionSource: String, Sendable {
    /// `clothingRegions` con las opciones de `SubjectOptions.regionOptions`.
    case poseRegions
    /// `clothingRegions` con las opciones de silueta (`SubjectExtractor.silhouetteOptions`):
    /// antebrazos incluidos, cápsulas y margen del torso más anchos; sigue sin
    /// cabeza ni manos y deja fuera objetos lejos del esqueleto (cochecito, bici).
    /// Es la «persona según la pose»: referencia de la suficiencia de las regiones.
    case poseSilhouette
    /// `cutHead` sobre la persona binaria.
    case headCut
    /// La persona binaria completa (`RegionMode.wholePerson`).
    case wholePerson
}

/// Cómo se eligió la región de una persona (para explicarlo en la capa y
/// reproducirlo con la CLI `ce`).
public struct RegionDecision: Equatable, Sendable {
    /// Región elegida.
    public let source: RegionSource
    /// Píxeles de la persona binaria.
    public let bodyPixels: Int
    /// Píxeles que deben tener las regiones de la pose para usarlas:
    /// max(ceil(minRegionFraction · silhouettePixels), suelo) con pose aceptada por
    /// el motor; sin ella, el suelo max(ceil(minCoverage · width · height), 1).
    public let requiredPixels: Int
    /// Píxeles de las regiones de la pose con las opciones finales (sin brazos si
    /// se quitaron) (nil: sin pose o CE_ERR_POSE).
    public let poseRegionPixels: Int?
    /// Píxeles de la silueta de la pose (nil: sin pose o CE_ERR_POSE). Se calcula
    /// siempre que el motor acepta la pose.
    public let silhouettePixels: Int?
    /// Pixeles de la región elegida.
    public let regionPixels: Int
    /// Pose entregada al motor (la de Vision con las caderas estimadas si hizo
    /// falta, ver `SubjectExtractor.regionPose`); nil sin pose.
    public let regionPose: Pose?
    /// true si las caderas de `regionPose` son estimadas (plano medio sin caderas).
    public let hipsEstimated: Bool
    /// Fracción de `cutHead` usada (solo con `source == .headCut`).
    public let headCutFraction: Double?
    /// Opciones de `clothingRegions` de las regiones de la pose (la silueta usa
    /// `SubjectExtractor.silhouetteOptions` de estas); nil si no se llamó con pose.
    public let regionOptions: RegionOptions?
    /// true si se quitaron los brazos de las opciones de la app porque se pidió
    /// excluir piel, no había muestra de piel (propia ni compartida) y la prueba de
    /// mangas no los reconoció como mangas de la prenda del torso (`sleevesKept`).
    public let upperArmsDropped: Bool
    /// Prueba de brazos desnudos (con modelo de piel y brazos pedidos): píxeles de
    /// los brazos (regiones con brazos menos sin brazos); nil si no se hizo. La piel
    /// (`armSkinPixels`) se cuenta con el modelo final (el aprendido si lo hubo).
    public let armPixels: Int?
    /// Píxeles de esos brazos que el modelo de piel marca como piel (sin salvaguarda).
    public let armSkinPixels: Int?
    /// true si los brazos se quitaron porque armSkinPixels >= ceil(bareArmsSkinFraction · armPixels).
    public let bareArmsDropped: Bool
    /// Prueba de piernas desnudas (con modelo de piel y piernas en la región): píxeles de las
    /// piernas (regiones menos regiones sin piernas); nil si no se hizo. Solo decide si se
    /// aprende la piel del cuerpo (las piernas no se quitan).
    public let legPixels: Int?
    /// Píxeles de esas piernas que el modelo de la cara marca como piel (sin salvaguarda).
    public let legSkinPixels: Int?
    /// Prueba de mangas sin modelo de piel: píxeles de los brazos probados; nil si no se hizo.
    public let sleevePixels: Int?
    /// Píxeles de esos brazos parecidos al torso (Mahalanobis <= sleeveMatchMahalanobis).
    public let sleeveMatchPixels: Int?
    /// true si sin modelo de piel los brazos se quedaron por ser mangas de la prenda del torso.
    public let sleevesKept: Bool

    public init(source: RegionSource, bodyPixels: Int, requiredPixels: Int, poseRegionPixels: Int?,
                silhouettePixels: Int?, regionPixels: Int, regionPose: Pose?, hipsEstimated: Bool,
                headCutFraction: Double?, regionOptions: RegionOptions? = nil, upperArmsDropped: Bool = false,
                armPixels: Int? = nil, armSkinPixels: Int? = nil, bareArmsDropped: Bool = false,
                legPixels: Int? = nil, legSkinPixels: Int? = nil, sleevePixels: Int? = nil,
                sleeveMatchPixels: Int? = nil, sleevesKept: Bool = false) {
        self.source = source
        self.bodyPixels = bodyPixels
        self.requiredPixels = requiredPixels
        self.poseRegionPixels = poseRegionPixels
        self.silhouettePixels = silhouettePixels
        self.regionPixels = regionPixels
        self.regionPose = regionPose
        self.hipsEstimated = hipsEstimated
        self.headCutFraction = headCutFraction
        self.regionOptions = regionOptions
        self.upperArmsDropped = upperArmsDropped
        self.armPixels = armPixels
        self.armSkinPixels = armSkinPixels
        self.bareArmsDropped = bareArmsDropped
        self.legPixels = legPixels
        self.legSkinPixels = legSkinPixels
        self.sleevePixels = sleevePixels
        self.sleeveMatchPixels = sleeveMatchPixels
        self.sleevesKept = sleevesKept
    }
}

/// Capas de una persona a lo largo de la cadena (mismas dimensiones que el raster).
public struct PersonLayers: Sendable {
    /// Índice en `SubjectMaskResult.people`.
    public let personIndex: Int
    /// `PersonInstance.id` (índice de instancia de Vision).
    public let instanceId: Int
    /// Máscara BINARIA de la persona (>= 128 de la instancia de Vision -> 255),
    /// que es la entrada de la cadena. La máscara blanda original está en
    /// `SubjectMaskResult.people[personIndex].mask`.
    public let personMask: [UInt8]
    /// Pose de Vision en píxeles del raster (para dibujar el esqueleto); nil sin pose.
    /// La pose que recibió el motor está en `regionDecision.regionPose`.
    public let pose: Pose?
    /// Región de ropa antes de la piel (regiones o silueta de la pose, o `headCut`);
    /// nil con `wholePerson`.
    public let regionMask: [UInt8]?
    /// Silueta de la pose (persona binaria ∩ envolvente ancha del esqueleto, sin
    /// cabeza ni manos); nil sin pose aceptada por el motor.
    public let silhouetteMask: [UInt8]?
    /// Brazos probados en la prueba de brazos desnudos o, sin modelo de piel, en la de mangas
    /// (255 = píxel de brazo); nil si no se hizo.
    public let armsMask: [UInt8]?
    /// Muestra de piel de la cara usada para el modelo (la propia o, con
    /// `shareSkinModel`, la de `skinSampleSource`); nil sin muestra o sin `adaptiveSkin`.
    public let faceSampleMask: [UInt8]?
    /// 255 donde se quitó piel (exclusión, crecimiento y halo); nil si no se aplicó o si saltó la salvaguarda.
    public let skinRemovedMask: [UInt8]?
    /// Máscara de esta persona al final de su cadena (región y piel), ANTES del
    /// suelo `minCoverage`: si luego se volvió a la persona completa
    /// (`.wholePerson`) o se descartó (`.none`), la máscara del motor es
    /// `SubjectLayers.finalMask`, no esta.
    public let finalMask: [UInt8]
    /// Pasos de esta persona.
    public let steps: [MaskFallback]
    /// Modelo de piel con el que se excluyó (el de la cara o, si se aprendió piel del
    /// cuerpo, el reajustado con la última de `learnedSampleMasks`); nil si no se ajustó.
    public let skinModel: SkinModel?
    /// Píxeles que la exclusión de piel pasó a 0, crecimiento y halo incluidos (0 con la
    /// salvaguarda o sin modelo); los del crecimiento solos están en `skinGrownPixels` y los del
    /// halo en `skinHaloPixels`.
    public let skinExcludedPixels: Int
    /// Por qué no se aplicó la piel teniendo muestra (p. ej. "tooFewSkinSamples"); nil si se aplicó.
    public let skinNote: String?
    /// Cómo se eligió la región (nil en capas construidas a mano).
    public let regionDecision: RegionDecision?
    /// false si esta persona no aporta a la máscara final (en `allPeople`, su
    /// máscara final no llegó al suelo `minCoverage`).
    public let usedInMask: Bool
    /// Índice en `SubjectMaskResult.people` de la persona cuya cara dio la muestra
    /// de piel: `personIndex` si es la propia, otro índice si se compartió; nil sin muestra.
    public let skinSampleSource: Int?
    /// Con el paso `.wholePerson`: qué máscara se usó en lugar de la final de la
    /// cadena (`.poseSilhouette` con pose, `.wholePerson` = persona binaria sin
    /// ella); nil si no hubo que volver.
    public let fallbackSource: RegionSource?
    /// Muestras de piel ampliadas con la piel del cuerpo, una por pasada de aprendizaje
    /// (`faceSampleMask` ∪ candidatos acumulados); la última ajustó `skinModel`. Vacío sin aprendizaje.
    public let learnedSampleMasks: [[UInt8]]
    /// Candidatos de piel de la región (lo que cuenta `excludeSkin` sin salvaguarda) en cada
    /// pasada de aprendizaje aceptada (mismo orden que `learnedSampleMasks`).
    public let skinLearningPixels: [Int]
    /// Piernas probadas en la prueba de piernas desnudas (255 = píxel de pierna); nil si no se hizo.
    public let legsMask: [UInt8]?
    /// Máscara justo después de `excludeSkin`, antes del halo; nil sin exclusión.
    public let skinExcludedMask: [UInt8]?
    /// Píxeles quitados por el halo alrededor de la piel (`skinHaloRadius`).
    public let skinHaloPixels: Int
    /// Torso usado en la prueba de mangas (255 = torso); nil si no se hizo.
    public let sleeveTorsoMask: [UInt8]?
    /// (Nuevo) Píxeles quitados por el crecimiento de la piel en sombra (`skinGrowMahalanobis`);
    /// 0 si no hubo crecimiento.
    public let skinGrownPixels: Int
    /// (Nuevo) 255 en los píxeles quitados por el crecimiento; nil sin crecimiento aplicado.
    public let skinGrownMask: [UInt8]?
    /// (Nuevo) Candidatos del crecimiento: píxeles de `skinExcludedMask` a Mahalanobis <=
    /// `skinGrowMahalanobis` (lo que cuenta `ce skin` sobre skin_excluded.pgm); nil si no se probó.
    public let skinGrowCandidatePixels: Int?
    /// (Nuevo) Mapa de regiones de prenda de esta persona (width * height bytes: 0 fuera, 1 arriba,
    /// 2 abajo) calculado sobre la máscara que esta persona aporta al motor; nil sin
    /// `computeGarmentRegions`, sin pose o si la persona no aporta máscara (ver `SubjectOptions`).
    public let garmentRegions: [UInt8]?
    /// (Nuevo) Recuentos y entradas del mapa; nil si `garmentRegions` es nil.
    public let garmentRegionStats: GarmentRegionStats?

    public init(personIndex: Int, instanceId: Int, personMask: [UInt8], pose: Pose?, regionMask: [UInt8]?,
                faceSampleMask: [UInt8]?, skinRemovedMask: [UInt8]?, finalMask: [UInt8], steps: [MaskFallback],
                skinModel: SkinModel?, skinExcludedPixels: Int, skinNote: String?,
                regionDecision: RegionDecision? = nil, usedInMask: Bool = true, skinSampleSource: Int? = nil,
                silhouetteMask: [UInt8]? = nil, armsMask: [UInt8]? = nil, fallbackSource: RegionSource? = nil,
                learnedSampleMasks: [[UInt8]] = [], skinLearningPixels: [Int] = [], skinExcludedMask: [UInt8]? = nil,
                skinHaloPixels: Int = 0, sleeveTorsoMask: [UInt8]? = nil, legsMask: [UInt8]? = nil,
                skinGrownPixels: Int = 0, skinGrownMask: [UInt8]? = nil, skinGrowCandidatePixels: Int? = nil,
                garmentRegions: [UInt8]? = nil, garmentRegionStats: GarmentRegionStats? = nil) {
        self.personIndex = personIndex
        self.instanceId = instanceId
        self.personMask = personMask
        self.pose = pose
        self.regionMask = regionMask
        self.faceSampleMask = faceSampleMask
        self.skinRemovedMask = skinRemovedMask
        self.finalMask = finalMask
        self.steps = steps
        self.skinModel = skinModel
        self.skinExcludedPixels = skinExcludedPixels
        self.skinNote = skinNote
        self.regionDecision = regionDecision
        self.usedInMask = usedInMask
        self.skinSampleSource = skinSampleSource
        self.silhouetteMask = silhouetteMask
        self.armsMask = armsMask
        self.fallbackSource = fallbackSource
        self.learnedSampleMasks = learnedSampleMasks
        self.skinLearningPixels = skinLearningPixels
        self.legsMask = legsMask
        self.skinExcludedMask = skinExcludedMask
        self.skinHaloPixels = skinHaloPixels
        self.sleeveTorsoMask = sleeveTorsoMask
        self.skinGrownPixels = skinGrownPixels
        self.skinGrownMask = skinGrownMask
        self.skinGrowCandidatePixels = skinGrowCandidatePixels
        self.garmentRegions = garmentRegions
        self.garmentRegionStats = garmentRegionStats
    }
}

/// Capas visuales del recorte: la persona elegida (o cada persona en
/// `allPeople`) y el mapa de instancias para pintar a cada persona de un color.
public struct SubjectLayers: Sendable {
    public let width: Int
    public let height: Int
    /// Una entrada con `largestPerson` / `selectedPerson`; una por persona con
    /// `allPeople`; vacía con `off` o sin personas.
    public let persons: [PersonLayers]
    /// `PersonInstance.id` de la persona con mayor máscara (>= 128) en cada píxel,
    /// 0 = fondo (desempate: la de más cobertura).
    public let allPeopleOverlay: [UInt8]
    /// Máscara que se entrega al motor (== `SubjectMaskResult.mask`).
    public let finalMask: [UInt8]?

    public init(width: Int, height: Int, persons: [PersonLayers], allPeopleOverlay: [UInt8], finalMask: [UInt8]?) {
        self.width = width
        self.height = height
        self.persons = persons
        self.allPeopleOverlay = allPeopleOverlay
        self.finalMask = finalMask
    }

    /// Capas de la persona elegida (la primera entrada).
    public var primary: PersonLayers? { persons.first }
}

/// Resultado de la cadena de máscaras.
public struct SubjectMaskResult: Sendable {
    public let width: Int
    public let height: Int
    /// Personas detectadas, ordenadas por cobertura descendente (desempate por
    /// id); incluye las separadas de instancias que juntaban a varias (hasta 8).
    public let people: [PersonInstance]
    /// Índice en `people` de la persona usada (nil con `allPeople`, `off` o sin personas).
    public let chosenIndex: Int?
    /// Máscara para el motor (width * height bytes, 0 o 255); nil = analizar sin máscara.
    public let mask: [UInt8]?
    /// Pasos aplicados y retornos, en orden.
    public let steps: [MaskFallback]
    /// Milisegundos por paso ("vision.instances", "vision.masks", "vision.pose",
    /// "vision.face", "associate", "detect", "regions", "skin", "coverage", "mask", "total").
    public let timings: [String: Double]
    /// Cobertura de `mask` (0 si es nil).
    public let maskCoverage: Double
    /// Capas para ver cada etapa.
    public let layers: SubjectLayers
    /// Instancias de Vision descartadas por no tener evidencia corporal (paso `.rejectedPhantom`).
    public let rejectedPhantoms: [RejectedPerson]
    /// (Nuevo, aditivo) Mapa de regiones de prenda de la persona elegida (width * height bytes, sin
    /// stride: 0 fuera de la máscara, 1 arriba = torso y brazos, 2 abajo = caderas a tobillos),
    /// para `analyzeGarments(..., mask: mask, regions: garmentRegions, regionCount: garmentMaxRegions)`.
    /// Sus píxeles > 0 son los de `mask`. nil sin `SubjectOptions.computeGarmentRegions`, sin pose
    /// (recorte de cabeza), con `wholePerson`, sin máscara o con `allPeople` (ahí el mapa va por
    /// persona en `layers.persons[i].garmentRegions`): entonces la app usa el camino clásico.
    public let garmentRegions: [UInt8]?

    public init(width: Int, height: Int, people: [PersonInstance], chosenIndex: Int?, mask: [UInt8]?,
                steps: [MaskFallback], timings: [String: Double], maskCoverage: Double, layers: SubjectLayers,
                rejectedPhantoms: [RejectedPerson] = [], garmentRegions: [UInt8]? = nil) {
        self.width = width
        self.height = height
        self.people = people
        self.chosenIndex = chosenIndex
        self.mask = mask
        self.steps = steps
        self.timings = timings
        self.maskCoverage = maskCoverage
        self.layers = layers
        self.rejectedPhantoms = rejectedPhantoms
        self.garmentRegions = garmentRegions
    }
}

/// Errores propios de SubjectKit (los del motor llegan como `ColorEngineError`).
public enum SubjectError: Error, Equatable, Sendable {
    /// width o height < 1, o width * height desborda.
    case invalidDimensions(width: Int, height: Int)
    /// Una máscara de persona o su muestra de cara no mide width * height.
    case maskSizeMismatch(personId: Int, expected: Int, actual: Int)
    /// `minCoverage`, `minRegionFraction`, `bareArmsSkinFraction`, `sleeveMatchFraction` o `skinGrowMaxRatio` no finitos o
    /// fuera de 0...1; `skinLearningIterations` o `skinHaloRadius` fuera de 0...8; `skinGrowRadius`
    /// fuera de 0...64; `skinLearningMahalanobis`, `sleeveMatchMahalanobis` o `skinGrowMahalanobis`
    /// no finitos o negativos.
    case invalidOptions(String)
    /// CoreGraphics no pudo crear un contexto o una imagen.
    case graphicsUnavailable
    /// Formato de pixel buffer de Vision no soportado.
    case unsupportedPixelFormat(UInt32)
}
