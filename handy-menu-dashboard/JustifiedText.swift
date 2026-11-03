import AppKit
import SwiftUI

struct JustifiedText: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    init(_ text: String, font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) {
        self.text = text
        self.font = font
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.alignment = .justified
        field.isSelectable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        field.font = font
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, let cell = nsView.cell else { return nil }
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        return CGSize(width: width, height: ceil(cell.cellSize(forBounds: bounds).height))
    }
}
