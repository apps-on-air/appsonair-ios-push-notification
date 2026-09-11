import Foundation

// MARK: - AOAPushDebug

/// ObjC-compatible facade for AppsOnAirPush.Debug.
@objc(AOAPushDebug)
public final class AOAPushDebug: NSObject {

    private override init() {}

    /// Current logging verbosity level.
    /// Set to AOALogLevelVerbose before `initialize` for full SDK logs.
    @objc
    public static var logLevel: AOALogLevel {
        get { AppsOnAirPush.Debug.logLevel.aoaValue }
        set { AppsOnAirPush.Debug.logLevel = LogLevel(newValue) }
    }

}
