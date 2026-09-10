import Foundation

@MainActor
final class RefreshLoop {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(180)) {
        self.interval = interval
    }

    func start(_ tick: @escaping @MainActor () async -> Void) {
        stop()
        task = Task { [interval] in
            while !Task.isCancelled {
                await tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
