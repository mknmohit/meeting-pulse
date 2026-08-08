import SwiftUI

public struct MPPlate: View {
  private let face: PlateFace
  private let ownerName: String?
  private let headline: String
  private let supporting: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    face: PlateFace,
    ownerName: String?,
    headline: String,
    supporting: String
  ) {
    self.face = face
    self.ownerName = ownerName
    self.headline = headline
    self.supporting = supporting
  }

  public var body: some View {
    VStack(spacing: 0) {
      DayShapeView(shape: DayShape(rawValue: face.dayShapeName) ?? .mast, tint: MPColor.paintWhite)
        .frame(width: MPShape.dayShapeWidth, height: MPShape.dayShapeHeight)
        .padding(.top, MPSpace.loose)

      Spacer(minLength: MPSpace.wide)

      Text(headline)
        .font(ownerName == nil && face != .callOkay ? MPFont.plateHeadline : MPFont.plateHeadlineNamed)
        .tracking(ownerName == nil && face != .callOkay ? -0.9 : -0.66)
        .foregroundStyle(MPColor.paintWhite)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)

      Text(supporting)
        .font(MPFont.plateSupporting)
        .foregroundStyle(MPColor.paintWhite.opacity(0.78))
        .multilineTextAlignment(.center)
        .padding(.top, MPSpace.tight)
        .padding(.bottom, MPSpace.loose)
    }
    .frame(width: MPShape.plateWidth, alignment: .top)
    .background(
      RoundedRectangle(cornerRadius: MPRadius.plate, style: .continuous)
        .fill(plateColor)
        .overlay(
          RoundedRectangle(cornerRadius: MPRadius.plate, style: .continuous)
            .strokeBorder(rimColor, lineWidth: 2)
        )
    )
    .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    .animation(reduceMotion ? nil : MPMotion.hoist, value: face)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(headline)
    .accessibilityValue(supporting)
  }

  private var plateColor: Color {
    switch face {
    case .meeting:
      return MPColor.plateStorm
    case .callOkay:
      return MPColor.plateAmber
    case .generic:
      return MPColor.plateBare
    }
  }

  private var rimColor: Color {
    switch face {
    case .meeting:
      return MPColor.plateStormRim
    case .callOkay:
      return MPColor.plateAmberRim
    case .generic:
      return MPColor.plateBareRim
    }
  }
}
