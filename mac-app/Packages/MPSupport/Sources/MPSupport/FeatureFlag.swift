import Foundation

public enum FeatureFlag {
  public static let macNativeKey = "ui.macNative"

  public static var macNative: Bool {
    guard UserDefaults.standard.object(forKey: macNativeKey) != nil else {
      return true
    }
    return UserDefaults.standard.bool(forKey: macNativeKey)
  }
}
