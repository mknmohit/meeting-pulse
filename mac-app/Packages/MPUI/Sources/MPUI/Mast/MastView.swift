import SwiftUI

public struct MastView: View {
  private let store: PulseStore
  private let actions: any PulseActions
  @Environment(\.mpIncreaseContrast) private var increaseContrast
  // Capture the schedule anchor once at first appearance so the
  // TimelineView's `now`-driven schedule is stable across re-renders. The
  // timeline still ticks every 30 s internally, but the schedule itself
  // is not recreated on every `body` evaluation.
  @SwiftUI.State private var scheduleAnchor: Date = .now

  public init(store: PulseStore, actions: any PulseActions) {
    self.store = store
    self.actions = actions
  }

  public var body: some View {
    VStack(spacing: MPSpace.snug) {
      MPPlate(
        face: store.plateFace,
        ownerName: store.displayName.isEmpty ? nil : store.displayName,
        headline: store.plateHeadline,
        supporting: store.plateSupporting
      )

      TimelineView(.periodic(from: scheduleAnchor, by: 30)) { context in
        Text(store.reasonLine(at: context.date))
          .font(MPFont.chalkLine)
          .foregroundStyle(reasonColor)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(maxWidth: MPShape.plateWidth)
      }

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
