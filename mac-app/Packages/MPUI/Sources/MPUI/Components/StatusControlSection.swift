import SwiftUI
import MPCore
import MPSupport

public struct StatusControlSection: View {
  @Bindable private var store: PulseStore
  private let actions: any PulseActions
  @SwiftUI.State private var customHours: Int
  @SwiftUI.State private var customMinutes: Int

  public init(store: PulseStore, actions: any PulseActions) {
    _store = Bindable(wrappedValue: store)
    self.actions = actions
    let initialMinutes = store.preferredDuration.customMinutes ?? 30
    _customHours = SwiftUI.State(initialValue: initialMinutes / 60)
    _customMinutes = SwiftUI.State(initialValue: initialMinutes % 60)
  }

  public var body: some View {
    MPGroup(title: MPString.station.status) {
      VStack(alignment: .leading, spacing: MPSpace.tight) {
        Text(MPString.station.statusDetail)
          .font(MPFont.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        TimelineView(.periodic(from: .now, by: 30)) { context in
          VStack(alignment: .leading, spacing: MPSpace.hair) {
            HStack(spacing: MPSpace.tight) {
              Text(currentStatusLabel)
                .font(MPFont.rowLabel.weight(.semibold))
              Spacer(minLength: MPSpace.tight)
              if store.isOverrideActionInFlight {
                ProgressView()
                  .controlSize(.small)
                  .accessibilityLabel(MPString.station.updating)
              }
            }
            Text(statusLine(at: context.date))
              .font(MPFont.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Divider()

        Picker(MPString.mast.duration, selection: $store.preferredDuration) {
          ForEach(ManualOverride.Duration.allCases) { duration in
            Text(MPString.mast.durationLabel(duration)).tag(duration)
          }
          Divider()
          Text(MPString.station.customDuration)
            .tag(ManualOverride.Duration.custom(minutes: customTotalMinutes))
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(MPString.mast.duration)

        if store.preferredDuration.customMinutes != nil {
          customDurationEditor
        }

        HStack(spacing: MPSpace.tight) {
          Button {
            let duration = store.preferredDuration
            Task { await actions.setBusy(for: duration) }
          } label: {
            Label(MPString.station.setBusy, systemImage: "moon.fill")
          }
          .buttonStyle(.borderedProminent)
          .tint(MPColor.brass)
          .disabled(!store.preferredDuration.isValid)

          Button {
            let duration = store.preferredDuration
            Task { await actions.setAvailable(for: duration) }
          } label: {
            Label(MPString.station.setAvailable, systemImage: "checkmark.circle")
          }
          .buttonStyle(.bordered)
          .disabled(!store.preferredDuration.isValid)
        }

        if store.hasOverride {
          Button {
            Task { await actions.clearOverride() }
          } label: {
            Label(MPString.station.backToAutomatic, systemImage: "arrow.uturn.backward")
          }
          .buttonStyle(.link)
        }

        if store.lastError == .override {
          Label(MPString.error.override, systemImage: "exclamationmark.triangle")
            .font(MPFont.caption)
            .foregroundStyle(MPColor.brass)
        }
      }
    }
    .onChange(of: customHours) { _, _ in
      updateCustomDuration()
    }
    .onChange(of: customMinutes) { _, _ in
      updateCustomDuration()
    }
    .onChange(of: store.preferredDuration) { _, duration in
      guard let minutes = duration.customMinutes else {
        return
      }
      customHours = minutes / 60
      customMinutes = minutes % 60
    }
  }

  private var customDurationEditor: some View {
    VStack(alignment: .leading, spacing: MPSpace.hair) {
      HStack(spacing: MPSpace.base) {
        Stepper(value: $customHours, in: 0...24) {
          Text("\(MPString.station.hours): \(customHours)")
            .font(MPFont.rowLabel)
        }
        .accessibilityLabel(MPString.station.hours)

        Stepper(value: $customMinutes, in: 0...59) {
          Text("\(MPString.station.minutes): \(customMinutes)")
            .font(MPFont.rowLabel)
        }
        .accessibilityLabel(MPString.station.minutes)
      }

      Text(customDurationIsValid
        ? MPString.station.customDurationDetail
        : MPString.station.invalidCustomDuration
      )
      .font(MPFont.caption)
      .foregroundStyle(customDurationIsValid ? .secondary : MPColor.brass)
    }
  }

  private var customTotalMinutes: Int {
    customHours * 60 + customMinutes
  }

  private var customDurationIsValid: Bool {
    ManualOverride.Duration.custom(minutes: customTotalMinutes).isValid
  }

  private var currentStatusLabel: String {
    switch store.mode {
    case .busy:
      return MPString.mast.modeBusy
    case .available:
      return MPString.mast.modeAvailable
    case .automatic:
      return MPString.mast.reasonAutomatic
    }
  }

  private func statusLine(at date: Date) -> String {
    if store.isOverrideActionInFlight {
      return MPString.station.updating
    }
    return store.reasonLine(at: date)
  }

  private func updateCustomDuration() {
    guard store.preferredDuration.customMinutes != nil else {
      return
    }
    store.preferredDuration = .custom(minutes: customTotalMinutes)
  }
}
