import Foundation

// MARK: - AppPushService.Debug namespace

extension AppPushService {

    /// Debug logging configuration.
    /// Call AppPushService.Debug.logLevel = .verbose before initialize() for full logs.
    public enum Debug {

        /// Current logging verbosity. Default is .none (no logs in production).
        /// Set to .verbose during development for full SDK output.
        /// nonisolated(unsafe): logLevel is a simple write-once-on-startup setting.
        /// It is always set before the SDK begins async work, so no data race occurs in practice.
        public nonisolated(unsafe) static var logLevel: LogLevel = .none

        /// Set the logging verbosity level.
        /// - Parameter level: .none, .fatal, .error, .warn, .info, .debug, or .verbose
        public static func setLogLevel(_ level: LogLevel) {
            logLevel = level
        }
    }
}
