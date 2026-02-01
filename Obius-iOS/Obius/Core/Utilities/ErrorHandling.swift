import Foundation
import SwiftUI

// MARK: - App Errors

enum ObiusError: LocalizedError {
    // Database
    case databaseCorrupted
    case migrationFailed(version: Int)
    case entityNotFound(type: String, id: String)
    case saveFailed(reason: String)

    // Sync
    case syncFailed(underlying: Error)
    case conflictUnresolvable(entityId: String)
    case networkUnavailable
    case serverError(code: Int, message: String)

    // AI
    case aiUnavailable
    case embeddingFailed(reason: String)
    case summaryFailed(reason: String)
    case quotaExceeded

    // Auth
    case sessionExpired
    case unauthorized
    case invalidCredentials

    // General
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .databaseCorrupted:
            return "Database is corrupted. Please reinstall the app."
        case .migrationFailed(let version):
            return "Failed to upgrade database to version \(version)."
        case .entityNotFound(let type, let id):
            return "\(type) with id \(id) not found."
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"

        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .conflictUnresolvable(let id):
            return "Could not resolve conflict for item \(id)."
        case .networkUnavailable:
            return "No internet connection. Changes will sync when online."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"

        case .aiUnavailable:
            return "AI features are temporarily unavailable."
        case .embeddingFailed(let reason):
            return "Failed to process content: \(reason)"
        case .summaryFailed(let reason):
            return "Failed to generate summary: \(reason)"
        case .quotaExceeded:
            return "AI usage limit reached. Please try again later."

        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .unauthorized:
            return "You don't have permission to perform this action."
        case .invalidCredentials:
            return "Invalid email or password."

        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .databaseCorrupted:
            return "Your data may be recoverable from cloud backup after reinstalling."
        case .networkUnavailable:
            return "Your changes are saved locally and will sync automatically."
        case .sessionExpired, .unauthorized:
            return "Tap to sign in."
        case .quotaExceeded:
            return "Upgrade to Pro for unlimited AI features."
        default:
            return nil
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .networkUnavailable, .sessionExpired, .quotaExceeded:
            return true
        case .databaseCorrupted, .migrationFailed:
            return false
        default:
            return true
        }
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlert: ViewModifier {
    @Binding var error: ObiusError?
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                ),
                presenting: error
            ) { _ in
                Button("OK") {
                    error = nil
                    onDismiss?()
                }
            } message: { error in
                VStack {
                    Text(error.localizedDescription)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
    }
}

extension View {
    func errorAlert(_ error: Binding<ObiusError?>, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlert(error: error, onDismiss: onDismiss))
    }
}

// MARK: - Toast Notification

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: Double = 2.0

    func body(content: Content) -> some View {
        ZStack {
            content

            if let message = message {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(), value: message)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation {
                            self.message = nil
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>, duration: Double = 2.0) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

// MARK: - Result Extension

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }

    var error: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}

// MARK: - Task Error Handling

extension Task where Failure == Never, Success == Void {
    /// Execute an async operation with error handling
    @discardableResult
    static func catching(
        priority: TaskPriority? = nil,
        operation: @escaping () async throws -> Void,
        onError: @escaping (Error) -> Void
    ) -> Task<Void, Never> {
        Task(priority: priority) {
            do {
                try await operation()
            } catch {
                onError(error)
            }
        }
    }
}

// MARK: - Logging

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

struct Logger {
    static let shared = Logger()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function): \(message)")
        #endif
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    func error(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        log(error.localizedDescription, level: .error, file: file, function: function, line: line)
    }
}

let logger = Logger.shared
