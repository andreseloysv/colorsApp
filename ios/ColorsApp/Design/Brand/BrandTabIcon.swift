// Icono de pestaña animado (sustituye al SF Symbol de `SolarTabBar`). La pestaña ACTIVA
// reproduce su animación con los tiempos del ejemplo y lleva el halo verde claro
// (`bg-primary-fixed/40` + `box-shadow 0 0 15px rgba(188,239,199,0.85)` con `animate-pulse`);
// las INACTIVAS repiten esos mismos tiempos con amplitud reducida y la mitad de fotogramas
// (`AmbientTabIcon`, Design/Motion/TabIconAmbient.swift), como en el ejemplo, donde las
// cuatro criaturas se mueven siempre. Con Reduce Motion: todo quieto y halo fijo; el
// ambiente de las inactivas se para además en segundo plano, en Ahorro de energía y tras
// 30 s sin tocar la pantalla.
//
// Integración en SolarTabBar (Design/Components/Chrome.swift), en lugar del `Image`:
//   if let kind = BrandTabIconKind(tabIdentifier: item.accessibilityIdentifier ?? "") {
//       BrandTabIcon(kind: kind, isActive: selected)
//   } else { Image(systemName: …) }
import SwiftUI

struct BrandTabIcon: View {
    let kind: BrandTabIconKind
    var isActive: Bool
    /// Lado del dibujo (viewBox 24). El ejemplo usa 24 px; 28 pt se lee mejor en el iPhone.
    var size: CGFloat = 28
    var showsHalo: Bool = true

    var body: some View {
        Group {
            if isActive {
                BrandMotionClock(animated: true) { time, reduceMotion in
                    ZStack {
                        if showsHalo {
                            BrandActiveHalo(diameter: size + 10, pose: BrandMotion.halo(at: time, reduceMotion: reduceMotion))
                        }
                        BrandTabIconFrame(kind: kind,
                                          pose: BrandMotion.pose(kind, at: time, active: true, reduceMotion: reduceMotion),
                                          size: size)
                    }
                    .frame(width: size + 4, height: size + 4)
                }
            } else {
                // Inactiva: en el ejemplo las cuatro criaturas se mueven SIEMPRE. Aquí con el
                // reloj ambiental compartido (15 fps, amplitud 45 %, sin halo ni ping) para que la
                // barra no se vea apagada: Design/Motion/TabIconAmbient.swift.
                AmbientTabIcon(kind: kind, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Halo verde claro de la pestaña activa.
struct BrandActiveHalo: View {
    var diameter: CGFloat = 36
    var pose: TabHaloPose = .rest

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = BrandInk(scheme)
        let dark = scheme == .dark
        ZStack {
            // box-shadow 0 0 15px rgba(188,239,199,0.85): copia desenfocada (sigma ≈ 7,5).
            Circle()
                .fill(ink.haloGreen.opacity(dark ? 0.42 : 0.85))
                .blur(radius: 7.5)
            // bg-primary-fixed/40 (en oscuro, musgo que brilla: primaryContainer al 60 %).
            Circle()
                .fill(dark ? Color(brand: 0x2D5A3C, opacity: 0.6) : ink.haloGreen.opacity(0.4))
        }
        .frame(width: diameter, height: diameter)
        .opacity(pose.opacity)
        .allowsHitTesting(false)
    }
}

/// Icono + título de una pestaña con las medidas del ejemplo (`w-16 h-12`, `gap-0.5`,
/// `label-sm`; activa en `primary` y negrita, inactiva en `onSurfaceVariant`).
struct BrandTabItemLabel: View {
    let kind: BrandTabIconKind
    var isActive: Bool
    var badge: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 2) {
            BrandTabIcon(kind: kind, isActive: isActive)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .textRole(.labelSM)
                            .foregroundStyle(Theme.onSecondary)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.secondary))
                            .offset(x: 8, y: -4)
                    }
                }
            if !dynamicTypeSize.isAccessibilitySize {
                Text(kind.title)
                    .textRole(.labelSM, weight: isActive ? .bold : .semibold)
                    .foregroundStyle(isActive ? Theme.primary : Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Barra de pestañas de marca completa (vista previa y referencia de integración): pergamino
/// esmerilado al 90 %, filo superior ámbar al 15 % y sombra `0 -3px 16px rgba(234,179,8,0.12)`
/// del Feed del ejemplo.
struct BrandTabBarPreview: View {
    @Binding var selection: BrandTabIconKind

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BrandTabIconKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    BrandTabItemLabel(kind: kind, isActive: kind == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
                .accessibilityAddTraits(kind == selection ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("brand.\(kind.tabIdentifier)")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(height: Sizes.tabBar)
        .background {
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.surface.opacity(0.9))
                Rectangle()
                    .fill(Color(brand: 0xF59E0B, opacity: scheme == .dark ? 0.22 : 0.15))
                    .frame(height: 1 / max(displayScale, 1))
            }
            .shadow(color: Color(brand: 0xEAB308, opacity: scheme == .dark ? 0.10 : 0.12), radius: 8, x: 0, y: -3)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
