import Foundation

// MARK: - AppPushService.Debug namespace

extension AppPushService {

    /// Debug logging configuration.
    /// Call AppPushService.Debug.logLevel = .verbose before initialize() for full logs.
    public enum Debug {

        /// Current logging verbosity. Default is .warn, so errors and warnings always reach the
        /// console: a failure before JS (or any listener) starts would otherwise be invisible.
        /// Set to .verbose during development for full SDK output, or .none to silence it.
        /// The Info.plist key `AppsOnAirLogLevel` (none|fatal|error|warn|info|debug|verbose)
        /// sets it without code, read when initialize() runs.
        /// nonisolated(unsafe): logLevel is a simple write-once-on-startup setting.
        /// It is always set before the SDK begins async work, so no data race occurs in practice.
        public nonisolated(unsafe) static var logLevel: LogLevel = .warn

        /// Set the logging verbosity level.
        /// - Parameter level: .none, .fatal, .error, .warn, .info, .debug, or .verbose
        public static func setLogLevel(_ level: LogLevel) {
            logLevel = level
        }
    }
}
