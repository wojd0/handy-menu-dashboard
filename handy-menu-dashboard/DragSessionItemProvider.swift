import Foundation

nonisolated final class DragSessionItemProvider: NSItemProvider {
    private let onEnd: @Sendable () -> Void

    init(text: String, onEnd: @escaping @Sendable () -> Void) {
        self.onEnd = onEnd
        super.init(item: text as NSString, typeIdentifier: "public.utf8-plain-text")
    }

    deinit {
        onEnd()
    }
}
