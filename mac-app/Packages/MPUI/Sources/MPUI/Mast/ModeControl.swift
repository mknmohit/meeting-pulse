import SwiftUI
import MPCore
import MPSupport

public struct ModeControl: View {
  private let store: PulseStore
  private let actions: any PulseActions

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(spacing: MPSpace.tight) {
      Picker("", selection: modeBinding) {
        Text(MPString.mast.modeBusy).tag(PulseMode.busy)
        Text(MPString.mast.modeAutomatic).tag(PulseMode.automatic)
        Text(MPString.mast.modeAvailable).tag(PulseMode.available)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if store.mode != .automatic {
        HStack {
          Text(MPString.mast.duration)
            .font(MPFont.rowLabel)
            .foregroundStyle(MPColor.chalk)
          Spacer()
          Picker("", selection: durationBinding) {
            ForEach(ManualOverride.Duration.allCases) { duration in
              Text(MPString.mast.durationLabel(duration)).tag(duration)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }
      }
    }
    .frame(width: MPShape.plateWidth)
  }

  private var modeBinding: Binding<PulseMode> {
    Binding(
      get: { store.mode },
      set: { mode in
        switch mode {
        case .busy:
          Task { await actions.setBusy(for: store.preferredDuration) }
        case .available:
          Task { await actions.setAvailable(for: store.preferredDuration) }
        case .automatic:
          Task { await actions.clearOverride() }
        }
      }
    )
  }

  private var durationBinding: Binding<ManualOverride.Duration> {
    Binding(
      get: { store.preferredDuration },
      set: { duration in
        store.preferredDuration = duration
        switch store.mode {
        case .busy:
          Task { await actions.setBusy(for: duration) }
        case .available:
          Task { await actions.setAvailable(for: duration) }
        case .automatic:
          break
        }
      }
    )
  }
}
