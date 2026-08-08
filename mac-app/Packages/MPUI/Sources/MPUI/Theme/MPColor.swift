import AppKit
import SwiftUI

public enum MPColor {
  public static let plateStorm = adaptive(dark: 0x8C2A22, light: 0x9A3128)
  public static let plateStormRim = adaptive(dark: 0x5C1C16, light: 0x66201A)
  public static let plateAmber = adaptive(dark: 0x7D4C13, light: 0x7D4C13)
  public static let plateAmberRim = adaptive(dark: 0x52320D, light: 0x52320D)
  public static let plateBare = adaptive(dark: 0x3A4247, light: 0x55585B)
  public static let plateBareRim = adaptive(dark: 0x262C2F, light: 0x383A3C)
  public static let paintWhite = Color(hex: 0xF2EFE8)
  public static let chalk = adaptive(dark: 0xC8CDCB, light: 0x3A403E)
  public static let brass = adaptive(dark: 0xE8B23A, light: 0x937025)
  public static let brassIncreaseContrast = Color(red: 0.62, green: 0.42, blue: 0.10)
  public static let nightBrass = Color(red: 0.92, green: 0.74, blue: 0.36)
  public static let nightBrassIncreaseContrast = Color(red: 0.96, green: 0.82, blue: 0.48)
  public static let ground = adaptive(dark: 0x0C1418, light: 0xE7E3DA)
  public static let groundRail = adaptive(dark: 0x070E11, light: 0xD6D1C6)

  private static func adaptive(dark: UInt32, light: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let value = isDark ? dark : light
        return NSColor(
          calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
          green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255,
          alpha: 1
        )
      }
    )
  }
}
