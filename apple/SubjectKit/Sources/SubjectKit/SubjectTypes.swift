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
    /// Opciones de `excludeSkin` (defecto del motor: ce_skin_opts_default).
    public var skinOptions: SkinOptions = .default
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

    public init(mode: SubjectMode = .largestPerson, region: RegionMode = .clothing, adaptiveSkin: Bool = true,
                selectedIndex: Int? = nil, regionOptions: RegionOptions = .default,
                skinOptions: SkinOptions = .default, minCoverage: Double = 0.0005, minRegionFraction: Double = 0.15,
                shareSkinModel: Bool = true, bareArmsSkinFraction: Double = 0.25) {
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
    }

    /// Persona más grande, solo ropa, piel adaptativa (compartida si la persona no
    /// tiene cara utilizable), regiones >= 15 % de la silueta de la pose, brazos
    /// fuera si >= 25 % es piel, suelo absoluto 0,05 % del raster.
    public static var `default`: SubjectOptions { SubjectOptions() }
}

/// Una persona detectada (o construida a mano en los tests).
public struct PersonInstance: Equatable, Sendable, Identifiable {
    /// Índice de instancia de Vision (1...n; 0 es el fondo en la máscara de instancias).
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

    public init(id: Int, mask: [UInt8], coverage: Double, bbox: CGRect, pose: Pose?, faceSampleMask: [UInt8]?,
                faceBox: CGRect? = nil) {
        self.id = id
        self.mask = mask
        self.coverage = coverage
        self.bbox = bbox
        self.pose = pose
        self.faceSampleMask = faceSampleMask
        self.faceBox = faceBox
    }

    /// Calcula `coverage` y `bbox` a partir de la máscara (`width` x `height`).
    public init(id: Int, mask: [UInt8], width: Int, height: Int, pose: Pose? = nil, faceSampleMask: [UInt8]? = nil,
                faceBox: CGRect? = nil) {
        let stats = MaskOps.stats(mask, width: width, height: height)
        self.init(id: id, mask: mask, coverage: stats.coverage, bbox: stats.bbox, pose: pose,
                  faceSampleMask: faceSampleMask, faceBox: faceBox)
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
    /// excluir piel y no había muestra de piel (propia ni compartida).
    public let upperArmsDropped: Bool
    /// Prueba de brazos desnudos (con modelo de piel y brazos pedidos): píxeles de
    /// los brazos (regiones con brazos menos sin brazos); nil si no se hizo.
    public let armPixels: Int?
    /// Píxeles de esos brazos que el modelo de piel marca como piel (sin salvaguarda).
    public let armSkinPixels: Int?
    /// true si los brazos se quitaron porque armSkinPixels >= ceil(bareArmsSkinFraction · armPixels).
    public let bareArmsDropped: Bool

    public init(source: RegionSource, bodyPixels: Int, requiredPixels: Int, poseRegionPixels: Int?,
                silhouettePixels: Int?, regionPixels: Int, regionPose: Pose?, hipsEstimated: Bool,
                headCutFraction: Double?, regionOptions: RegionOptions? = nil, upperArmsDropped: Bool = false,
                armPixels: Int? = nil, armSkinPixels: Int? = nil, bareArmsDropped: Bool = false) {
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
    /// Brazos probados en la prueba de brazos desnudos (255 = píxel de brazo); nil si no se hizo.
    public let armsMask: [UInt8]?
    /// Muestra de piel de la cara usada para el modelo (la propia o, con
    /// `shareSkinModel`, la de `skinSampleSource`); nil sin muestra o sin `adaptiveSkin`.
    public let faceSampleMask: [UInt8]?
    /// 255 donde se quitó piel; nil si no se aplicó o si saltó la salvaguarda.
    public let skinRemovedMask: [UInt8]?
    /// Máscara de esta persona al final de su cadena (región y piel), ANTES del
    /// suelo `minCoverage`: si luego se volvió a la persona completa
    /// (`.wholePerson`) o se descartó (`.none`), la máscara del motor es
    /// `SubjectLayers.finalMask`, no esta.
    public let finalMask: [UInt8]
    /// Pasos de esta persona.
    public let steps: [MaskFallback]
    /// Modelo de piel ajustado (nil si no se ajustó).
    public let skinModel: SkinModel?
    /// Píxeles que la exclusión de piel pasó a 0 (0 con la salvaguarda o sin modelo).
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

    public init(personIndex: Int, instanceId: Int, personMask: [UInt8], pose: Pose?, regionMask: [UInt8]?,
                faceSampleMask: [UInt8]?, skinRemovedMask: [UInt8]?, finalMask: [UInt8], steps: [MaskFallback],
                skinModel: SkinModel?, skinExcludedPixels: Int, skinNote: String?,
                regionDecision: RegionDecision? = nil, usedInMask: Bool = true, skinSampleSource: Int? = nil,
                silhouetteMask: [UInt8]? = nil, armsMask: [UInt8]? = nil, fallbackSource: RegionSource? = nil) {
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
    /// Personas detectadas, ordenadas por cobertura descendente (desempate por id).
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

    public init(width: Int, height: Int, people: [PersonInstance], chosenIndex: Int?, mask: [UInt8]?,
                steps: [MaskFallback], timings: [String: Double], maskCoverage: Double, layers: SubjectLayers) {
        self.width = width
        self.height = height
        self.people = people
        self.chosenIndex = chosenIndex
        self.mask = mask
        self.steps = steps
        self.timings = timings
        self.maskCoverage = maskCoverage
        self.layers = layers
    }
}

/// Errores propios de SubjectKit (los del motor llegan como `ColorEngineError`).
public enum SubjectError: Error, Equatable, Sendable {
    /// width o height < 1, o width * height desborda.
    case invalidDimensions(width: Int, height: Int)
    /// Una máscara de persona o su muestra de cara no mide width * height.
    case maskSizeMismatch(personId: Int, expected: Int, actual: Int)
    /// `minCoverage`, `minRegionFraction` o `bareArmsSkinFraction` no finitos o fuera de 0...1.
    case invalidOptions(String)
    /// CoreGraphics no pudo crear un contexto o una imagen.
    case graphicsUnavailable
    /// Formato de pixel buffer de Vision no soportado.
    case unsupportedPixelFormat(UInt32)
}
