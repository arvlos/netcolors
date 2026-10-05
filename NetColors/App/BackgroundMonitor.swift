import BackgroundTasks
import SwiftData
import UserNotifications

/// Manages background network checks and degradation notifications.
/// Only alerts on degradation to whitelist or full shutdown — VPN on/off
/// (green ↔ yellow) is ignored to avoid noise.
final class BackgroundMonitor: Sendable {
    static let taskIdentifier = "com.artemlosev.netcolors.refresh"

    static func registerTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60) // 10 min
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Private

    private static func handleRefresh(_ bgTask: BGAppRefreshTask) {
        // Schedule next refresh immediately
        scheduleNextRefresh()

        // BGTask is not Sendable; safe here because completion is called once
        nonisolated(unsafe) let task = bgTask

        let workItem = Task.detached {
            let newMode = await runBackgroundProbes()

            let previousModeRaw = UserDefaults.standard.string(forKey: "lastKnownMode")
            let previousMode = previousModeRaw.flatMap { AccessMode(rawValue: $0) }

            UserDefaults.standard.set(newMode.rawValue, forKey: "lastKnownMode")

            if shouldNotify(previous: previousMode, current: newMode) {
                await sendDegradationNotification(mode: newMode)
            }

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            workItem.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Lightweight probe run for background context (no UI state).
    @MainActor
    private static func runBackgroundProbes() async -> AccessMode {
        let engine = ProbeEngine()
        await engine.runDiagnostics()
        return engine.currentMode
    }

    /// Returns true only for genuine degradation — drops to whitelist or shutdown.
    /// Green ↔ yellow (unrestricted ↔ restricted) is VPN toggle noise, not degradation.
    static func shouldNotify(previous: AccessMode?, current: AccessMode) -> Bool {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return false }

        let isDegraded = current == .fullShutdown || current == .whitelist
        let wasDegraded = previous == .fullShutdown || previous == .whitelist

        // Notify on entering degraded state, not on staying in it
        return isDegraded && !wasDegraded
    }

    private static func sendDegradationNotification(mode: AccessMode) async {
        let content = UNMutableNotificationContent()
        content.title = mode.title
        content.body = mode.statusDescription
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mode-degradation-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // deliver immediately
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
