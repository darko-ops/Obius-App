import SwiftUI

// MARK: - Insight Card (Surfaced)

struct InsightCardView: View {
    let insight: Insight
    let onTrack: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: type badge + timestamp
            HStack {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: insight.insightType.icon)
                        .font(.caption2)
                    Text(insight.insightType.label)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(insight.insightType.tint.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(insight.insightType.tint.color.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Title
            Text(insight.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            // Body
            if !insight.body.isEmpty {
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Action row
            HStack(spacing: 10) {
                if insight.insightType == .nonsenseContent, let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption2)
                            Text("Delete Page")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        onTrack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star")
                                .font(.caption2)
                            Text("Track")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(insight.insightType.tint.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(insight.insightType.tint.color.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                        Text("Dismiss")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(insight.insightType.tint.color.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var relativeTimestamp: String {
        let date = Date(timeIntervalSince1970: Double(insight.createdAt) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tracked Insight Card (Compact, horizontal scroll)

struct TrackedInsightChip: View {
    let insight: Insight
    let onTap: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type badge
            HStack(spacing: 4) {
                Image(systemName: insight.insightType.icon)
                    .font(.system(size: 9))
                Text(insight.insightType.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(insight.insightType.tint.color)

            // Title
            Text(insight.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            // Body preview
            Text(insight.body.isEmpty ? " " : insight.body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(width: 150, height: 100, alignment: .topLeading)
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(insight.insightType.tint.color.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Insight Detail Sheet

struct InsightDetailSheet: View {
    let insight: Insight
    let onTrack: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onUntrack: (() -> Void)?
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Type badge
                    HStack(spacing: 6) {
                        Image(systemName: insight.insightType.icon)
                            .font(.subheadline)
                        Text(insight.insightType.label)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(insight.insightType.tint.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(insight.insightType.tint.color.opacity(0.15))
                    .clipShape(Capsule())

                    // Title
                    Text(insight.title)
                        .font(.title3.weight(.semibold))

                    // Body
                    if !insight.body.isEmpty {
                        Text(insight.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Timestamp
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Divider()

                    // Actions
                    if insight.status == .surfaced {
                        if insight.insightType == .nonsenseContent, let onDelete {
                            HStack(spacing: 12) {
                                Button {
                                    onDelete()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                        Text("Delete Page")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                                Button {
                                    onDismiss?()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                        Text("Dismiss")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button {
                                    onTrack?()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "star")
                                        Text("Track")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(insight.insightType.tint.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(insight.insightType.tint.color.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                                Button {
                                    onDismiss?()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                        Text("Dismiss")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    } else if insight.status == .tracked {
                        Button {
                            onUntrack?()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "star.slash")
                                Text("Untrack")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(insight.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Create Insight Sheet

struct CreateInsightSheet: View {
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Title") {
                    TextField("What are you tracking?", text: $title)
                }

                SwiftUI.Section("Details") {
                    TextField("Add details...", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onCreate(title, details)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
