import SwiftUI

public struct MastView: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @Environment(\.mpIncreaseContrast) private var increaseContrast

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(spacing: MPSpace.base) {
      MPPlate(
        face: store.plateFace,
        ownerName: store.displayName.isEmpty ? nil : store.displayName,
        headline: store.plateHeadline,
        supporting: store.plateSupporting
      )

      TimelineView(.periodic(from: .now, by: 30)) { context in
        Text(store.reasonLine(at: context.date))
          .font(MPFont.chalkLine)
          .foregroundStyle(reasonColor)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(maxWidth: MPShape.plateWidth)
      }

      ModeControl(store: store, actions: actions)
      CallsOkaySwitch(store: store, actions: actions)
    }
    .padding(.horizontal, MPSpace.base)
    .padding(.top, MPSpace.wide)
  }

  private var reasonColor: Color {
    switch store.reasonTone {
    case .info:
      return MPColor.chalk
    case .caution, .alert:
      return increaseContrast ? MPColor.brassIncreaseContrast : MPColor.brass
    }
  }
}
