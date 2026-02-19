import UIKit
import Messages
import SwiftUI

/// Main entry point for the Obius iMessage extension.
class MessagesViewController: MSMessagesAppViewController {

    /// The slug for the currently selected message (used when expanding).
    private var selectedSlug: String?

    /// The note ID from the message URL (used for offline fallback).
    private var selectedNoteId: String?

    /// ViewModel for the expanded view (retained for lifecycle management)
    private var expandedViewModel: ExpandedContentViewModel?

    // MARK: - Lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)

        // Restore auth session from shared keychain before any Supabase calls
        Task {
            await ExtensionSupabaseClient.shared.restoreSession()

            // Check for a pending share payload from the main app
            if let payload = MessageSharePayload.readFromSharedDefaults() {
                let message = MessageBuilder.buildMessage(from: payload)
                conversation.insert(message) { error in
                    if let error {
                        print("[ObiusMessages] Failed to insert message: \(error)")
                    }
                }
                MessageSharePayload.clearSharedDefaults()
            }
        }

        presentCompactView()
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        guard let slug = MessageBuilder.extractSlug(from: message) else { return }
        selectedSlug = slug
        selectedNoteId = MessageBuilder.extractNoteId(from: message)
        requestPresentationStyle(.expanded)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)

        switch presentationStyle {
        case .expanded:
            if let slug = selectedSlug {
                presentExpandedView(slug: slug)
            }
        case .compact:
            presentCompactView()
        case .transcript:
            // Clean up realtime subscriptions when leaving expanded view
            expandedViewModel?.cleanup()
            expandedViewModel = nil
        @unknown default:
            break
        }
    }

    // MARK: - View Presentation

    private func presentCompactView() {
        // Clean up expanded view realtime subscriptions
        expandedViewModel?.cleanup()
        expandedViewModel = nil

        removeAllChildViewControllers()

        let compactView = CompactView { [weak self] message in
            self?.activeConversation?.insert(message) { error in
                if let error {
                    print("[ObiusMessages] Failed to insert message: \(error)")
                }
            }
        }
        let hostingController = UIHostingController(rootView: compactView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func presentExpandedView(slug: String) {
        removeAllChildViewControllers()

        let viewModel = ExpandedContentViewModel(slug: slug, noteId: selectedNoteId)
        self.expandedViewModel = viewModel

        let expandedView = ExpandedContentView(viewModel: viewModel) { [weak self] in
            self?.requestPresentationStyle(.compact)
        }
        let hostingController = UIHostingController(rootView: expandedView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func removeAllChildViewControllers() {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }
}
