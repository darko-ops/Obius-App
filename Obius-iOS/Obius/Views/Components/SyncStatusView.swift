import SwiftUI

/// Displays current sync status
struct SyncStatusView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var syncState: SyncEngine.SyncState = .idle
    @State private var lastSyncDate: Date?
    @State private var pendingCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task {
            await observeSyncState()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch syncState {
        case .idle:
            if !networkMonitor.isConnected {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            } else if pendingCount > 0 {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch syncState {
        case .idle:
            if !networkMonitor.isConnected {
                Text("Offline")
            } else if pendingCount > 0 {
                Text("\(pendingCount) pending")
            } else if let date = lastSyncDate {
                Text("Synced \(date, style: .relative) ago")
            } else {
                Text("Synced")
            }
        case .syncing:
            Text("Syncing...")
        case .error(let message):
            Text(message)
                .lineLimit(1)
        case .offline:
            Text("Offline")
        }
    }

    private func observeSyncState() async {
        // Observe sync engine state changes
        for await state in await appState.syncEngine.$syncState.values {
            syncState = state
        }
    }
}

/// Compact sync indicator for toolbar
struct SyncIndicator: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var syncState: SyncEngine.SyncState = .idle
    @State private var pendingCount: Int = 0

    var body: some View {
        Button {
            Task {
                await appState.triggerSync()
            }
        } label: {
            ZStack {
                icon
                    .font(.body)

                if pendingCount > 0 && syncState != .syncing {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .disabled(syncState == .syncing || !networkMonitor.isConnected)
        .task {
            await observeSyncState()
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch syncState {
        case .idle:
            if !networkMonitor.isConnected {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        case .syncing:
            ProgressView()
                .scaleEffect(0.8)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
        }
    }

    private func observeSyncState() async {
        for await state in await appState.syncEngine.$syncState.values {
            syncState = state
        }

        for await count in await appState.syncEngine.$pendingChangesCount.values {
            pendingCount = count
        }
    }
}

/// Pull-to-refresh sync modifier
struct SyncRefreshModifier: ViewModifier {
    @EnvironmentObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .refreshable {
                await appState.triggerSync()
            }
    }
}

extension View {
    func syncRefreshable() -> some View {
        modifier(SyncRefreshModifier())
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusView()
        SyncIndicator()
    }
    .environmentObject(AppState())
}
