// Punto de enganche del sistema de diseño en la raíz de la app: comprueba al arrancar
// que las fuentes se registraron (FontRegistry, con fallback), instala el reloj de
// actividad del ambiente (Ahorro de energía y reposo de 30 s, FIDELITY.md §1.1) y, solo en DEBUG, sustituye
// la raíz por la galería de componentes con `-uiScreen design-gallery`
// (`-uiGalleryPage <página>` elige la página; `-uiAppearance light|dark` fuerza el tema).
import SwiftUI

struct DesignSystemRootModifier: ViewModifier {
    init() {
        FontRegistry.bootstrap()
    }

    func body(content: Content) -> some View {
        // Reloj de actividad del ambiente (Design/Motion/AmbientActivity.swift): Ahorro de
        // energía y reposo tras 30 s sin tocar la pantalla paran todo el movimiento decorativo.
        root(content: content).ambientActivityRoot()
    }

    @ViewBuilder
    private func root(content: Content) -> some View {
        #if DEBUG
        if DesignGalleryLaunch.isRequested {
            DesignGalleryView()
        } else if MotionGalleryLaunch.isRequested {
            // Galería de movimiento y luz (Design/Motion): -uiScreen motion-gallery.
            MotionGalleryView()
        } else if BrandGalleryLaunch.isRequested {
            // Galería de marca (Design/Brand): -uiScreen brand-gallery.
            BrandGalleryView()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Aplicar una vez a la vista raíz (ColorsAppApp).
    func designSystemRoot() -> some View {
        modifier(DesignSystemRootModifier())
    }
}
