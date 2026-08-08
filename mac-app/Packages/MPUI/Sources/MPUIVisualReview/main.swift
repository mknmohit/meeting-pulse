import AppKit
import Foundation
import MPCore
import MPUI
import MPSupport
import SwiftUI

@MainActor
private final class ReviewActions: PulseActions {
  func setBusy(for _: ManualOverride.Duration) async {}
  func setAvailable(for _: ManualOverride.Duration) async {}
  func clearOverride() async {}
  func setCallsOkay(_: Bool) async {}
  func setDisplayName(_: String) async {}
  func checkAndPublishNow() async {}
  func createViewerLink() async {}
  func rotateViewerLink() async {}
  func revokeViewerAccess() async {}
  func loadViewers() async {}
  func removeViewer(id _: UUID) async {}
  func setLaunchAtLogin(_: Bool) throws {}
  func setOpenWindowAtLogin(_: Bool) {}
  func revealRecoveryPhrase() async {}
  func deleteEverything() async {}
  func completeOnboarding() {}
  func openAccessibilitySettings() -> Bool { false }
  func openLoginItemsSettings() {}
  func revealInFinder() {}
  func openStation() {}
  func openStation(section _: StationSection) {}
  func showOnboarding() {}
  func openPairing() {}
  func openRecovery() {}
  func openDiagnostics() {}
  func openSettings() {}
  func quit() { NSApp.terminate(nil) }
}

@main
@MainActor
struct MPUIVisualReviewApp: App {
  @SwiftUI.State private var store: PulseStore
  @SwiftUI.State private var actions = ReviewActions()

  private let scheme: ColorScheme
  private let contrastEnabled: Bool

  init() {
    let face = Self.argument(named: "--face") ?? "generic"
    let schemeName = Self.argument(named: "--scheme") ?? "dark"
    let sectionName = Self.argument(named: "--section") ?? "watch"
    let store: PulseStore
    switch face {
    case "meeting":
      store = .previewBusy()
    case "call-okay":
      store = .previewCallOkay()
    case "permission":
      store = .previewNoPermission()
    default:
      store = .preview()
    }
    store.hasCompletedOnboarding = true
    store.stationVisible = true
    switch sectionName {
    case "sharing":
      store.section = .sharing
    case "this-mac":
      store.section = .thisMac
    case "privacy":
      store.section = .privacy
    default:
      store.section = .watch
    }
    _store = SwiftUI.State(initialValue: store)
    scheme = schemeName == "light" ? .light : .dark
    contrastEnabled = CommandLine.arguments.contains("--contrast")
  }

  var body: some Scene {
    WindowGroup(MPString.station.windowTitle) {
      StationWindow(
        store: store,
        actions: actions,
        contrastOverride: contrastEnabled ? true : nil
      )
        .preferredColorScheme(scheme)
    }
    .defaultSize(width: 940, height: 620)
    .windowResizability(.contentMinSize)
  }

  private static func argument(named name: String) -> String? {
    let prefix = "\(name)="
    return CommandLine.arguments
      .first(where: { $0.hasPrefix(prefix) })
      .map { String($0.dropFirst(prefix.count)) }
  }
}
