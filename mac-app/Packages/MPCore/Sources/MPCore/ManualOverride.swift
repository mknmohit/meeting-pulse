import Foundation

public struct ManualOverride: Codable, Equatable, Sendable {
  public enum ValidationError: Error, Equatable, Sendable {
    case unavailableState
  }

  public enum Duration: CaseIterable, Equatable, Sendable {
    case m15
    case m30
    case m45
    case h1
    case h2
    case h4
    case untilCleared

    public static let `default`: Duration = .m30

    public var seconds: TimeInterval? {
      switch self {
      case .m15:
        900
      case .m30:
        1_800
      case .m45:
        2_700
      case .h1:
        3_600
      case .h2:
        7_200
      case .h4:
        14_400
      case .untilCleared:
        nil
      }
    }
  }

  public let state: State
  public let createdAtWall: Date
  public let expiresAtWall: Date?
  public let deadline: ContinuousClock.Instant?

  public init(
    state: State,
    createdAtWall: Date,
    expiresAtWall: Date?,
    deadline: ContinuousClock.Instant?
  ) throws {
    guard state == .busy || state == .available else {
      throw ValidationError.unavailableState
    }
    self.state = state
    self.createdAtWall = createdAtWall
    self.expiresAtWall = expiresAtWall
    self.deadline = deadline
  }

  public func isActive(at now: ContinuousClock.Instant) -> Bool {
    guard expiresAtWall != nil else {
      return true
    }
    guard let deadline else {
      return false
    }
    return now < deadline
  }

  enum CodingKeys: String, CodingKey {
    case state
    case createdAtWall
    case expiresAtWall
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let state = try container.decode(State.self, forKey: .state)
    try self.init(
      state: state,
      createdAtWall: container.decode(Date.self, forKey: .createdAtWall),
      expiresAtWall: container.decodeIfPresent(Date.self, forKey: .expiresAtWall),
      deadline: nil
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(state, forKey: .state)
    try container.encode(createdAtWall, forKey: .createdAtWall)
    try container.encodeIfPresent(expiresAtWall, forKey: .expiresAtWall)
  }
}

extension ManualOverride.Duration: Identifiable, Hashable {
  public var id: Self {
    self
  }
}
