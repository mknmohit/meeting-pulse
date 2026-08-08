import Foundation
import MPSupport

public enum MPRelativeTime {
  public static func text(since date: Date?, now: Date = .now) -> String {
    guard let date else {
      return MPString.station.notSeenYet
    }
    return MPString.Relative.elapsed(max(Int(now.timeIntervalSince(date)), 0))
  }
}
