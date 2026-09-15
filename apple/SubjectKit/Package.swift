// swift-tools-version:6.0
// SubjectKit: extracción del sujeto con Apple Vision (instancias de persona,
// pose y landmarks de cara) para producir las máscaras que consume el motor C.
// Vision solo DETECTA; la geometría de regiones de ropa y la exclusión de piel
// las hace el motor (ColorEngine: ce_mask_clothing_regions, ce_mask_cut_head,
// ce_skin_model_fit, ce_mask_exclude_skin) para que la web futura comparta
// exactamente la misma lógica (docs/DECISIONS.md, ADR-010).
//
// Productos:
//   - SubjectKit (librería, iOS 17 / macOS 14): SubjectExtractor.
//   - visionmask (ejecutable macOS): máscaras, capas y raster exactos de la app
//     para analizarlos con `ce batch` (make visionmask-people).
// Sin unsafeFlags ni capabilities de cuenta de pago; sin red.
import PackageDescription

let package = Package(
    name: "SubjectKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SubjectKit", targets: ["SubjectKit"]),
        .executable(name: "visionmask", targets: ["visionmask"]),
    ],
    dependencies: [
        .package(path: "../../engine"),
    ],
    targets: [
        .target(
            name: "SubjectKit",
            dependencies: [.product(name: "ColorEngine", package: "engine")],
            path: "Sources/SubjectKit"
        ),
        .executableTarget(
            name: "visionmask",
            dependencies: ["SubjectKit", .product(name: "ColorEngine", package: "engine")],
            path: "Sources/visionmask"
        ),
        .testTarget(
            name: "SubjectKitTests",
            dependencies: ["SubjectKit", .product(name: "ColorEngine", package: "engine")],
            path: "Tests/SubjectKitTests"
        ),
    ]
)
