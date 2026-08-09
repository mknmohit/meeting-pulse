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
    // The reason line is rendered without `TimelineView`. A `TimelineView`
    // in a `MenuBarExtra` body is a known crash trigger on macOS: the
    // periodic schedule combined with `MenuBehavior.menuNeedsUpdate`'s
    // re-entry path produces a render loop that exhausts the main thread's
    // stack guard within ~85 frames
    // (`EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE` inside
    // `ViewRendererHost.render`). The menu is open for a few seconds at a
    // time, so a static text snapshot of the reason line is sufficient —
    // any countdown will be re-read the next time the user opens the menu,
    // when SwiftUI re-evaluates the body against the latest store state.
    Text(store.reasonLine(at: .now, presentation: .menuBar))
      .font(MPFont.caption)
      .foregroundStyle(.secondary)
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
      get: { [store] in store.callsOkay },
      set: { [store, actions] value in
        store.callsOkay = value
        Task { await actions.setCallsOkay(value) }
      }
    )
  }
}
