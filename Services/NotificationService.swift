import UserNotifications
import os.log

enum NotificationService {

    private static let logger = Logger(subsystem: "com.sahan.Nix", category: "NotificationService")

    // ─────────────────────────────────────────────────────────────
    // MARK: - Authorization
    // ─────────────────────────────────────────────────────────────

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    print("[NotificationService] Authorization error: \(error.localizedDescription)")
                }
                print("[NotificationService] Authorization granted: \(granted)")
            }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Delivery
    // ─────────────────────────────────────────────────────────────

    static func show(title: String, body: String) {
        let content       = UNMutableNotificationContent()
        content.title     = title
        content.body      = body
        content.sound     = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content:    content,
            trigger:    nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Delivery error: \(error.localizedDescription)")
            }
        }
    }
}
