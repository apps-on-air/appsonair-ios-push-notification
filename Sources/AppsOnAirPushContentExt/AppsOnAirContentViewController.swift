import UIKit
import UserNotifications
import UserNotificationsUI

// MARK: - AppsOnAirContentViewController

/// Base view controller for the host app's **Notification Content Extension** target.
///
/// ## Setup
/// 1. In Xcode add a new **Notification Content Extension** target to your app.
/// 2. Link `AppsOnAirPushContentExt` (SPM) or pod `AppPushService/ContentExtension` to
///    **only** that extension target.
/// 3. In the extension's Info.plist, set:
///    ```
///    NSExtension → NSExtensionPrincipalClass → AppsOnAirContentViewController
///    ```
///    (or use your subclass name — see below).
/// 4. Add the notification category identifier(s) in the Info.plist under
///    `UNNotificationExtensionCategory`.
///
/// ## What this class renders
/// - Full-width image (from the first `UNNotificationAttachment`, e.g. added by
///   `AppsOnAirNotificationServiceExtension`). Hidden when no attachment is present.
/// - Bold title label.
/// - Multiline body label.
///
/// ## Subclassing
/// ```swift
/// class MyContentVC: AppsOnAirContentViewController {
///     override func configure(with notification: UNNotification) {
///         super.configure(with: notification)
///         // Apply additional customisation here.
///     }
/// }
/// ```
/// Set `MyContentVC` as the principal class in the extension's Info.plist.
open class AppsOnAirContentViewController: UIViewController, UNNotificationContentExtension {

    // MARK: - Views

    private let scrollView   = UIScrollView()
    private let contentStack = UIStackView()
    private let imageView    = UIImageView()
    private let titleLabel   = UILabel()
    private let bodyLabel    = UILabel()

    // MARK: - UIViewController

    open override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    // MARK: - UNNotificationContentExtension

    public func didReceive(_ notification: UNNotification) {
        configure(with: notification)
    }

    // MARK: - Subclass hook

    /// Apply content from the notification to the UI. Override to add custom behaviour.
    /// Call `super` to keep the built-in title, body, and attachment image display.
    open func configure(with notification: UNNotification) {
        let content = notification.request.content
        titleLabel.text = content.title
        bodyLabel.text  = content.body

        // Load image from the first attachment (added by the Notification Service Extension).
        if let attachment = content.attachments.first,
           attachment.url.startAccessingSecurityScopedResource() {
            defer { attachment.url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: attachment.url),
               let image = UIImage(data: data) {
                imageView.image    = image
                imageView.isHidden = false
                updatePreferredContentSize(hasImage: true)
                return
            }
        }
        imageView.isHidden = true
        updatePreferredContentSize(hasImage: false)
    }

    // MARK: - Layout

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        // Image view — hidden until an attachment is loaded
        imageView.contentMode  = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden     = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font          = .boldSystemFont(ofSize: 16)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Body
        bodyLabel.font          = .systemFont(ofSize: 14)
        bodyLabel.textColor     = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Stack (title + body)
        contentStack.axis      = .vertical
        contentStack.spacing   = 6
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(bodyLabel)

        // Scroll view wraps everything so long bodies scroll correctly
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.addSubview(imageView)
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            // Scroll view fills the view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Image — pinned to top, full width, fixed height
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 200),

            // Text stack — below image, full width
            contentStack.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
    }

    private func updatePreferredContentSize(hasImage: Bool) {
        let imageHeight: CGFloat = hasImage ? 200 : 0
        // Title (≤ 2 lines) + body + spacing + margins
        let textHeight: CGFloat  = 80
        let total = imageHeight + textHeight + 12 + 16  // top gap + bottom margin
        preferredContentSize = CGSize(width: view.bounds.width, height: total)
    }
}
