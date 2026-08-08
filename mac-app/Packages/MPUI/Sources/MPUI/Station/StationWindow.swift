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
      store.stationVisible = true
      systemContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    .onDisappear {
      store.stationVisible = false
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
      Spacer(minLength: MPSpace.loose)
      Divider()
      List {
        ForEach(StationSection.allCases) { section in
          Button {
            selection = section
          } label: {
            Label(section.title, systemImage: section.symbol)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .padding(.vertical, MPSpace.hair)
          .background(
            selection == section
              ? Color.accentColor.opacity(0.12)
              : Color.clear,
            in: RoundedRectangle(cornerRadius: MPRadius.cell)
          )
        }
      }
      .listStyle(.sidebar)
      Spacer(minLength: MPSpace.tight)
      PublishRail(store: store)
    }
    .background(MPColor.ground)
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
