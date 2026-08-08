import SwiftUI
import MPSupport

public struct PublishRail: View {
  private let store: PulseStore
  @Environment(\.mpIncreaseContrast) private var increaseContrast

  public init(store: PulseStore) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: MPSpace.hair) {
      GeometryReader { geometry in
        RoundedRectangle(cornerRadius: 2)
          .fill(railColor)
          .frame(width: railWidth(total: geometry.size.width), height: 3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 3)

      Text(railLabel)
        .font(MPFont.chalkLine)
        .foregroundStyle(store.syncState == .idle ? MPColor.chalk : MPColor.brass)
        .lineLimit(1)
    }
    .padding(.horizontal, MPSpace.base)
    .padding(.vertical, MPSpace.tight)
    .background(MPColor.groundRail)
  }

  private var railColor: Color {
    store.syncState == .idle
      ? MPColor.chalk
      : (increaseContrast ? MPColor.brassIncreaseContrast : MPColor.brass)
  }

  private var railLabel: String {
    if !store.isOnline {
      return MPString.mast.noNetwork
    }
    switch store.publishState {
    case .never:
      return MPString.mast.nothingPublished
    case .publishing:
      return MPString.mast.publishing
    case .retrying:
      return MPString.mast.reasonUnreachable
    case .offline:
      return MPString.mast.noNetwork
    case .superseded:
      return MPString.mast.anotherMacPublishing
    case .published(let date):
      let seconds = max(Int(Date.now.timeIntervalSince(date)), 0)
      return MPString.Relative.published(seconds)
    }
  }

  private func railWidth(total: CGFloat) -> CGFloat {
    switch store.publishState {
    case .never:
      return total * 0.5
    case .published:
      return total
    case .publishing:
      return total * 0.7
    case .retrying, .offline, .superseded:
      return total * 0.15
    }
  }
}
