import UserNotifications
import os.log

enum NotificationService {

    private static let logger = Logger(subsystem: "com.sahan.Nix", category: "NotificationService")

    // ─────────────────────────────────────────────────────────────
    // MARK: - Authorization
    // ─────────────────────────────────────────────────────────────

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    logger.error("Authorization error: \(error.localizedDescription)")
                }
                logger.info("requestAuthorization completed — granted: \(granted)")
                logCurrentStatus(context: "post-request")
            }
    }

    /// Dumps full notification settings to console. This is the ground truth —
    /// check this log line before touching any other code.
    static func logCurrentStatus(context: String = "manual") {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let statusName: String
            switch settings.authorizationStatus {
            case .authorized:    statusName = "authorized"
            case .denied:        statusName = "DENIED — go to System Settings → Notifications → Nix → enable manually. Code cannot force this."
            case .notDetermined: statusName = "notDetermined — system prompt has not been answered yet"
            case .provisional:   statusName = "provisional"
            case .ephemeral:     statusName = "ephemeral"
            @unknown default:    statusName = "unknown"
            }
            logger.info("""
                [\(context)] authorizationStatus=\(statusName) \
                alertSetting=\(settings.alertSetting.rawValue) \
                soundSetting=\(settings.soundSetting.rawValue) \
                alertStyle=\(settings.alertStyle.rawValue)
                """)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Delivery
    // ─────────────────────────────────────────────────────────────

    static func show(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
                logger.warning("SUPPRESSED — authorizationStatus=\(settings.authorizationStatus.rawValue), nothing was sent.")
                return
            }
            guard settings.alertSetting == .enabled else {
                logger.warning("SUPPRESSED — alertSetting=\(settings.alertSetting.rawValue). Check Alert Style in System Settings.")
                return
            }

            let content   = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content:    content,
                trigger:    nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    logger.error("Delivery error: \(error.localizedDescription)")
                } else {
                    logger.info("✅ Handed to Notification Center: '\(title)' — \(body)")
                }
            }
        }
    }

    #if DEBUG
    /// Bypasses QuitEngine entirely — fires directly to isolate the failure point.
    static func sendTestNotification() {
        logCurrentStatus(context: "test-trigger")
        show(title: "Nix — Test", body: "If you see this, delivery works end-to-end.")
    }
    #endif
}
