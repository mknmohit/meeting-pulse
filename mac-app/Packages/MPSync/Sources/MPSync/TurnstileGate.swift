import Foundation
import WebKit

public enum TurnstileReason: Sendable {
  case firstRegistration
  case recoveryRebind
}

public enum TurnstileError: Error, Equatable, Sendable {
  case unavailable
  case emptyToken
}

@MainActor
public protocol TurnstileProvider: Sendable {
  func token(for reason: TurnstileReason) async throws -> String
}

public actor TurnstileGate {
  private let provider: any TurnstileProvider

  public init(provider: any TurnstileProvider) {
    self.provider = provider
  }

  public func token(for reason: TurnstileReason) async throws -> String {
    let token = try await provider.token(for: reason).trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !token.isEmpty else {
      throw TurnstileError.emptyToken
    }
    return token
  }
}

@MainActor
public struct UnavailableTurnstileProvider: TurnstileProvider {
  public init() {}

  public func token(for reason: TurnstileReason) async throws -> String {
    throw TurnstileError.unavailable
  }
}

@MainActor
public final class WKTurnstileProvider: NSObject, TurnstileProvider, WKScriptMessageHandler,
  @unchecked Sendable
{
  private let siteKey: String
  private let webView: WKWebView
  private var continuation: CheckedContinuation<String, Error>?

  public init(siteKey: String, htmlURL: URL) {
    self.siteKey = siteKey
    let configuration = WKWebViewConfiguration()
    let controller = WKUserContentController()
    configuration.userContentController = controller
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    controller.add(self, name: "meetingPulse")
    webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
  }

  public func token(for reason: TurnstileReason) async throws -> String {
    guard continuation == nil else {
      throw TurnstileError.unavailable
    }
    let encodedKey = try JSONSerialization.data(
      withJSONObject: siteKey,
      options: [.fragmentsAllowed]
    )
    guard let key = String(data: encodedKey, encoding: .utf8) else {
      throw TurnstileError.unavailable
    }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      webView.evaluateJavaScript(
        "window.meetingPulseTurnstile.render(\(key));"
      ) { [weak self] _, error in
        guard let error else {
          return
        }
        self?.resume(with: .failure(error))
      }
    }
  }

  @objc(userContentController:didReceiveScriptMessage:)
  public func userContentController(
    _: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? [String: Any] else {
      resume(with: .failure(TurnstileError.unavailable))
      return
    }
    if let token = body["token"] as? String {
      resume(with: .success(token))
    } else {
      resume(with: .failure(TurnstileError.unavailable))
    }
  }

  private func resume(with result: Result<String, Error>) {
    guard let continuation else {
      return
    }
    self.continuation = nil
    continuation.resume(with: result)
  }
}
