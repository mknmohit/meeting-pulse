import Foundation
import OSLog

public struct Redactor: Sendable {
  private var sensitiveValues: [String] = []

  public init() {}

  public mutating func registerSensitiveValue(_ value: String) {
    guard !value.isEmpty, !sensitiveValues.contains(value) else {
      return
    }
    sensitiveValues.append(value)
    sensitiveValues.sort { $0.count > $1.count }
  }

  public func redact(_ input: String) -> String {
    var result = input
    for value in sensitiveValues {
      result = result.replacingOccurrences(of: value, with: "<redacted>")
    }
    let patterns = [
      #"https?://\S+"#,
      #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
      #"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
      #"\b[A-Za-z0-9-]{20}\.supabase\.co\b"#,
      #"\b[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}\b"#,
      #"\b([0-9A-HJKMNP-TV-Z]{5}-){5}[0-9A-HJKMNP-TV-Z]\b"#,
      #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#,
    ]
    for pattern in patterns {
      result = result.replacingOccurrences(
        of: pattern,
        with: "<redacted>",
        options: .regularExpression
      )
    }
    return result
  }
}

public final class DiagnosticsLog: @unchecked Sendable {
  private let logger: Logger
  private let fileURL: URL
  private let lock = NSLock()
  private var redactor: Redactor

  public init(
    subsystem: String = "com.techdevix.meetingpulse",
    category: String = "diagnostics",
    fileURL: URL = FileManager.default
      .urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/MeetingPulse/meetingpulse.log"),
    redactor: Redactor = Redactor()
  ) {
    logger = Logger(subsystem: subsystem, category: category)
    self.fileURL = fileURL
    self.redactor = redactor
  }

  public func registerSensitiveValue(_ value: String) {
    lock.lock()
    redactor.registerSensitiveValue(value)
    lock.unlock()
  }

  public func write(_ message: String) {
    lock.lock()
    let sanitized = redactor.redact(message)
    lock.unlock()
    logger.info("\(sanitized, privacy: .public)")

    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try rotateIfNeeded()
      cleanupExpiredLogs()
      try Data((sanitized + "\n").utf8).append(to: fileURL)
    } catch {
      logger.error("DIAGNOSTICS_FILE_WRITE_FAILED")
    }
  }

  private func rotateIfNeeded() throws {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let size = attributes[.size] as? NSNumber,
      size.intValue >= 5 * 1024 * 1024
    else {
      return
    }

    let fileManager = FileManager.default
    for index in stride(from: 2, through: 1, by: -1) {
      let source = fileURL.appendingPathExtension("\(index)")
      let destination = fileURL.appendingPathExtension("\(index + 1)")
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      if fileManager.fileExists(atPath: source.path) {
        try fileManager.moveItem(at: source, to: destination)
      }
    }
    let first = fileURL.appendingPathExtension("1")
    if fileManager.fileExists(atPath: first.path) {
      try fileManager.removeItem(at: first)
    }
    try fileManager.moveItem(at: fileURL, to: first)
  }

  private func cleanupExpiredLogs() {
    let fileManager = FileManager.default
    guard
      let directory = fileURL.deletingLastPathComponent() as URL?,
      let files = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
    else {
      return
    }
    let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    for file in files where file.lastPathComponent.hasPrefix("meetingpulse.log") {
      guard
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
        let modified = values.contentModificationDate,
        modified < cutoff
      else {
        continue
      }
      do {
        try fileManager.removeItem(at: file)
      } catch {
        logger.error("DIAGNOSTICS_RETENTION_DELETE_FAILED")
      }
    }
  }
}

extension Data {
  fileprivate func append(to url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: self)
      try handle.close()
    } else {
      try write(to: url, options: .atomic)
    }
  }
}
