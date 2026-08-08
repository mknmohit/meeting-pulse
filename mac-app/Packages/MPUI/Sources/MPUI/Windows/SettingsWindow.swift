import SwiftUI

public struct SettingsWindow: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    ThisMacSection(store: store, actions: actions)
      .frame(minWidth: 520, minHeight: 580)
  }
}
