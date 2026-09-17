struct EnvironmentConfig{
// MARK: - Production Config:
   static let serverBaseURL = "https://push.appsonair.com/"
    
// MARK: - API Endpoints:
    static let registerDevice = serverBaseURL + "v1/subscriptions"

    /// PATCH target for a single subscription. Append the `subscriptionId`:
    ///   subscriptionById + "<subscriptionId>"  →  …/v1/subscriptions/<id>
    static let subscriptionById = serverBaseURL + "v1/subscriptions/"

    /// POST target for the delivery-receipt event — sent once a push has been
    /// confirmed delivered to the device (NSE), powers "Delivered" analytics.
    static let eventDelivered = serverBaseURL + "v1/events/delivered"

    /// POST target for the open event — sent once the user taps a notification's body.
    static let eventOpened = serverBaseURL + "v1/events/opened"

    /// POST target for the click event — sent once the user taps a notification's action button.
    static let eventClicked = serverBaseURL + "v1/events/clicked"

    /// POST target for starting a session when the device is already registered
    /// (the register response itself starts the first session of a launch).
    static let startSession = serverBaseURL + "v1/sessions"

    /// PATCH target for ending a session. Append the `sessionId`:
    ///   sessionById + "<sessionId>"  →  …/v1/sessions/<id>
    static let sessionById = serverBaseURL + "v1/sessions/"
}