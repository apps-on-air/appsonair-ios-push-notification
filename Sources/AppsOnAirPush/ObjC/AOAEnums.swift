import Foundation

// MARK: - AOAAPNsEnvironment

/// ObjC-compatible wrapper for APNsEnvironment.
@objc(AOAAPNsEnvironment)
public enum AOAAPNsEnvironment: Int {
    case sandbox = 0
    case production = 1
}

extension APNsEnvironment {
    var aoaValue: AOAAPNsEnvironment {
        switch self {
        case .sandbox:    return .sandbox
        case .production: return .production
        }
    }
    init(_ aoa: AOAAPNsEnvironment) {
        switch aoa {
        case .sandbox:    self = .sandbox
        case .production: self = .production
        @unknown default: self = .production
        }
    }
}

// MARK: - AOANotificationPermission

/// ObjC-compatible wrapper for NotificationPermission.
@objc(AOANotificationPermission)
public enum AOANotificationPermission: Int {
    case notDetermined = 0
    case denied        = 1
    case authorized    = 2
    case provisional   = 3
    case ephemeral     = 4
}

extension NotificationPermission {
    var aoaValue: AOANotificationPermission {
        switch self {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .provisional:   return .provisional
        case .ephemeral:     return .ephemeral
        }
    }
}

// MARK: - AOALogLevel

/// ObjC-compatible wrapper for LogLevel.
@objc(AOALogLevel)
public enum AOALogLevel: Int {
    case none    = 0
    case fatal   = 1
    case error   = 2
    case warn    = 3
    case info    = 4
    case debug   = 5
    case verbose = 6
}

extension LogLevel {
    var aoaValue: AOALogLevel {
        switch self {
        case .none:    return .none
        case .fatal:   return .fatal
        case .error:   return .error
        case .warn:    return .warn
        case .info:    return .info
        case .debug:   return .debug
        case .verbose: return .verbose
        }
    }
    init(_ aoa: AOALogLevel) {
        switch aoa {
        case .none:    self = .none
        case .fatal:   self = .fatal
        case .error:   self = .error
        case .warn:    self = .warn
        case .info:    self = .info
        case .debug:   self = .debug
        case .verbose: self = .verbose
        @unknown default: self = .none
        }
    }
}

// MARK: - AOAPushErrorCode

/// ObjC-compatible wrapper for PushError.Code.
@objc(AOAPushErrorCode)
public enum AOAPushErrorCode: Int {
    case notInitialized        = 0
    case permissionDenied      = 1
    case apnsRegistrationFailed = 2
    case unknown               = 3
}

extension PushError {
    /// Convert to NSError for ObjC consumption.
    var nsError: NSError {
        let code: AOAPushErrorCode
        switch self.code {
        case .notInitialized:        code = .notInitialized
        case .permissionDenied:      code = .permissionDenied
        case .apnsRegistrationFailed: code = .apnsRegistrationFailed
        case .unknown:               code = .unknown
        }
        return NSError(
            domain: "AOAPushErrorDomain",
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
