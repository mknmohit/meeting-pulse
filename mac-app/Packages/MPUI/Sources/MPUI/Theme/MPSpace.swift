import CoreGraphics

public enum MPSpace {
  public static let hair: CGFloat = 4
  public static let tight: CGFloat = 8
  public static let snug: CGFloat = 12
  public static let base: CGFloat = 16
  public static let wide: CGFloat = 20
  public static let loose: CGFloat = 24
  public static let open: CGFloat = 32
  public static let vast: CGFloat = 40
  /// Comfortable gap used between sibling groups inside a section. Distinct
  /// from `loose` so authors compose a deliberate tight/airy cadence rather
  /// than repeating one value.
  public static let airy: CGFloat = 28
  /// Outer padding used for section stacks so groups read with breathing room
  /// against the well.
  public static let breath: CGFloat = 36
}
