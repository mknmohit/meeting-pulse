import Foundation

public enum OwnerError: Error, Equatable, Sendable {
  case unreachable(retryIn: Duration)
  case permissionDenied
  case noPairingCode
  case recoveryPhraseUnavailable
  case deleteInProgress
}
