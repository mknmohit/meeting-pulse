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
      HStack(spacing: MPSpace.hair) {
        modeButton(
          title: MPString.mast.modeBusy,
          mode: .busy
        )
        modeButton(
          title: MPString.mast.modeAutomatic,
          mode: .automatic
        )
        modeButton(
          title: MPString.mast.modeAvailable,
          mode: .available
        )
      }
      .padding(MPSpace.hair)
      .background(
        RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
          .fill(MPColor.groundRail)
          .overlay(
            RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
              .strokeBorder(MPColor.chalk.opacity(0.2), lineWidth: 1)
          )
      )

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

  private func modeButton(title: String, mode: PulseMode) -> some View {
    ModeRailButton(
      title: title,
      isSelected: store.mode == mode
    ) {
      modeBinding.wrappedValue = mode
    }
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

private struct ModeRailButton: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @FocusState private var isFocused
  @SwiftUI.State private var isHovered = false

  init(title: String, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(MPFont.rowValue.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? MPColor.ground : MPColor.chalk)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous)
        .fill(backgroundColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous)
        .strokeBorder(focusColor, lineWidth: 2)
        .padding(-2)
    )
    .focused($isFocused)
    .onHover { isHovered = $0 }
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var backgroundColor: Color {
    if isSelected {
      return MPColor.brass
    }
    if isHovered {
      return MPColor.chalk.opacity(0.1)
    }
    return .clear
  }

  private var focusColor: Color {
    isFocused ? (isSelected ? MPColor.ground : MPColor.brass) : .clear
  }
}
