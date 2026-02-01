import SwiftUI

// MARK: - Möbius Navigation State

/// Manages the navigation stack for drilling into section children
@MainActor
final class MöbiusNavigationState: ObservableObject {
    /// The stack of section IDs representing the navigation path
    @Published var navigationPath: [String] = []
    
    /// Animation trigger for matched geometry
    @Published var animationTrigger: UUID = UUID()
    
    /// The currently focused section (root level if nil)
    var currentParentId: String? {
        navigationPath.last
    }
    
    /// Whether we're at the root level
    var isAtRoot: Bool {
        navigationPath.isEmpty
    }
    
    /// The depth of navigation
    var depth: Int {
        navigationPath.count
    }
    
    /// Push into a section's children
    func drillInto(_ sectionId: String) {
        navigationPath.append(sectionId)
        animationTrigger = UUID()
    }
    
    /// Pop back to parent level
    func popBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        animationTrigger = UUID()
    }
    
    /// Pop back to root
    func popToRoot() {
        navigationPath.removeAll()
        animationTrigger = UUID()
    }
    
    /// Pop to a specific level in the path
    func popTo(_ sectionId: String) {
        if let index = navigationPath.firstIndex(of: sectionId) {
            navigationPath = Array(navigationPath.prefix(through: index))
            animationTrigger = UUID()
        }
    }
    
    /// Get the section ID at a specific depth (nil for root)
    func sectionIdAt(depth: Int) -> String? {
        guard depth > 0, depth <= navigationPath.count else { return nil }
        return navigationPath[depth - 1]
    }
}

// MARK: - Möbius Namespace Environment Key

private struct MöbiusNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var möbiusNamespace: Namespace.ID? {
        get { self[MöbiusNamespaceKey.self] }
        set { self[MöbiusNamespaceKey.self] = newValue }
    }
}

// MARK: - Möbius Container View

/// Container view that handles the unfolding transition animation with matched geometry
struct MöbiusContainer<Content: View>: View {
    @ObservedObject var navigationState: MöbiusNavigationState
    let sections: [Section]
    let content: (Section?, [Section]) -> Content
    
    @Namespace private var möbiusNamespace
    @State private var previousParentId: String?
    
    /// Get sections visible at current navigation level
    private var visibleSections: [Section] {
        sections.filter { section in
            section.parentSectionId == navigationState.currentParentId
        }
    }
    
    /// Get the current parent section (if navigated into one)
    private var currentParentSection: Section? {
        guard let parentId = navigationState.currentParentId else { return nil }
        return sections.first { $0.id == parentId }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            if !navigationState.isAtRoot {
                MöbiusBreadcrumb(
                    path: buildBreadcrumbPath(),
                    namespace: möbiusNamespace,
                    onNavigate: { sectionId in
                        withAnimation(.möbiusUnfold) {
                            if let id = sectionId {
                                navigationState.popTo(id)
                            } else {
                                navigationState.popToRoot()
                            }
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Content with matched geometry for smooth transitions
            ZStack {
                content(currentParentSection, visibleSections)
                    .id(navigationState.currentParentId ?? "root")
            }
            .animation(.möbiusUnfold, value: navigationState.animationTrigger)
        }
        .environment(\.möbiusNamespace, möbiusNamespace)
        .onChange(of: navigationState.currentParentId) { old, new in
            previousParentId = old
        }
    }
    
    private func buildBreadcrumbPath() -> [(id: String?, title: String)] {
        var path: [(id: String?, title: String)] = [(nil, "Note")]
        
        for sectionId in navigationState.navigationPath {
            if let section = sections.first(where: { $0.id == sectionId }) {
                path.append((sectionId, section.displayTitle))
            }
        }
        
        return path
    }
}

// MARK: - Möbius Section Card

/// A section card that supports matched geometry for smooth drill-in/out transitions
struct MöbiusSectionCard: View {
    let section: Section
    let isSource: Bool  // Whether this is the source of a drill-in animation
    let namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Intent indicator
            HStack(spacing: 8) {
                Image(systemName: section.intent.icon)
                    .foregroundStyle(section.intent.color)
                
                if let title = section.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                
                Spacer()
                
                if section.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Text(section.preview)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(section.intent.backgroundTint)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .matchedGeometryEffect(
            id: "section-\(section.id)",
            in: namespace,
            properties: .frame,
            isSource: isSource
        )
    }
}

// MARK: - Möbius Breadcrumb

/// Breadcrumb navigation for showing path through sections
struct MöbiusBreadcrumb: View {
    let path: [(id: String?, title: String)]
    let namespace: Namespace.ID
    let onNavigate: (String?) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Button {
                        withAnimation(.möbiusUnfold) {
                            onNavigate(item.id)
                        }
                        HapticFeedback.selection()
                    } label: {
                        Text(item.title)
                            .font(.caption)
                            .fontWeight(index == path.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                index == path.count - 1 
                                    ? Color.accentColor.opacity(0.1) 
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(
                        id: "breadcrumb-\(item.id ?? "root")",
                        in: namespace,
                        properties: .position
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .horizontal)
        )
    }
}

// MARK: - Möbius Section Header

/// Header view for a section when drilled into, showing section info and back button
struct MöbiusSectionHeader: View {
    let section: Section
    let onBack: () -> Void
    
    @Environment(\.möbiusNamespace) private var namespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Back button
            Button {
                withAnimation(.möbiusUnfold) {
                    onBack()
                }
                HapticFeedback.selection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                    Text("Back")
                        .font(.body)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            // Section header with intent rail
            HStack(spacing: 0) {
                // Intent rail
                RoundedRectangle(cornerRadius: 2)
                    .fill(section.intent.color)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Title with matched geometry
                    HStack {
                        Text(section.displayTitle)
                            .font(.title2.weight(.semibold))
                        
                        Spacer()
                        
                        // Biometric badge
                        if section.isLocked {
                            BiometricBadge(
                                isLocked: section.isLocked,
                                isAuthenticated: BiometricManager.shared.isAuthenticated(sectionId: section.id)
                            )
                        }
                    }
                    
                    // Content preview
                    if !section.content.isEmpty {
                        Text(section.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    
                    // Metadata row
                    HStack(spacing: 12) {
                        Label(section.intent.displayName, systemImage: section.intent.icon)
                            .foregroundStyle(section.intent.color)
                        
                        if section.isLocked {
                            Label("Protected", systemImage: "lock.shield")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
                .padding(.leading, 12)
            }
            .padding()
            .background(section.intent.backgroundTint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .optionalMatchedGeometry(
                id: "section-\(section.id)",
                namespace: namespace
            )
        }
        .padding()
    }
}

// MARK: - Drill-In Button

/// Button overlay for sections that have children, allowing drill-in with matched geometry
struct DrillInButton: View {
    let hasChildren: Bool
    let childCount: Int
    let onDrillIn: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        if hasChildren {
            Button {
                withAnimation(.möbiusUnfold) {
                    onDrillIn()
                }
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: 4) {
                    if childCount > 0 {
                        Text("\(childCount)")
                            .font(.caption2.weight(.semibold))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                    }
            )
        }
    }
}

// MARK: - Möbius Transition

extension AnyTransition {
    /// Custom unfold transition for Möbius navigation
    static var möbiusUnfold: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MöbiusTransitionModifier(offset: 1, scale: 0.92, opacity: 0),
                identity: MöbiusTransitionModifier(offset: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: MöbiusTransitionModifier(offset: -1, scale: 0.92, opacity: 0),
                identity: MöbiusTransitionModifier(offset: 0, scale: 1, opacity: 1)
            )
        )
    }
    
    /// Reverse unfold for going back
    static var möbiusFold: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MöbiusTransitionModifier(offset: -1, scale: 0.92, opacity: 0),
                identity: MöbiusTransitionModifier(offset: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: MöbiusTransitionModifier(offset: 1, scale: 0.92, opacity: 0),
                identity: MöbiusTransitionModifier(offset: 0, scale: 1, opacity: 1)
            )
        )
    }
}

/// Custom transition modifier for Möbius animations
struct MöbiusTransitionModifier: ViewModifier {
    let offset: CGFloat  // -1 to 1, representing direction
    let scale: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset * 120) // Simplified offset for cross-platform
            .scaleEffect(scale, anchor: offset >= 0 ? .leading : .trailing)
            .opacity(opacity)
    }
}

