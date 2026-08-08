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
    TimelineView(.periodic(from: .now, by: 30)) { context in
      Text(store.reasonLine(at: context.date, presentation: .menuBar))
        .font(MPFont.caption)
        .foregroundStyle(.secondary)
    }
    Divider()

    Menu {
      ForEach(ManualOverride.Duration.allCases) { duration in
        Button {
          Task { await actions.setBusy(for: duration) }
        } label: {
          Image(systemName: "moon.fill")
          Text(MPString.mast.durationLabel(duration))
        }
      }
    } label: {
      Image(systemName: "moon.fill")
      Text(MPString.menuBar.setBusy)
    }

    Menu {
      ForEach(ManualOverride.Duration.allCases) { duration in
        Button {
          Task { await actions.setAvailable(for: duration) }
        } label: {
          Image(systemName: "checkmark.circle")
          Text(MPString.mast.durationLabel(duration))
        }
      }
    } label: {
      Image(systemName: "checkmark.circle")
      Text(MPString.menuBar.setAvailable)
    }

    if store.hasOverride {
      Button {
        Task { await actions.clearOverride() }
      } label: {
        Image(systemName: "arrow.uturn.backward")
        Text(MPString.menuBar.backToAutomatic)
      }
    }

    Toggle(isOn: callsOkayBinding) {
      Image(systemName: "phone.fill")
      Text(MPString.menuBar.callsAreOkay)
    }
    Divider()
    Button {
      actions.openStation()
    } label: {
      Image(systemName: "rectangle.grid.2x2")
      Text(MPString.menuBar.openStation)
    }
    Button {
      actions.quit()
    } label: {
      Image(systemName: "power")
      Text(MPString.menuBar.quit)
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
