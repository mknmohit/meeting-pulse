import SwiftUI

public enum MPFont {
  public static let plateHeadline = Font.system(size: 30, weight: .semibold)
  public static let plateHeadlineNamed = Font.system(size: 22, weight: .semibold)
  public static let plateName = Font.system(size: 13, weight: .medium)
  public static let plateSupporting = Font.system(size: 13, weight: .regular)
  public static let sectionTitle = Font.system(size: 20, weight: .semibold)
  public static let groupHeader = Font.system(size: 13, weight: .semibold)
  public static let rowLabel = Font.system(size: 13, weight: .regular)
  public static let rowValue = Font.system(size: 13, weight: .regular)
  public static let caption = Font.system(size: 11, weight: .regular)
  public static let chalkLine = Font.system(size: 11, weight: .regular)
  public static let code = Font.system(size: 22, weight: .semibold, design: .monospaced)
  public static let phrase = Font.system(size: 15, weight: .regular, design: .monospaced)
}