extension Animation {
    /// Animation timing for Möbius unfold transition
    static var möbiusUnfold: Animation {
        .spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)
    }
    
    /// Faster animation for subtle interactions
    static var möbiusQuick: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }
}

// MARK: - Helper Extensions

extension View {
    /// Apply matched geometry effect only if namespace is available
    @ViewBuilder
    func optionalMatchedGeometry(id: String, namespace: Namespace.ID?) -> some View {
        if let namespace = namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Möbius Navigation") {
    struct PreviewContainer: View {
        @StateObject private var navState = MöbiusNavigationState()
        
        let sections: [Section] = [
            Section(id: "1", noteId: "note1", content: "Parent Section 1 - This is an idea about the project", orderKey: "A", intent: .idea),
            Section(id: "2", noteId: "note1", content: "Parent Section 2 - A task to complete", orderKey: "B", intent: .task),
            Section(id: "3", noteId: "note1", content: "Parent Section 3 - Evidence for the argument", orderKey: "C", intent: .evidence),
            Section(id: "1-1", noteId: "note1", content: "Child of Section 1 - A question to explore", parentSectionId: "1", orderKey: "A", intent: .question),
            Section(id: "1-2", noteId: "note1", content: "Another child of Section 1", parentSectionId: "1", orderKey: "B", intent: .idea),
            Section(id: "1-1-1", noteId: "note1", content: "Grandchild - deep nested content", parentSectionId: "1-1", orderKey: "A", intent: .evidence),
        ]
        
        var body: some View {
            NavigationStack {
                MöbiusContainer(navigationState: navState, sections: sections) { parent, visible in
                    ScrollView {
                        VStack(spacing: 12) {
                            if let parent {
                                MöbiusSectionHeader(section: parent) {
                                    navState.popBack()
                                }
                            }
                            
                            ForEach(visible) { section in
                                HStack {
                                    // Intent rail
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(section.intent.color)
                                        .frame(width: 3)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(section.displayTitle)
                                            .font(.headline)
                                        Text(section.content)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                    
                                    let childCount = sections.filter { $0.parentSectionId == section.id }.count
                                    DrillInButton(
                                        hasChildren: childCount > 0,
                                        childCount: childCount
                                    ) {
                                        navState.drillInto(section.id)
                                    }
                                }
                                .padding()
                                .background(section.intent.backgroundTint)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                            
                            if visible.isEmpty {
                                ContentUnavailableView(
                                    "No Sections",
                                    systemImage: "doc.text",
                                    description: Text("Add a section to get started")
                                )
                                .padding(.top, 60)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                .navigationTitle("Möbius Demo")
                .toolbar {
                    if !navState.isAtRoot {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                withAnimation(.möbiusUnfold) {
                                    navState.popBack()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return PreviewContainer()
}
