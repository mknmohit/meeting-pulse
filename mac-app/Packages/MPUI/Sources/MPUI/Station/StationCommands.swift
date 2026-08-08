import SwiftUI
import MPSupport

public struct StationCommands: Commands {
  private let actions: any PulseActions

  public init(actions: any PulseActions) {
    self.actions = actions
  }

  public var body: some Commands {
    CommandMenu(MPString.station.windowTitle) {
      Button(MPString.station.watch) {
        actions.openStation(section: .watch)
      }
      .keyboardShortcut("1", modifiers: .command)
      Button(MPString.station.sharing) {
        actions.openStation(section: .sharing)
      }
      .keyboardShortcut("2", modifiers: .command)
      Button(MPString.station.thisMac) {
        actions.openStation(section: .thisMac)
      }
      .keyboardShortcut("3", modifiers: .command)
      Button(MPString.station.privacy) {
        actions.openStation(section: .privacy)
      }
      .keyboardShortcut("4", modifiers: .command)
    }
  }
}
