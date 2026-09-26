import UIKit
import UserNotifications
import UserNotificationsUI

// MARK: - AOAContentViewController

/// ObjC-subclassable Notification Content Extension base view controller.
///
/// Swift developers should use ``AppsOnAirContentViewController`` instead, which provides
/// the same built-in layout and an `open` `configure(with:)` override hook.
///
/// `AppsOnAirContentViewController` is a Swift `open class` — Objective-C cannot
/// subclass it due to `objc_subclassing_restricted`. `AOAContentViewController` is
/// an `@objc`-exposed `UIViewController` subclass that ObjC CE implementations can
/// subclass directly.
///
/// ## What this class renders
/// - Full-width image from the first `UNNotificationAttachment` (added by the NSE). Hidden when absent.
/// - Bold title label.
/// - Multiline body label.
///
/// ## Objective-C setup
/// 1. Set `NSExtensionPrincipalClass` to `AOAContentViewController` (direct use) or
///    your subclass name (no module prefix for ObjC) in the CE Info.plist.
/// 2. Remove `NSExtensionMainStoryboard` — this class builds its UI in code.
///
/// ## Objective-C subclassing
/// ```objc
/// // NotificationViewController.h
/// @import AppsOnAir_AppPush;   // CocoaPods
///
/// @interface NotificationViewController : AOAContentViewController
/// @end
///
/// // NotificationViewController.m
/// @implementation NotificationViewController
/// - (void)configureWithNotification:(UNNotification *)notification {
///     [super configureWithNotification:notification]; // keeps image + title + body
///     // add your own customisation here
/// }
/// @end
/// ```
///
/// Set `NSExtensionPrincipalClass` to `NotificationViewController`.
@objc(AOAContentViewController)
open class AOAContentViewController: UIViewController, UNNotificationContentExtension {

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
        configureWithNotification(notification)
    }

    // MARK: - Subclass hook

    /// Apply content from the notification to the UI.
    /// Override to add custom behaviour — call `super` to keep the built-in
    /// image, title, and body display.
    ///
    /// - Note: This method is named `configureWithNotification:` in Objective-C.
    @objc open func configureWithNotification(_ notification: UNNotification) {
        let content = notification.request.content
        titleLabel.text = content.title
        bodyLabel.text  = content.body

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

        imageView.contentMode   = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden      = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font          = .boldSystemFont(ofSize: 16)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.font          = .systemFont(ofSize: 14)
        bodyLabel.textColor     = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis      = .vertical
        contentStack.spacing   = 6
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(bodyLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.addSubview(imageView)
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 200),

            contentStack.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
    }

    private func updatePreferredContentSize(hasImage: Bool) {
        let imageHeight: CGFloat = hasImage ? 200 : 0
        let textHeight: CGFloat  = 80
        let total = imageHeight + textHeight + 12 + 16
        preferredContentSize = CGSize(width: view.bounds.width, height: total)
    }
}
