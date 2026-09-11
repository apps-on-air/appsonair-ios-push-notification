struct EnvironmentConfig{
// MARK: - Production Config:
   static let serverBaseURL = "https://push.appsonair.com/"
    
// MARK: - API Endpoints:
    static let registerDevice = serverBaseURL + "v1/subscriptions"

    /// PATCH target for a single subscription. Append the `subscriptionId`:
    ///   subscriptionById + "<subscriptionId>"  →  …/v1/subscriptions/<id>
    static let subscriptionById = serverBaseURL + "v1/subscriptions/"
}