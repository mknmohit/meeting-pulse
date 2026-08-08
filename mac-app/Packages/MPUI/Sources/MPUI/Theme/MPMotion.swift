import SwiftUI

public enum MPMotion {
  public static let hoist = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
  public static let settle = Animation.spring(duration: 0.34, bounce: 0.22)
  public static let quick = Animation.easeOut(duration: 0.15)
  public static let chalk = Animation.easeInOut(duration: 0.18)
  public static let leaf = Animation.easeOut(duration: 0.18)
  public static let land = Animation.spring(duration: 0.28, bounce: 0.15)
}
