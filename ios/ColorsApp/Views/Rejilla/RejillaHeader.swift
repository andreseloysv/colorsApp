// Cabecera de la Rejilla con la marca y las luces del ejemplo (docs/design/FIDELITY.md §5 R1–R3,
// §2.1 y §2.2): logotipo ChromaSol de 32 pt + «ChromaSol» + «REJILLA», botón de sol de 44 pt con
// destello solar (12 s, 0→180→0°, resplandor ámbar) y avatar local con anillo, halo e insignia «✦»,
// sobre el pergamino esmerilado con sombra y filo ámbar.
// Funciones reales (sin inventar nada):
//   · sol    → otra combinación al azar (sube hasta la tarjeta; con búsqueda activa, abre su detalle)
//   · avatar → Jardín; la insignia «✦» aparece solo si hay combinaciones desbloqueadas desde la
//              última vez que se abrió el Jardín desde aquí (`RejillaAvatarBadge`)
// La cápsula «20/348» de la versión anterior desaparece: el recuento con barra ya está en
// «20 de 348 desbloqueadas» y el filtro en el chip «Desbloqueadas».
// Movimiento: los relojes se pausan con `.ambientMotion(false)` (pestaña oculta), en segundo plano,
// fuera de pantalla y con «Reducir movimiento» (reposo quieto).
import SwiftUI

struct RejillaHeader: View {
    /// Rótulo de sección («Rejilla», «Rejilla · ejemplo»).
    let section: String
    var onSun: () -> Void
    var onAvatar: (() -> Void)?
    /// Combinaciones nuevas para el Jardín (0 = sin insignia).
    var newUnlocks: Int = 0

    @Environment(\.ambientMotionEnabled) private var ambientEnabled

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ChromaSolLockup(section: section, showsDot: false, animated: ambientEnabled)
                .accessibilityIdentifier("rejilla.brand")
            Spacer(minLength: Spacing.sm)
            Button(action: onSun) {
                ZStack {
                    SunHalo()
                        .frame(width: 36, height: 36)
                    Image(systemName: "sun.max")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .solarSparkle(glow: true)
                }
                .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                .contentShape(Circle())
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Otra combinación al azar")
            .accessibilityIdentifier("rejilla.sun")
            if let onAvatar {
                Button(action: onAvatar) {
                    RejillaGardenAvatar(showsBadge: newUnlocks > 0)
                        .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel(RejillaAvatarBadge.accessibilityLabel(newUnlocks: newUnlocks))
                .accessibilityIdentifier("rejilla.avatar")
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { FrostedHeaderBackground() }
    }
}

/// Avatar local (el jardín del teléfono, sin foto ni cuenta): el MISMO personaje del brote en
/// maceta que usan el Feed, Extraer y el Jardín (`BrandTabIconFrame(kind: .jardin)`) sobre un
/// círculo de 32 pt melocotón→musgo, con `p-0.5 bg-secondary-fixed`, anillo `amber-300/60`,
/// halo `0 0 12px` ámbar 35 % e insignia «✦». La marca no cambia al cambiar de pestaña.
struct RejillaGardenAvatar: View {
    var showsBadge: Bool

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.secondaryFixed, Tone.moss.badgeFill],
                                 center: UnitPoint(x: 0.5, y: 0.35), startRadius: 2, endRadius: 20))
            .overlay {
                BrandTabIconFrame(kind: .jardin, size: 23)
                    .offset(y: 1.5)
            }
            .frame(width: Sizes.avatar, height: Sizes.avatar)
            .glowRing(.header, sparkleBadge: showsBadge)
            .accessibilityHidden(true)
    }
}

/// Insignia «✦» del avatar: combinaciones desbloqueadas desde la última apertura del Jardín.
enum RejillaAvatarBadge {
    /// Clave compartida con el Jardín (FIDELITY.md §2.2): recuento de desbloqueadas ya vistas.
    static let lastSeenKey = "jardin.lastSeenUnlockCount"

    /// Nuevas = desbloqueadas − vistas (nunca negativo; sin registro previo cuentan todas).
    static func newUnlocks(unlocked: Int, lastSeen: Int?) -> Int {
        max(0, unlocked - max(0, lastSeen ?? 0))
    }

    static func accessibilityLabel(newUnlocks: Int) -> String {
        switch newUnlocks {
        case ...0: "Tu jardín"
        case 1: "Tu jardín, 1 combinación nueva"
        default: "Tu jardín, \(newUnlocks) combinaciones nuevas"
        }
    }
}
