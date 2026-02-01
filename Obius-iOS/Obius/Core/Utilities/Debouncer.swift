import Foundation
import Combine

/// Debounces rapid calls to a function
final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

/// Throttles calls to a function (executes at most once per interval)
final class Throttler {
    private let interval: TimeInterval
    private var lastExecutionTime: Date?
    private let queue: DispatchQueue

    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    func throttle(action: @escaping () -> Void) {
        let now = Date()

        if let lastTime = lastExecutionTime,
           now.timeIntervalSince(lastTime) < interval {
            return
        }

        lastExecutionTime = now
        queue.async(execute: action)
    }

    func reset() {
        lastExecutionTime = nil
    }
}

// MARK: - Async Debouncer

actor AsyncDebouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    func debounce(operation: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await operation()
            } catch {
                // Task was cancelled
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Publisher Extension

extension Publisher {
    /// Debounce with custom scheduler
    func debounce(for interval: TimeInterval) -> AnyPublisher<Output, Failure> {
        self.debounce(for: .seconds(interval), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Throttle with custom scheduler
    func throttle(for interval: TimeInterval, latest: Bool = true) -> AnyPublisher<Output, Failure> {
        self.throttle(for: .seconds(interval), scheduler: DispatchQueue.main, latest: latest)
            .eraseToAnyPublisher()
    }
}
