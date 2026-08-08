import SwiftUI

public struct MPRefreshable: ViewModifier {
  private let action: @MainActor () async -> Void

  public init(action: @escaping @MainActor () async -> Void) {
    self.action = action
  }

  public func body(content: Content) -> some View {
    content.refreshable {
      await action()
    }
  }
}

public extension View {
  func mpRefreshable(action: @escaping @MainActor () async -> Void) -> some View {
    modifier(MPRefreshable(action: action))
  }
}
