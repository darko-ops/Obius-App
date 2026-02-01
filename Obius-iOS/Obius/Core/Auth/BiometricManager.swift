import Foundation
import LocalAuthentication
import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Result of a biometric authentication attempt
enum BiometricResult {
    case success
    case cancelled
    case failed(Error)
    case notAvailable
}

/// Manages biometric authentication (FaceID/TouchID) for locked sections
@MainActor
final class BiometricManager: ObservableObject {
    
    static let shared = BiometricManager()
    
    /// Set of section IDs that have been authenticated this session
    @Published private(set) var authenticatedSections: Set<String> = []
    
    /// Whether biometric authentication is available on this device
    @Published private(set) var isBiometricAvailable: Bool = false
    
    /// The type of biometric available (FaceID, TouchID, or none)
    @Published private(set) var biometricType: LABiometryType = .none
    
    /// Whether authentication is currently in progress
    @Published private(set) var isAuthenticating: Bool = false
    
    /// Last authentication error message
    @Published var lastError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        checkBiometricAvailability()
        setupAppLifecycleObservers()
    }
    
    // MARK: - Lifecycle
    
    private func setupAppLifecycleObservers() {
        #if os(iOS)
        // Revoke all authentications when app goes to background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.revokeAllAuthentications()
            }
            .store(in: &cancellables)
        
        // Re-check biometric availability when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkBiometricAvailability()
            }
            .store(in: &cancellables)
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Check if biometric authentication is available
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricType = context.biometryType
    }
    
    /// Handle the complete lock/unlock toggle flow
    /// - Parameters:
    ///   - sectionId: The section to lock/unlock
    ///   - isCurrentlyLocked: Whether the section is currently locked
    ///   - onToggle: Callback to actually toggle the lock state in the database
    /// - Returns: Whether the toggle was successful
    func handleLockToggle(
        sectionId: String,
        isCurrentlyLocked: Bool,
        onToggle: @escaping () async throws -> Void
    ) async -> Bool {
        if isCurrentlyLocked {
            // Unlocking - requires authentication first
            let authenticated = await authenticate(for: sectionId)
            if authenticated {
                do {
                    try await onToggle()
                    // Keep authenticated so they can view content
                    return true
                } catch {
                    lastError = "Failed to unlock: \(error.localizedDescription)"
                    return false
                }
            } else {
                return false
            }
        } else {
            // Locking - no authentication needed, just toggle
            do {
                try await onToggle()
                // Remove from authenticated set since it's now locked
                authenticatedSections.remove(sectionId)
                return true
            } catch {
                lastError = "Failed to lock: \(error.localizedDescription)"
                return false
            }
        }
    }
    
    /// Authenticate to unlock a specific section
    /// - Parameter sectionId: The ID of the section to unlock
    /// - Returns: Whether authentication was successful
    func authenticate(for sectionId: String) async -> Bool {
        // Already authenticated this session
        if authenticatedSections.contains(sectionId) {
            return true
        }
        
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }
        
        let result = await performAuthentication(reason: "Unlock this section to view its contents")
        
        switch result {
        case .success:
            authenticatedSections.insert(sectionId)
            #if os(iOS)
            HapticFeedback.notification(.success)
            #endif
            return true
        case .cancelled:
            return false
        case .failed(let error):
            lastError = error.localizedDescription
            #if os(iOS)
            HapticFeedback.notification(.error)
            #endif
            return false
        case .notAvailable:
            // If no biometrics, try passcode
            let passcodeResult = await performPasscodeAuthentication(
                reason: "Unlock this section to view its contents"
            )
            if case .success = passcodeResult {
                authenticatedSections.insert(sectionId)
                return true
            }
            return false
        }
    }
    
    /// Authenticate without associating with a specific section (for bulk operations)
    func authenticateGeneral(reason: String) async -> BiometricResult {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }
        
        return await performAuthentication(reason: reason)
    }
    
    /// Perform biometric authentication
    private func performAuthentication(reason: String) async -> BiometricResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                return .failed(error)
            }
            return .notAvailable
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .success : .failed(NSError(domain: "BiometricManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"]))
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .userFallback:
                // User chose passcode
                return await performPasscodeAuthentication(reason: reason)
            default:
                return .failed(error)
            }
        } catch {
            return .failed(error)
        }
    }
    
    /// Authenticate using device passcode as fallback
    private func performPasscodeAuthentication(reason: String) async -> BiometricResult {
        let context = LAContext()
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error = error {
                return .failed(error)
            }
            return .notAvailable
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success ? .success : .failed(NSError(domain: "BiometricManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"]))
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            default:
                return .failed(error)
            }
        } catch {
            return .failed(error)
        }
    }
    
    /// Check if a section is currently authenticated
    func isAuthenticated(sectionId: String) -> Bool {
        authenticatedSections.contains(sectionId)
    }
    
    /// Revoke authentication for a specific section
    func revokeAuthentication(for sectionId: String) {
        authenticatedSections.remove(sectionId)
    }
    
    /// Revoke all authentications (e.g., when app goes to background)
    func revokeAllAuthentications() {
        authenticatedSections.removeAll()
    }
    
    /// Lock a section and require re-authentication
    func lockSection(_ sectionId: String) {
        authenticatedSections.remove(sectionId)
    }
    
    // MARK: - Display Helpers
    
    /// Human-readable name for the biometric type
    var biometricTypeName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Passcode"
        @unknown default:
            return "Biometrics"
        }
    }
    
    /// SF Symbol for the biometric type
    var biometricIcon: String {
        switch biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        @unknown default:
            return "lock.fill"
        }
    }
    
    /// Localized prompt for the lock action
    var lockPrompt: String {
        "Lock with \(biometricTypeName)"
    }
    
    /// Localized prompt for the unlock action
    var unlockPrompt: String {
        "Unlock with \(biometricTypeName)"
    }
}

// MARK: - Lock Button View

/// A button that handles the lock/unlock flow with biometric authentication
struct LockButton: View {
    let isLocked: Bool
    let sectionId: String
    let onToggle: () async throws -> Void
    
    @StateObject private var biometricManager = BiometricManager.shared
    @State private var isProcessing = false
    
    var body: some View {
        Button {
            Task {
                isProcessing = true
                _ = await biometricManager.handleLockToggle(
                    sectionId: sectionId,
                    isCurrentlyLocked: isLocked,
                    onToggle: onToggle
                )
                isProcessing = false
            }
        } label: {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Label(
                    isLocked ? "Unlock" : "Lock",
                    systemImage: isLocked ? "lock.open.fill" : "lock.fill"
                )
            }
        }
        .disabled(isProcessing)
    }
}

// MARK: - Biometric Badge View

/// Shows the biometric type icon with authentication status
struct BiometricBadge: View {
    let isLocked: Bool
    let isAuthenticated: Bool
    
    @StateObject private var biometricManager = BiometricManager.shared
    
    var body: some View {
        if isLocked {
            Image(systemName: isAuthenticated ? "lock.open.fill" : biometricManager.biometricIcon)
                .font(.caption)
                .foregroundStyle(isAuthenticated ? .green : .orange)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
