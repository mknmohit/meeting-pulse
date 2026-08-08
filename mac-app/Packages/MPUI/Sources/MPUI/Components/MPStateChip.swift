import SwiftUI
import MPCore
import MPSupport

public struct MPStateChip: View {
  private let observation: SourceObservation?

  public init(observation: SourceObservation?) {
    self.observation = observation
  }

  public var body: some View {
    HStack(spacing: MPSpace.hair) {
      Circle()
        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
        .frame(width: 7, height: 7)
      Text(value)
        .font(MPFont.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var isActive: Bool {
    observation == .active
  }

  private var value: String {
    switch observation {
    case .active:
      return MPString.station.inCall
    case .inactive:
      return MPString.station.noCall
    case .unknown:
      return MPString.station.cannotTell
    case .sourceAbsent:
      return MPString.station.cannotTell
    case .none:
      return MPString.station.notSeenYet
    }
  }
}
