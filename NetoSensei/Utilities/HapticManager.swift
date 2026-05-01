//
//  HapticManager.swift
//  NetoSensei
//
//  Haptic feedback manager for enhanced user experience
//

import UIKit

@MainActor
class HapticManager {
    static let shared = HapticManager()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        // Prepare generators
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
    }

    // MARK: - Impact Feedback

    /// Light tap - for subtle interactions
    func light() {
        impactLight.impactOccurred()
        impactLight.prepare()
    }

    /// Medium tap - for standard button presses
    func medium() {
        impactMedium.impactOccurred()
        impactMedium.prepare()
    }

    /// Heavy tap - for important actions
    func heavy() {
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
    }

    // MARK: - Notification Feedback

    /// Success feedback - for completed actions
    func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Warning feedback - for cautionary actions
    func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    /// Error feedback - for failed actions
    func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    // MARK: - Selection Feedback

    /// Selection changed - for picker/toggle changes
    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    // MARK: - Contextual Feedback

    /// Diagnostic started
    func diagnosticStarted() {
        medium()
    }

    /// Diagnostic completed successfully
    func diagnosticCompleted(healthScore: Int) {
        if healthScore >= 80 {
            success()
        } else if healthScore >= 60 {
            light()
        } else {
            warning()
        }
    }

    /// Diagnostic failed
    func diagnosticFailed() {
        error()
    }

    /// Test completed (speed test, etc.)
    func testCompleted() {
        success()
    }

    /// Test failed
    func testFailed() {
        error()
    }

    /// Button tapped
    func buttonTapped() {
        light()
    }

    /// Important button tapped (Run Diagnostic, etc.)
    func primaryButtonTapped() {
        medium()
    }

    /// Destructive button tapped (Cancel, etc.)
    func destructiveButtonTapped() {
        warning()
    }

    /// Auto-fix action triggered
    func autoFixTriggered() {
        medium()
    }

    /// Sheet presented
    func sheetPresented() {
        light()
    }

    /// Sheet dismissed
    func sheetDismissed() {
        light()
    }

    /// Toggle switched
    func toggleSwitched() {
        selectionChanged()
    }

    /// Refresh triggered (pull to refresh)
    func refreshTriggered() {
        light()
    }

    /// VPN region selected
    func regionSelected() {
        selectionChanged()
    }

    /// VPN optimization started
    func optimizationStarted() {
        medium()
    }

    /// VPN optimization completed
    func optimizationCompleted() {
        success()
    }

    /// Security issue detected
    func securityIssueDetected(isCritical: Bool) {
        if isCritical {
            error()
        } else {
            warning()
        }
    }
}
