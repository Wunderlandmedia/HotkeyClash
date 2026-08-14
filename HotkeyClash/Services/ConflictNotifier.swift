import UserNotifications
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ConflictNotifier")

/// Posts a local notification when a background rescan turns up conflicts that
/// weren't there before. This only matters for the auto rescan: a manual rescan
/// already puts the result on screen, so there's nothing to tell the user they
/// can't already see.
///
/// Kept deliberately quiet. Nothing is requested or posted unless the user has
/// opted in (the Settings switch), and permission is only asked for at the moment
/// they flip it on, so the system prompt lands where they'd expect it rather than
/// unbidden at launch.
@MainActor
final class ConflictNotifier {

    private let center = UNUserNotificationCenter.current()

    /// Ask the user to allow notifications. Called when the Settings switch goes on.
    /// Returns whether it was granted, so the toggle can flip itself back if the
    /// user declines rather than sitting on enabled-but-silent.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Post a banner summarizing the conflicts that just appeared. No-op on an empty
    /// list. Delivery still depends on the user having granted permission; if they
    /// revoked it after opting in, the center simply drops the request.
    func notify(newConflicts: [Conflict]) {
        guard !newConflicts.isEmpty else { return }

        let text = ConflictDiff.notificationText(newConflicts: newConflicts)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default

        // A nil trigger fires immediately. The identifier is per-post (UUID) so a
        // burst of rescans stacks rather than replacing one another in Notification
        // Center.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                logger.error("Failed to post conflict notification: \(error.localizedDescription)")
            }
        }
    }
}
