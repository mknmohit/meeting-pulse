import SwiftUI
import MPSupport

public struct CallsOkaySwitch: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    HStack {
      Text(MPString.mast.callsAreOkay)
        .font(MPFont.rowLabel)
        .foregroundStyle(.primary)
      Spacer()
      Toggle("", isOn: binding)
        .labelsHidden()
        .toggleStyle(.switch)
    }
    .frame(width: MPShape.plateWidth)
  }

  private var binding: Binding<Bool> {
    Binding(
      get: { store.callsOkay },
      set: { value in
        store.callsOkay = value
        Task { await actions.setCallsOkay(value) }
      }
    )
  }
}
