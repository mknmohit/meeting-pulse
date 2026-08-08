import SwiftUI
import MPCore
import MPSupport

public struct MenuBarContent: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    Text(store.plateHeadline)
      .font(MPFont.rowLabel)
    Text(store.reasonLine)
      .font(MPFont.caption)
      .foregroundStyle(.secondary)
    Divider()

    Menu(MPString.menuBar.setBusy) {
      ForEach(ManualOverride.Duration.allCases) { duration in
        Button(MPString.mast.durationLabel(duration)) {
          Task { await actions.setBusy(for: duration) }
        }
      }
    }

    Button(MPString.menuBar.setAvailable) {
      Task { await actions.setAvailable(for: store.preferredDuration) }
    }

    if store.hasOverride {
      Button(MPString.menuBar.backToAutomatic) {
        Task { await actions.clearOverride() }
      }
    }

    Toggle(MPString.menuBar.callsAreOkay, isOn: callsOkayBinding)
    Divider()
    Button(MPString.menuBar.openStation) {
      actions.openStation()
    }
    Button(MPString.menuBar.quit) {
      actions.quit()
    }
  }

  private var callsOkayBinding: Binding<Bool> {
    Binding(
      get: { store.callsOkay },
      set: { value in
        store.callsOkay = value
        Task { await actions.setCallsOkay(value) }
      }
    )
  }
}
