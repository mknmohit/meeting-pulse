import SwiftUI
import MPSupport

public struct DiagnosticsWindow: View {
  private let store: PulseStore

  public init(store: PulseStore) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.tight) {
      Text(MPString.diagnostics.headline)
        .font(MPFont.sectionTitle)
      LabeledContent(MPString.diagnostics.state, value: store.plateHeadline)
      LabeledContent(MPString.diagnostics.connection, value: store.reasonLine)
      Text(MPString.diagnostics.privacy)
        .font(MPFont.caption)
        .foregroundStyle(.secondary)
        .padding(.top, MPSpace.tight)
    }
    .padding(MPSpace.open)
    .frame(width: 480)
  }
}
