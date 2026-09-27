import Foundation
import AppsOnAir_AppPush
import Combine

struct LiveEvent: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

@MainActor
final class SDKState: ObservableObject {

    static let shared = SDKState()

    @Published var deviceId: String = ""
    @Published var subscriptionId: String = ""
    @Published var apnsToken: String = ""
    @Published var apnsEnvironment: String = ""
    @Published var externalId: String = ""

    @Published var permissionGranted: String = ""
    @Published var permissionNative: String = ""
    @Published var canRequestPermission: String = ""

    @Published var optedIn: String = ""
    @Published var subscriptionToken: String = ""

    @Published var badgeCount: String = ""

    @Published var logLevel: String = ""

    @Published var bgSyncStatus: String = ""
    @Published var bgTaskIdentifier: String = ""

    @Published var liveTokenEvent: String = ""
    @Published var liveReceivedEvent: String = ""
    @Published var liveOpenedEvent: String = ""
    @Published var liveErrorEvent: String = ""
    @Published var liveSilentPushEvent: String = ""

    @Published var tagsResult: String = ""
    @Published var languageResult: String = ""

    private init() {}
}
