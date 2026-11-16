import AudioToolbox
import UIKit

/// Feedback fired when a brick completes while the app is in the foreground.
enum Haptics {
    private static let notifier = UINotificationFeedbackGenerator()

    /// Success-style haptic for an up brick, warning-style for a down brick.
    static func brickHaptic(up: Bool) {
        notifier.notificationOccurred(up ? .success : .warning)
    }

    /// Subtle "Tink" system sound for a completed brick.
    static func playBrickSound() {
        AudioServicesPlaySystemSound(1104)
    }
}
