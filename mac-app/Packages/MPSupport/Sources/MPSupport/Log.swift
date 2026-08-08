import OSLog

public enum MPLog {
  public static let runtime = Logger(
    subsystem: "com.techdevix.meetingpulse",
    category: "runtime"
  )
  public static let sync = Logger(
    subsystem: "com.techdevix.meetingpulse",
    category: "sync"
  )
  public static let ui = Logger(
    subsystem: "com.techdevix.meetingpulse",
    category: "ui"
  )
}
