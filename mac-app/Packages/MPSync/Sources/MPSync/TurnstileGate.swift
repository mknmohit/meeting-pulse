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
  func shutdown()
}

public extension TurnstileProvider {
  func shutdown() {}
}

@MainActor
public final class LazyTurnstileProvider: TurnstileProvider, @unchecked Sendable {
  private let siteKey: String
  private let htmlURL: URL
  private let baseURL: URL?
  private let onCreated: (@MainActor @Sendable (WKWebView) -> Void)?
  private var provider: WKTurnstileProvider?

  public init(
    siteKey: String,
    htmlURL: URL,
    baseURL: URL? = nil,
    onCreated: (@MainActor @Sendable (WKWebView) -> Void)? = nil
  ) {
    self.siteKey = siteKey
    self.htmlURL = htmlURL
    self.baseURL = baseURL
    self.onCreated = onCreated
  }

  public func token(for reason: TurnstileReason) async throws -> String {
    let provider = makeProvider()
    return try await provider.token(for: reason)
  }

  public func shutdown() {
    provider?.shutdown()
    provider = nil
  }

  private func makeProvider() -> WKTurnstileProvider {
    if let provider {
      return provider
    }
    let provider = WKTurnstileProvider(
      siteKey: siteKey,
      htmlURL: htmlURL,
      baseURL: baseURL
    )
    self.provider = provider
    onCreated?(provider.view)
    return provider
  }
}

public actor TurnstileGate {
  private let provider: any TurnstileProvider
  private let onTokenStarted: (@MainActor @Sendable () -> Void)?
  private let onTokenFinished: (@MainActor @Sendable () -> Void)?

  public init(
    provider: any TurnstileProvider,
    onTokenStarted: (@MainActor @Sendable () -> Void)? = nil,
    onTokenFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.provider = provider
    self.onTokenStarted = onTokenStarted
    self.onTokenFinished = onTokenFinished
  }

  public func token(for reason: TurnstileReason) async throws -> String {
    let rawToken: String
    do {
      await onTokenStarted?()
      rawToken = try await provider.token(for: reason)
    } catch {
      await finishTokenWork()
      throw error
    }
    await finishTokenWork()
    let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw TurnstileError.emptyToken
    }
    return token
  }

  public func shutdown() async {
    await provider.shutdown()
  }

  private func finishTokenWork() async {
    await provider.shutdown()
    await onTokenFinished?()
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
  WKNavigationDelegate,
  @unchecked Sendable
{
  private static let messageName = "meetingPulse"
  private let siteKey: String
  private var webView: WKWebView?
  private var continuation: CheckedContinuation<String, Error>?
  private var pageLoaded = false
  private var loadWaiters = [CheckedContinuation<Void, Error>]()
  private var isShutdown = false

  public var view: WKWebView {
    guard let webView else {
      // The provider has been shut down. Returning a placeholder WKWebView
      // instead of crashing lets SwiftUI re-render gracefully (the
      // Turnstile view is hidden behind a sheet/scrim once we have a
      // token, and the recovery flow recreates the provider on demand).
      assertionFailure("The Turnstile provider has been shut down.")
      let placeholder = WKWebView(frame: .zero)
      return placeholder
    }
    return webView
  }

  public init(siteKey: String, htmlURL: URL, baseURL: URL? = nil) {
    self.siteKey = siteKey
    let configuration = WKWebViewConfiguration()
    let controller = WKUserContentController()
    configuration.userContentController = controller
    let webView = WKWebView(frame: .zero, configuration: configuration)
    self.webView = webView
    super.init()
    controller.add(WeakScriptMessageHandler(owner: self), name: Self.messageName)
    webView.navigationDelegate = self
    if let html = try? String(contentsOf: htmlURL, encoding: .utf8) {
      webView.loadHTMLString(html, baseURL: baseURL)
    } else {
      webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
  }

  public func token(for reason: TurnstileReason) async throws -> String {
    guard !isShutdown, continuation == nil else {
      throw TurnstileError.unavailable
    }
    try await waitForPage()
    guard !isShutdown, let webView else {
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

  public func shutdown() {
    guard !isShutdown else {
      return
    }
    isShutdown = true
    resume(with: .failure(TurnstileError.unavailable))

    let waiters = loadWaiters
    loadWaiters.removeAll()
    for waiter in waiters {
      waiter.resume(throwing: TurnstileError.unavailable)
    }

    guard let webView else {
      return
    }
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: Self.messageName
    )
    self.webView = nil
  }

  public func webView(
    _: WKWebView,
    didFinish navigation: WKNavigation!
  ) {
    guard !isShutdown else {
      return
    }
    pageLoaded = true
    let waiters = loadWaiters
    loadWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  public func webView(
    _: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    guard !isShutdown else {
      return
    }
    NSLog("Meeting Pulse Turnstile page failed: %@", error.localizedDescription)
    let waiters = loadWaiters
    loadWaiters.removeAll()
    for waiter in waiters {
      waiter.resume(throwing: error)
    }
  }

  public func webView(
    _: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    guard !isShutdown else {
      return
    }
    NSLog("Meeting Pulse Turnstile navigation failed: %@", error.localizedDescription)
    let waiters = loadWaiters
    loadWaiters.removeAll()
    for waiter in waiters {
      waiter.resume(throwing: error)
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

  private func waitForPage() async throws {
    guard !isShutdown else {
      throw TurnstileError.unavailable
    }
    if pageLoaded {
      return
    }
    try await withCheckedThrowingContinuation { continuation in
      loadWaiters.append(continuation)
    }
  }
}

@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  weak var owner: WKTurnstileProvider?

  init(owner: WKTurnstileProvider) {
    self.owner = owner
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    owner?.userContentController(
      userContentController,
      didReceive: message
    )
  }
}
