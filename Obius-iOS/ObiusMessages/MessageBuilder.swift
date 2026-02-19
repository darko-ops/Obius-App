import Messages
import UIKit

/// Builds MSMessage objects from MessageSharePayload data.
@MainActor
enum MessageBuilder {

    /// Creates an MSMessage with a template layout and rendered card image.
    static func buildMessage(from payload: MessageSharePayload) -> MSMessage {
        let message = MSMessage()
        let layout = MSMessageTemplateLayout()

        // Render the branded card image
        let cardImage: UIImage
        if #available(iOS 16.0, *) {
            cardImage = NodeImageRenderer.renderCard(from: payload)
        } else {
            cardImage = MessageCardRenderer.renderCard(from: payload)
        }
        layout.image = cardImage

        // Captions
        layout.caption = payload.title
        layout.trailingCaption = payload.shareType == "commit" ? "Snapshot" : "Live"

        if let commitId = payload.commitShortId {
            layout.subcaption = "#\(commitId)"
        }

        if let creator = payload.creatorName {
            layout.trailingSubcaption = creator
        }

        message.layout = layout

        // Encode slug and type into the URL for the expanded view
        var components = URLComponents()
        components.scheme = "https"
        components.host = "obius.io"
        components.path = "/s/\(payload.slug)"
        components.queryItems = [
            URLQueryItem(name: "type", value: payload.shareType)
        ]
        if let noteId = payload.noteId {
            components.queryItems?.append(URLQueryItem(name: "note_id", value: noteId))
        }
        message.url = components.url

        return message
    }

    /// Extracts the slug from an MSMessage URL.
    static func extractSlug(from message: MSMessage) -> String? {
        guard let url = message.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // Path format: /s/{slug}
        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.count >= 2, pathComponents[0] == "s" else { return nil }
        return String(pathComponents[1])
    }

    /// Extracts the note_id query parameter from an MSMessage URL (for offline fallback).
    static func extractNoteId(from message: MSMessage) -> String? {
        guard let url = message.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "note_id" })?.value
    }
}
