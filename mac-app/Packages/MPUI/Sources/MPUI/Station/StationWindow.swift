import AppKit
import SwiftUI
import MPSupport

public struct StationWindow: View {
  @Bindable private var store: PulseStore
  private let actions: any PulseActions
  private let contrastOverride: Bool?
  @SwiftUI.State private var systemContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

  public init(
    store: PulseStore,
    actions: any PulseActions,
    contrastOverride: Bool? = nil
  ) {
    _store = Bindable(wrappedValue: store)
    self.actions = actions
    self.contrastOverride = contrastOverride
  }

  public var body: some View {
    NavigationSplitView {
      StationSidebar(store: store, actions: actions, selection: $store.section)
        .navigationSplitViewColumnWidth(min: 288, ideal: 288, max: 288)
    } detail: {
      StationDetail(store: store, actions: actions)
        .toolbar {
          StationToolbar(store: store, actions: actions)
        }
    }
    .frame(minWidth: 940, minHeight: 620)
    .environment(\.mpIncreaseContrast, contrastOverride ?? systemContrast)
    .onAppear {
      // Mark the station as visible and flip the activation policy to
      // `.regular` synchronously. The synchronous flip ensures the Dock icon
      // appears at the same moment SwiftUI presents the window, even before
      // the `DockVisibilityCoordinator` observer has a chance to react. The
      // observer's subsequent application is a no-op.
      if !store.stationVisible {
        store.stationVisible = true
        NSApplication.shared.setActivationPolicy(.regular)
      }
      systemContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    .onDisappear {
      // Mark the station as hidden and flip the activation policy to
      // `.accessory` synchronously. Without this, the user clicking the red
      // close button would close the window but the Dock icon would stay
      // visible until the next runloop tick (when the observer fires). The
      // synchronous flip keeps the Dock icon in lockstep with the window.
      store.stationVisible = false
      NSApplication.shared.setActivationPolicy(.accessory)
    }
  }
}

private struct StationSidebar: View {
  let store: PulseStore
  let actions: any PulseActions
  @Binding var selection: StationSection

  var body: some View {
    VStack(spacing: 0) {
      MastView(store: store, actions: actions)
      Spacer(minLength: MPSpace.snug)
      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: MPSpace.tight) {
            ForEach(StationSection.allCases) { section in
              SidebarNavigationRow(
                section: section,
                isSelected: selection == section
              ) {
                selection = section
              }
            }
          }
          .padding(.horizontal, MPSpace.tight)
          .padding(.vertical, MPSpace.tight)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        PublishRail(store: store)
      }
      .background(
        RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
          .fill(MPColor.groundRail)
      )
      .overlay(
        RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous)
          .strokeBorder(MPColor.chalk.opacity(0.16), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: MPRadius.well, style: .continuous))
      .padding(.horizontal, MPSpace.tight)
    }
    .background(MPColor.ground)
  }
}

private struct SidebarNavigationRow: View {
  let section: StationSection
  let isSelected: Bool
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @FocusState private var isFocused
  @SwiftUI.State private var isHovered = false

  init(section: StationSection, isSelected: Bool, action: @escaping () -> Void) {
    self.section = section
    self.isSelected = isSelected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: MPSpace.snug) {
        Image(systemName: section.symbol)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(isSelected ? MPColor.brass : MPColor.chalk)
          .frame(width: 20)
        Text(section.title)
          .font(MPFont.rowLabel.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(MPColor.chalk)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
      .padding(.horizontal, MPSpace.base)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: MPRadius.cell, style: .continuous)
        .fill(backgroundColor)
    )
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(isSelected ? MPColor.brass : .clear)
        .frame(width: 2, height: 20)
        .padding(.leading, MPSpace.hair)
    }
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
      return MPColor.brass.opacity(0.14)
    }
    if isHovered {
      return MPColor.chalk.opacity(0.08)
    }
    return .clear
  }

  private var focusColor: Color {
    isFocused ? MPColor.brass : .clear
  }
}

private struct StationDetail: View {
  let store: PulseStore
  let actions: any PulseActions

  var body: some View {
    Group {
      if store.deleteCompleted {
        MPEmptyState(
          headline: MPString.thisMac.everythingGone,
          detail: MPString.thisMac.nothingLeft,
          actionTitle: MPString.thisMac.setUpAgain
        ) {
          actions.quit()
        }
      } else {
        switch store.section {
        case .watch:
          WatchSection(store: store, actions: actions)
        case .sharing:
          SharingSection(store: store, actions: actions)
        case .thisMac:
          ThisMacSection(store: store, actions: actions)
        case .privacy:
          PrivacySection()
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct StationToolbar: ToolbarContent {
  let store: PulseStore
  let actions: any PulseActions

  var body: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        Task { await actions.checkAndPublishNow() }
      } label: {
        Label(MPString.station.checkNow, systemImage: "arrow.clockwise")
      }
      .help(MPString.station.checkNowHelp)
      .disabled(store.isPublishing)
      .keyboardShortcut("r", modifiers: .command)
    }
  }
}
