import SwiftUI

public enum StationSection: String, CaseIterable, Identifiable, Hashable, Sendable {
  case watch
  case sharing
  case thisMac
  case privacy

  public var id: String {
    rawValue
  }

  public var title: String {
    MPStringBindings.stationSection(self)
  }

  public var symbol: String {
    switch self {
    case .watch:
      return "eye"
    case .sharing:
      return "link"
    case .thisMac:
      return "desktopcomputer"
    case .privacy:
      return "hand.raised"
    }
  }
}
