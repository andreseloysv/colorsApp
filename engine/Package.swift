// swift-tools-version:5.9
// Paquete Swift del motor de color: target C "CColorEngine" (la misma fuente
// que compila a WASM) y un wrapper Swift fino "ColorEngine". Sin unsafeFlags:
// la no-contracción FMA la garantiza el pragma STDC FP_CONTRACT OFF en cada .c.
import PackageDescription

let package = Package(
    name: "ColorEngine",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ColorEngine", targets: ["ColorEngine"]),
    ],
    targets: [
        .target(
            name: "CColorEngine",
            path: "Sources/CColorEngine",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ColorEngine",
            dependencies: ["CColorEngine"],
            path: "Sources/ColorEngine"
        ),
        .testTarget(
            name: "ColorEngineTests",
            dependencies: ["ColorEngine"],
            path: "tests/ColorEngineTests"
        ),
    ],
    cLanguageStandard: .c11
)
