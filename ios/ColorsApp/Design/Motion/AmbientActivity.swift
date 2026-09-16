// Reloj de actividad del ambiente (docs/design/FIDELITY.md §1.1). Además de «Reducir
// movimiento», la escena y la visibilidad (MotionGate.swift), lo decorativo se para
// cuando:
//   1. el teléfono está en Ahorro de energía (`isLowPowerModeEnabled`), y
//   2. nadie toca la pantalla desde hace 30 s (reposo).
// Al primer toque o desplazamiento vuelve a moverse. Sin esto, con el Feed abierto y
// quieto el proceso consumía entre el 9,6 % y el 13,4 % de un núcleo de forma continua
// (medido con `top` sobre el simulador), que en el iPhone es batería para nada.
//
// Cómo se detecta el toque: un `UILongPressGestureRecognizer(minimumPressDuration: 0)`
// instalado en la ventana con `cancelsTouchesInView = false`, `delaysTouchesBegan = false`
// y un delegado que reconoce a la vez que cualquier otro gesto: ve todos los toques sin
// robárselos a nadie (§1.1). El reposo se comprueba con un temporizador lento (2 s con 1 s
// de tolerancia): el corte cae entre 30 y 32 s y el propio temporizador no gasta nada.
//
// El estado viaja por el entorno (`\.ambientActivity`), así que los tests y las capturas
// lo fijan sin tocar ajustes del sistema: `.ambientActivity(.idle)`.
import Combine
import QuartzCore
import SwiftUI
import UIKit

// MARK: - Estado

/// Energía y actividad del usuario: lo que apaga el ambiente por encima de la pantalla.
struct AmbientActivityState: Sendable, Hashable {
    /// 30 s sin tocar la pantalla.
    var isIdle: Bool = false
    /// Ahorro de energía del sistema.
    var isLowPower: Bool = false

    /// Lo decorativo puede moverse.
    var allowsAmbientMotion: Bool { !isIdle && !isLowPower }

    static let active = AmbientActivityState()
    static let idle = AmbientActivityState(isIdle: true)
    static let lowPower = AmbientActivityState(isLowPower: true)
}

private struct AmbientActivityKey: EnvironmentKey {
    static let defaultValue = AmbientActivityState.active
}

extension EnvironmentValues {
    /// Ahorro de energía y reposo por inactividad del subárbol (lo inyecta `ambientActivityRoot()`).
    var ambientActivity: AmbientActivityState {
        get { self[AmbientActivityKey.self] }
        set { self[AmbientActivityKey.self] = newValue }
    }
}

extension View {
    /// Fija el estado de actividad del subárbol (tests, capturas y galería).
    func ambientActivity(_ state: AmbientActivityState) -> some View {
        environment(\.ambientActivity, state)
    }
}

// MARK: - Monitor

