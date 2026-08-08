import Foundation

@MainActor
public struct AppEnvironment {
  private let openWindowAction: (String) -> Void
  private let activateAction: () -> Void

  public init(
    openWindow: @escaping (String) -> Void,
    activate: @escaping () -> Void
  ) {
    openWindowAction = openWindow
    activateAction = activate
  }

  public func openWindow(id: String) {
    activateAction()
    openWindowAction(id)
  }
}
