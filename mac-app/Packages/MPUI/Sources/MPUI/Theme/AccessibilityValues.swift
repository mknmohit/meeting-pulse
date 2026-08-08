import AppKit
import SwiftUI

private struct MPIncreaseContrastKey: EnvironmentKey {
  static let defaultValue = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
}

public extension EnvironmentValues {
  var mpIncreaseContrast: Bool {
    get { self[MPIncreaseContrastKey.self] }
    set { self[MPIncreaseContrastKey.self] = newValue }
  }
}
