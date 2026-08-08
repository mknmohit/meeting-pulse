import SwiftUI
import MPCore
import MPSupport

public struct PairingWindow: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.base) {
      Text(MPString.sharing.headline)
        .font(MPFont.sectionTitle)
      if let code = store.pairingCode {
        Text(PairingCodeFormat.display(code))
          .font(MPFont.code)
        MPCopyButton(title: MPString.sharing.copyCode, value: PairingCodeFormat.display(code))
      } else {
        MPEmptyState(
          headline: MPString.sharing.emptyHeadline,
          detail: MPString.sharing.emptyBody,
          actionTitle: MPString.sharing.createLink
        ) {
          Task { await actions.createViewerLink() }
        }
      }
    }
    .padding(MPSpace.open)
    .frame(width: 480)
  }
}
