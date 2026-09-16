// Puerta de todo el movimiento ambiental: decide si una animación decorativa corre y le
// da el tiempo. Corre solo si (1) «Reducir movimiento» está apagado, (2) la escena está
// activa (en segundo plano o inactiva se pausa), (3) la vista es visible (dentro del
// área visible de su ScrollView y presente en pantalla), (4) la pantalla no la ha
// desactivado con `.ambientMotion(false)` (p. ej. una pestaña oculta con opacidad 0) y
// (5) el teléfono no está en Ahorro de energía ni en reposo por inactividad
// (`AmbientActivity.swift`, FIDELITY.md §1.1).
// Cuando no corre, el `TimelineView` queda en pausa: no se programa ningún fotograma
// (0 CPU). Tope: 30 fps (`MotionSpec.ambientFramesPerSecond`).
import SwiftUI

/// Política pura (los tests la ejercitan sin vistas).
struct MotionPolicy: Sendable, Hashable {
    var reduceMotion: Bool
    var scenePhase: ScenePhase
    var isVisible: Bool
    var isEnabled: Bool
    /// Ahorro de energía y reposo tras 30 s sin toques (FIDELITY.md §1.1).
    var activity: AmbientActivityState = .active

    /// Movimiento decorativo en marcha.
    var isRunning: Bool {
        !reduceMotion && scenePhase == .active && isVisible && isEnabled && activity.allowsAmbientMotion
    }

    /// Qué muestra un efecto cuando no corre: con «Reducir movimiento», su estado de
    /// reposo quieto; en pausa (fondo, fuera de pantalla), el último fotograma.
    var showsRestState: Bool { reduceMotion }
}

// MARK: - Entorno

private struct AmbientMotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ForceReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MotionTimeOverrideKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// false = el movimiento ambiental de este subárbol se pausa (pestaña oculta, hoja encima…).
    var ambientMotionEnabled: Bool {
        get { self[AmbientMotionEnabledKey.self] }
        set { self[AmbientMotionEnabledKey.self] = newValue }
    }

    /// Fuerza el comportamiento de «Reducir movimiento» (tests, galería con `-uiReduceMotion 1`).
    var forceReducedMotion: Bool {
        get { self[ForceReducedMotionKey.self] }
        set { self[ForceReducedMotionKey.self] = newValue }
    }

    /// Tiempo fijo (s) para capturas y tests deterministas: los efectos se dibujan en ese
    /// instante sin `TimelineView`.
    var motionTimeOverride: Double? {
        get { self[MotionTimeOverrideKey.self] }
        set { self[MotionTimeOverrideKey.self] = newValue }
    }
}

extension View {
    /// Activa o pausa el movimiento ambiental del subárbol. Uso típico en la raíz de pestañas:
    /// `.ambientMotion(selection == tab)` junto a `.opacity(selection == tab ? 1 : 0)`.
    func ambientMotion(_ enabled: Bool) -> some View {
        environment(\.ambientMotionEnabled, enabled)
    }

    /// Comportamiento de «Reducir movimiento» forzado (además del ajuste del sistema).
    func forceReducedMotion(_ reduced: Bool = true) -> some View {
        environment(\.forceReducedMotion, reduced)
    }

    /// Congela todos los efectos en el instante `time` (s).
    func motionTime(_ time: Double?) -> some View {
        environment(\.motionTimeOverride, time)
    }
}

// MARK: - Registro de actividad (tests y galería)

/// Cuántos efectos ambientales están corriendo ahora mismo, por ámbito
/// (`.motionActivityScope(_:)`). Se actualiza solo cuando cambia el estado de una puerta
/// (aparece, desaparece, entra en pausa o reanuda), nunca por fotograma.
@MainActor
final class MotionActivityMonitor {
    static let shared = MotionActivityMonitor()
    private var entries: [UUID: (scope: String?, running: Bool)] = [:]

    /// Efectos con el reloj en marcha (en `scope`, o todos si es nil).
    func runningCount(scope: String? = nil) -> Int {
        entries.values.filter { $0.running && (scope == nil || $0.scope == scope) }.count
    }

