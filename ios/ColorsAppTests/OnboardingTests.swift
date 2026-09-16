// Pendientes de F6/F7: el arranque instala PhotoKitScanRunner, el Feed presenta el
// escaneo del carrete la primera vez (sin escaneo inicial ni salto previo, nunca
// con un atajo de depuración ni en XCTest) con "Ahora no", y la hoja de la
// Rejilla reutiliza ComboDetailView.
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

@MainActor
final class OnboardingTests: XCTestCase {
    func testBootstrapInstallsPhotoKitScanRunner() throws {
        let env = try AppEnvironment.bootstrap(bundle: Bundle(for: AppDatabase.self))
        XCTAssertTrue(env.scanRunner is PhotoKitScanRunner, "bootstrap instala el escaneo real")
        XCTAssertTrue(env.installPhotoKitScanRunner() === (env.scanRunner as AnyObject), "no se duplica")
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }

    func testPresentationRule() {
        XCTAssertTrue(FeedOnboarding.shouldPresent(initialScanDone: false, skipped: false, debugScreen: false, runningTests: false))
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: true, skipped: false, debugScreen: false, runningTests: false))
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: false, skipped: true, debugScreen: false, runningTests: false))
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: false, skipped: false, debugScreen: true, runningTests: false))
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: false, skipped: false, debugScreen: false, runningTests: true))
    }

    func testSkipFlowPersistsAndDoesNotPresentAgain() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        var done = try await env.settings.bool(.initialScanDone)
        var skipped = try await env.settings.bool(.scanOnboardingSkipped)
        XCTAssertTrue(FeedOnboarding.shouldPresent(initialScanDone: done, skipped: skipped, debugScreen: false, runningTests: false),
                      "primera vez: se presenta")
        // "Ahora no" / cerrar la hoja sin escanear.
        await FeedOnboarding.markDismissed(settings: env.settings)
        skipped = try await env.settings.bool(.scanOnboardingSkipped)
        XCTAssertTrue(skipped)
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: done, skipped: skipped, debugScreen: false, runningTests: false),
                       "saltado: no se vuelve a presentar")

        // Con el escaneo hecho, cerrar no marca el salto.
        let other = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        try await other.settings.setBool(.initialScanDone, true)
        await FeedOnboarding.markDismissed(settings: other.settings)
        let otherSkipped = try await other.settings.bool(.scanOnboardingSkipped)
        XCTAssertFalse(otherSkipped)
        done = try await other.settings.bool(.initialScanDone)
        XCTAssertFalse(FeedOnboarding.shouldPresent(initialScanDone: done, skipped: otherSkipped, debugScreen: false, runningTests: false))

        // La hoja con "Ahora no" y el detalle de la Rejilla se construyen.
        // (UIHostingController: ImageRenderer aborta al liberar vistas con .onAppear/.task en NavigationStack, iOS 27.)
        let sheet = UIHostingController(rootView: ScanOnboardingView(onSkip: {}).environmentObject(env))
        XCTAssertGreaterThan(sheet.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 100)
        let combo = try XCTUnwrap(env.dictionary.combo(id: 12))
        let detail = UIHostingController(rootView: RejillaComboDetailView(combo: combo).environmentObject(env))
        XCTAssertGreaterThan(detail.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 100)
    }
}