/// Vigila el Ahorro de energía y el reposo por inactividad. Uno por app: lo crea
/// `AmbientActivityRootModifier`.
@MainActor
final class AmbientActivityMonitor: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    /// Reposo tras 30 s sin toques (FIDELITY §1.1).
    static let defaultIdleDelay: TimeInterval = 30

    @Published private(set) var state = AmbientActivityState()

    private var idleDelay = AmbientActivityMonitor.defaultIdleDelay
    private var lastActivity = CACurrentMediaTime()
    private var timer: Timer?
    private weak var recognizer: UIGestureRecognizer?
    private var started = false
    /// Estado fijado por argumento de depuración: se deja de vigilar.
    private var forced: AmbientActivityState?

    override init() {
        super.init()
        // Los argumentos se leen en el init, no en `start()`: el estado forzado tiene que
        // estar puesto ANTES del primer `body` (cambiarlo desde `onAppear` llega tarde).
        #if DEBUG
        applyDebugArguments(ProcessInfo.processInfo.arguments)
        #endif
    }

    /// Arranca la vigilancia (idempotente).
    func start() {
        guard !started else { return }
        started = true
        guard forced == nil else { return }
        refreshLowPower()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(powerStateChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(sceneWokeUp), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneWokeUp), name: UIWindow.didBecomeKeyNotification, object: nil)
        attachTouchRecognizer()
        noteActivity()
        let interval = min(2, max(0.2, idleDelay / 3))
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 2
        self.timer = timer
    }

    /// Suelta el temporizador, los avisos y el gesto (tests; en la app el monitor vive con ella).
    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizer = nil
        started = false
    }

    /// Cualquier toque, desplazamiento o vuelta a primer plano: el ambiente se reanuda ya.
    func noteActivity() {
        guard forced == nil else { return }
        lastActivity = CACurrentMediaTime()
        if state.isIdle { state.isIdle = false }
    }

    /// Decide el reposo y reintenta enganchar la ventana si aún no había ninguna.
    private func tick() {
        guard forced == nil else { return }
        if recognizer == nil { attachTouchRecognizer() }
        // Seguro: sin gesto enganchado no se ven los toques, así que NUNCA se declara el
        // reposo (si no, el ambiente se quedaría congelado sin forma de despertarlo).
        let watching = recognizer?.view != nil
        let idle = watching && CACurrentMediaTime() - lastActivity >= idleDelay
        if state.isIdle != idle { state.isIdle = idle }
    }

    /// Gesto instalado y vigilando una ventana (lo comprueban los tests).
    var isWatchingTouches: Bool { recognizer?.view != nil }

    /// Configuración del gesto instalado, para los tests.
    var touchRecognizer: UIGestureRecognizer? { recognizer }

    private func refreshLowPower() {
        guard forced == nil else { return }
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        if state.isLowPower != low { state.isLowPower = low }
    }

    // `NSProcessInfoPowerStateDidChange` se publica en un hilo cualquiera: hay que saltar al principal.
    @objc private nonisolated func powerStateChanged() {
        Task { @MainActor [weak self] in self?.refreshLowPower() }
    }

    @objc private nonisolated func sceneWokeUp() {
        Task { @MainActor [weak self] in
            self?.attachTouchRecognizer()
            self?.noteActivity()
        }
    }

    // MARK: Toques

    private func attachTouchRecognizer() {
        guard recognizer == nil, let window = Self.frontWindow() else { return }
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(touched))
        gesture.name = "ambient.activity"
        gesture.minimumPressDuration = 0
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.requiresExclusiveTouchType = false
        gesture.delegate = self
        window.addGestureRecognizer(gesture)
        recognizer = gesture
    }

    @objc private func touched(_ gesture: UIGestureRecognizer) {
        noteActivity()
    }

    private static func frontWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    // El gesto solo mira: nunca cancela ni exige el fallo de otro.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        noteActivity()
        return true
    }

    // MARK: Depuración

    #if DEBUG
    /// `-uiAmbientIdle 1`, `-uiAmbientLowPower 1` (fijan el estado) y `-uiAmbientIdleDelay <s>`
    /// (acorta los 30 s para poder comprobarlo en una captura).
    func applyDebugArguments(_ arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        if let delay = value("-uiAmbientIdleDelay").flatMap(Double.init), delay > 0 { idleDelay = delay }
        var fixed = AmbientActivityState()
        var any = false
        if value("-uiAmbientIdle") == "1" { fixed.isIdle = true; any = true }
        if value("-uiAmbientLowPower") == "1" { fixed.isLowPower = true; any = true }
        if any {
            forced = fixed
            state = fixed
        }
    }
    #endif
}

// MARK: - Raíz

/// Inyecta el estado de actividad en toda la app. Se aplica UNA vez, en
/// `DesignSystemRootModifier`.
struct AmbientActivityRootModifier: ViewModifier {
    @StateObject private var monitor = AmbientActivityMonitor()

    func body(content: Content) -> some View {
        content
            .environment(\.ambientActivity, monitor.state)
            .onAppear { monitor.start() }
    }
}

extension View {
    /// Ahorro de energía y reposo tras 30 s sin toques para todo el movimiento ambiental.
    func ambientActivityRoot() -> some View {
        modifier(AmbientActivityRootModifier())
    }
}
