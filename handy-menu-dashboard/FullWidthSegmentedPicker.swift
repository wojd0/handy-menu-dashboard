import AppKit
import SwiftUI

struct FullWidthSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Value
    let options: [(title: String, value: Value)]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.setAccessibilityLabel(label)
        if control.segmentCount != options.count {
            control.segmentCount = options.count
        }
        for (index, option) in options.enumerated() where control.label(forSegment: index) != option.title {
            control.setLabel(option.title, forSegment: index)
        }
        if let index = options.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = index
        } else {
            control.selectedSegment = -1
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    final class Coordinator: NSObject {
        var parent: FullWidthSegmentedPicker

        init(_ parent: FullWidthSegmentedPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}
