import SwiftUI

public struct MenuBarIcon: View {
  private let face: PlateFace
  private let label: String
  private let isDimmed: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(face: PlateFace, label: String, isDimmed: Bool = false) {
    self.face = face
    self.label = label
    self.isDimmed = isDimmed
  }

  public var body: some View {
    DayShapeView(
      shape: DayShape(rawValue: face.dayShapeName) ?? .mast,
      tint: .primary
    )
    .frame(width: 18, height: 18)
    .opacity(isDimmed ? 0.4 : 1)
    .animation(reduceMotion ? nil : MPMotion.hoist, value: face)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityIdentifier("meetingpulse.menu-bar-status")
  }
}
