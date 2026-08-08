import SwiftUI
import MPSupport

public struct RecoveryWindow: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @SwiftUI.State private var isPresented = false

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.base) {
      Text(MPString.thisMac.recoveryPhrase)
        .font(MPFont.sectionTitle)
      RecoveryPhraseView(store: store, actions: actions, isPresented: $isPresented)
    }
    .padding(MPSpace.open)
    .frame(width: 480)
  }
}
