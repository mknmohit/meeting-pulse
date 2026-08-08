import MPCore
import MPSupport

public enum MPStringBindings {
  public static func stationSection(_ section: StationSection) -> String {
    switch section {
    case .watch:
      return MPString.station.watch
    case .sharing:
      return MPString.station.sharing
    case .thisMac:
      return MPString.station.thisMac
    case .privacy:
      return MPString.station.privacy
    }
  }

  public static func durationLabel(_ duration: ManualOverride.Duration) -> String {
    MPString.mast.durationLabel(duration)
  }
}
