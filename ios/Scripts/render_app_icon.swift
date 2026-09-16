// Icono de la app ChromaSol (1024 × 1024 px) renderizado en macOS con ImageRenderer desde el
// MISMO código vectorial del emblema que usa la app (Design/Brand). Escribe tres PNG opacos
// sRGB 8 bits en el catálogo: claro (any), oscuro (dark) y tintado (tinted, en grises).
//
//   sh ios/Scripts/render_app_icon.sh                 # regenera el AppIcon.appiconset
//   sh ios/Scripts/render_app_icon.sh --preview <png> # además, una hoja de prueba
//
// (El .sh compila este fichero junto a BrandKeyframes.swift, BrandPalette.swift y
// ChromaSolEmblem.swift con swiftc para macOS y lo ejecuta.)
import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct RenderAppIcon {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let outDir = value("--out") else {
            FileHandle.standardError.write(Data("uso: render_app_icon --out <AppIcon.appiconset> [--preview <png>]\n".utf8))
            exit(2)
        }
        let light = try render(ChromaSolEmblem(style: .appIcon, scheme: .light, glow: false), side: 1024)
        let dark = try render(ChromaSolEmblem(style: .appIcon, scheme: .dark, glow: false), side: 1024)
        let tinted = try grayscale(dark)
        try writePNG(light, to: URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-1024.png"))
        try writePNG(dark, to: URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-1024-dark.png"))
        try writePNG(tinted, to: URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-1024-tinted.png"))
        print("render_app_icon: AppIcon-1024.png, AppIcon-1024-dark.png, AppIcon-1024-tinted.png (\(light.width)x\(light.height)) en \(outDir)")

        if let preview = value("--preview") {
            let sheet = HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 16) {
                    ChromaSolEmblem(style: .full, scheme: .light).frame(width: 320, height: 320)
                    ChromaSolEmblem(style: .full, scheme: .dark).frame(width: 320, height: 320)
                        .background(Color(brand: 0x15130E))
                }
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ChromaSolEmblem(style: .compact, scheme: .light).frame(width: 32, height: 32)
                        ChromaSolEmblem(style: .compact, scheme: .light).frame(width: 64, height: 64)
                        ChromaSolEmblem(style: .compact, scheme: .light).frame(width: 160, height: 160)
                    }
                    .padding(8).background(Color(brand: 0xFCF9F1))
                    HStack(spacing: 12) {
                        ChromaSolEmblem(style: .compact, scheme: .dark).frame(width: 32, height: 32)
                        ChromaSolEmblem(style: .compact, scheme: .dark).frame(width: 64, height: 64)
                        ChromaSolEmblem(style: .compact, scheme: .dark).frame(width: 160, height: 160)
                    }
                    .padding(8).background(Color(brand: 0x15130E))
                    HStack(spacing: 12) {
                        iconTile(light, 180)
                        iconTile(dark, 180)
                        iconTile(tinted, 60)
                    }
                }
            }
            .padding(24)
            .background(Color(brand: 0xEBE8E0))
            let image = try render(sheet, side: nil)
            try writePNG(image, to: URL(fileURLWithPath: preview))
            print("render_app_icon: hoja de prueba \(image.width)x\(image.height) en \(preview)")
        }
    }

    /// Icono con la máscara aproximada de iOS (superelipse ≈ esquina continua del 22,37 %).
    @MainActor
    static func iconTile(_ image: CGImage, _ side: CGFloat) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
    }

    @MainActor
    static func render<V: View>(_ view: V, side: CGFloat?) throws -> CGImage {
        let content = side.map { AnyView(view.frame(width: $0, height: $0)) } ?? AnyView(view)
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        guard let cg = renderer.cgImage else { throw RenderError.failed }
        return try opaqueSRGB(cg)
    }

    /// Copia en sRGB 8 bits sin alfa (el icono de la app no admite transparencia).
    static func opaqueSRGB(_ image: CGImage) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RenderError.failed }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = ctx.makeImage() else { throw RenderError.failed }
        return out
    }

    /// Variante tintada: luminancia Rec. 709 del icono oscuro en grises opacos.
    static func grayscale(_ image: CGImage) throws -> CGImage {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width, space: space,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw RenderError.failed }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let gray = ctx.makeImage() else { throw RenderError.failed }
        return try opaqueSRGB(gray)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.failed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.failed }
    }

    enum RenderError: Error { case failed }
}
