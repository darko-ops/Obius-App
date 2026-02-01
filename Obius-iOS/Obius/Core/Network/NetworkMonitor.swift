import Foundation
import Network
import Combine

/// Monitors network connectivity status
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }

    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        }
        return .unknown
    }

    deinit {
        monitor.cancel()
    }
}