    /// Efectos presentes, en marcha o en pausa (en `scope`, o todos si es nil).
    func registeredCount(scope: String? = nil) -> Int {
        entries.values.filter { scope == nil || $0.scope == scope }.count
    }

    func update(_ id: UUID, scope: String?, running isRunning: Bool) {
        entries[id] = (scope, isRunning)
    }

    func remove(_ id: UUID) {
        entries[id] = nil
    }
}

private struct MotionActivityScopeKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Etiqueta con la que los efectos del subárbol se registran en `MotionActivityMonitor`.
    var motionActivityScope: String? {
        get { self[MotionActivityScopeKey.self] }
        set { self[MotionActivityScopeKey.self] = newValue }
    }
}

extension View {
    func motionActivityScope(_ scope: String?) -> some View {
        environment(\.motionActivityScope, scope)
    }
}

// MARK: - Visibilidad

/// true si la vista está en pantalla (entre `onAppear` y `onDisappear`) y su rectángulo
/// local corta el área visible de su ScrollView más cercano (sin ScrollView = visible).
/// La geometría solo avisa cuando el booleano cambia (no por fotograma de desplazamiento).
struct VisibilityTracker: ViewModifier {
    @Binding var isVisible: Bool
    @State private var inScrollBounds = true
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                let local = CGRect(origin: .zero, size: proxy.size)
                guard local.width > 0, local.height > 0 else { return false }
                guard let visible = proxy.bounds(of: .scrollView) else { return true }
                return visible.intersects(local)
            } action: { newValue in
                inScrollBounds = newValue
                publish()
            }
            .onAppear {
                onScreen = true
                publish()
            }
            .onDisappear {
                onScreen = false
                publish()
            }
    }

    private func publish() {
        let value = onScreen && inScrollBounds
        if isVisible != value { isVisible = value }
    }
}

// MARK: - Reloj ambiental

/// Reloj de un efecto decorativo. `content(nil)` = estado de reposo quieto («Reducir
/// movimiento»); `content(t)` = t segundos desde que apareció la vista.
struct AmbientTimeline<Content: View>: View {
    var frameInterval: Double = MotionSpec.ambientFrameInterval
    @ViewBuilder let content: (Double?) -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    @Environment(\.ambientMotionEnabled) private var enabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionTimeOverride) private var fixedTime
    @Environment(\.motionActivityScope) private var scope
    @Environment(\.ambientActivity) private var activity
    @State private var isVisible = true
    @State private var origin = Date()
    @State private var id = UUID()
    @State private var isPresent = false

    init(frameInterval: Double = MotionSpec.ambientFrameInterval, @ViewBuilder content: @escaping (Double?) -> Content) {
        self.frameInterval = frameInterval
        self.content = content
    }

    private var policy: MotionPolicy {
        MotionPolicy(reduceMotion: systemReduceMotion || forcedReduceMotion, scenePhase: scenePhase,
                     isVisible: isVisible, isEnabled: enabled, activity: activity)
    }

    /// El reloj del `TimelineView` avanza (ni reposo, ni tiempo fijo, ni pausa).
    private var clockRunning: Bool { policy.isRunning && fixedTime == nil }

    var body: some View {
        let policy = policy
        Group {
            if policy.showsRestState {
                content(nil)
            } else if let fixedTime {
                content(fixedTime)
            } else {
                TimelineView(.animation(minimumInterval: frameInterval, paused: !policy.isRunning)) { context in
                    content(max(0, context.date.timeIntervalSince(origin)))
                }
            }
        }
        .modifier(VisibilityTracker(isVisible: $isVisible))
        .onAppear {
            isPresent = true
            MotionActivityMonitor.shared.update(id, scope: scope, running: clockRunning)
        }
        .onChange(of: clockRunning) { _, running in
            if isPresent { MotionActivityMonitor.shared.update(id, scope: scope, running: running) }
        }
        .onDisappear {
            isPresent = false
            MotionActivityMonitor.shared.remove(id)
        }
    }
}
