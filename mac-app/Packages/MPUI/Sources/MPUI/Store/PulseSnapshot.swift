import Foundation
import MPCore

public enum PulseMode: Hashable, Sendable {
  case busy
  case automatic
  case available
}

public enum PublishState: Equatable, Sendable {
  case never
  case publishing
  case published(at: Date)
  case retrying
  case offline
  case superseded
}

public enum SyncState: Equatable, Sendable {
  case idle
  case retrying
  case superseded
}

public enum ReasonTone: Equatable, Sendable {
  case info
  case caution
  case alert
}

public enum Loadable<Value: Sendable>: Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(String)

  public var isLoading: Bool {
    if case .loading = self {
      return true
    }
    return false
  }
}

public struct ViewerSummary: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let pairedAt: Date

  public init(id: UUID, pairedAt: Date) {
    self.id = id
    self.pairedAt = pairedAt
  }
}

public enum PulseError: Equatable, Sendable {
  case network
  case localStorage
  case permissionDenied
  case invalidPhrase
  case loginItemBlocked
  case supersededByAnother
  case createLink
  case viewers
  case setup(String)
}

public enum Freshness: Equatable, Sendable {
  case fresh(secondsAgo: Int)
  case stale(Date)

  public var isStale: Bool {
    if case .stale = self {
      return true
    }
    return false
  }
}

public struct SyncSnapshot: Equatable, Sendable {
  public let state: State
  public let callOkay: Bool?
  public let freshness: Freshness
  public let capturedAt: Date

  public init(
    state: State,
    callOkay: Bool?,
    freshness: Freshness,
    capturedAt: Date
  ) {
    self.state = state
    self.callOkay = callOkay
    self.freshness = freshness
    self.capturedAt = capturedAt
  }

  public static let empty = SyncSnapshot(
    state: .available,
    callOkay: nil,
    freshness: .stale(.now),
    capturedAt: .now
  )
}

public enum Reachability: Equatable, Sendable {
  case unknown
  case ok
  case unreachable(since: Date)
}

public enum LoadingState: Equatable, Sendable {
  case idle
  case loading
  case loaded(at: Date)
  case failed(PulseError)
}

public enum PlateFace: String, Equatable, Sendable {
  case meeting
  case callOkay
  case generic

  public init(state: State, callsOkay: Bool, isFresh: Bool) {
    guard isFresh, state == .busy else {
      self = .generic
      return
    }
    self = callsOkay ? .callOkay : .meeting
  }

  public var dayShapeName: String {
    switch self {
    case .meeting:
      return "cone"
    case .callOkay:
      return "pennant"
    case .generic:
      return "mast"
    }
  }
}
