import SwiftUI

struct EntitySuggestionBanner: View {
    let entities: [ExtractedEntity]
    let onPromote: (ExtractedEntity) -> Void
    let onDismiss: (ExtractedEntity) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entities) { entity in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.purple)

                        Text("@\(entity.name)")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Button {
                            onPromote(entity)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }

                        Button {
                            onDismiss(entity)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
