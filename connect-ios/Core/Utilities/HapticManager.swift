//
//  HapticManager.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Haptic feedback manager for tactile user interactions
//

import UIKit
import Foundation

enum HapticManager {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    // MARK: - Settings Check

    /// Check if haptic feedback is enabled in user settings
    private static var isHapticEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptic_feedback_enabled") as? Bool ?? true
    }

    // MARK: - Impact Feedback

    /// Light impact - for subtle interactions (e.g., button taps, minor state changes)
    static func light() {
        guard isHapticEnabled else { return }
        impactLight.impactOccurred()
    }

    /// Medium impact - for standard interactions (e.g., selections, toggles)
    static func medium() {
        guard isHapticEnabled else { return }
        impactMedium.impactOccurred()
    }

    /// Heavy impact - for significant interactions (e.g., deletions, important actions)
    static func heavy() {
        guard isHapticEnabled else { return }
        impactHeavy.impactOccurred()
    }

    /// Soft impact - for gentle interactions (e.g., hovering, previewing)
    static func soft() {
        guard isHapticEnabled else { return }
        impactSoft.impactOccurred()
    }

    /// Rigid impact - for precise interactions (e.g., snapping, locking)
    static func rigid() {
        guard isHapticEnabled else { return }
        impactRigid.impactOccurred()
    }

    // MARK: - Selection Feedback

    /// Selection feedback - for changing selections (e.g., picker, segmented control)
    static func selection() {
        guard isHapticEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    // MARK: - Notification Feedback

    /// Success notification - for successful operations
    static func success() {
        guard isHapticEnabled else { return }
        notification.notificationOccurred(.success)
    }

    /// Warning notification - for warnings or cautions
    static func warning() {
        guard isHapticEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    /// Error notification - for errors or failures
    static func error() {
        guard isHapticEnabled else { return }
        notification.notificationOccurred(.error)
    }

    // MARK: - Prepared Feedback

    /// Prepares haptic engine for upcoming feedback (reduces latency)
    static func prepare() {
        impactMedium.prepare()
        selectionGenerator.prepare()
        notification.prepare()
    }

    // MARK: - Common Use Cases

    /// Haptic for button press
    static func buttonPress() {
        soft()
    }

    /// Haptic for toggle switch
    static func toggle() {
        medium()
    }

    /// Haptic for device selection
    static func deviceSelection() {
        selection()
    }

    /// Haptic for drive/route selection
    static func routeSelection() {
        soft()
    }

    /// Haptic for video seek/scrub
    static func videoScrub() {
        light()
    }

    /// Haptic for timeline zoom
    static func timelineZoom() {
        rigid()
    }

    /// Haptic for pull-to-refresh
    static func refresh() {
        medium()
    }

    /// Haptic for successful action (e.g., device paired, route preserved)
    static func actionSuccess() {
        success()
    }

    /// Haptic for failed action
    static func actionError() {
        error()
    }

    /// Haptic for warning (e.g., approaching preservation limit)
    static func actionWarning() {
        warning()
    }

    /// Haptic for deletion
    static func delete() {
        heavy()
    }

    /// Haptic for cancellation
    static func cancel() {
        medium()
    }
}

// MARK: - SwiftUI View Extension

import SwiftUI

extension View {
    /// Adds haptic feedback on tap
    func hapticFeedback(_ style: HapticFeedbackStyle = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                switch style {
                case .light:
                    HapticManager.light()
                case .medium:
                    HapticManager.medium()
                case .heavy:
                    HapticManager.heavy()
                case .soft:
                    HapticManager.soft()
                case .rigid:
                    HapticManager.rigid()
                case .selection:
                    HapticManager.selection()
                }
            }
        )
    }
}

enum HapticFeedbackStyle {
    case light, medium, heavy, soft, rigid, selection
}
