import AppKit
import SwiftUI

/// The native text input inside a draft card. The parent owns the card and its actions.
struct TaskEditor: NSViewRepresentable {
    @Binding var name: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editor: self) }

    func makeNSView(context: Context) -> DraftTextField {
        let field = DraftTextField(frame: .zero)
        field.delegate = context.coordinator
        field.stringValue = name
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.appearance = NSAppearance(named: .aqua)
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.allowsEditingTextAttributes = false
        field.font = Self.cardFont
        field.textColor = NSColor(StackTheme.ink)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Task name")
        field.setAccessibilityHelp("Press Return to add the task. Press Escape to cancel.")
        return field
    }

    func updateNSView(_ field: DraftTextField, context: Context) {
        context.coordinator.editor = self
        // While editing, AppKit's field editor owns the text and marked IME range.
        if field.currentEditor() == nil, field.stringValue != name {
            field.stringValue = name
        }
    }

    private static var cardFont: NSFont {
        let system = NSFont.systemFont(ofSize: 12, weight: .medium)
        guard let rounded = system.fontDescriptor.withDesign(.rounded) else { return system }
        return NSFont(descriptor: rounded, size: 12) ?? system
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var editor: TaskEditor

        init(editor: TaskEditor) {
            self.editor = editor
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let textView = field.currentEditor() as? NSTextView {
                guard !textView.hasMarkedText() else { return }
                editor.name = textView.string
            } else {
                editor.name = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Let the input method accept or dismiss its composition first.
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                editor.name = textView.string
                editor.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                editor.onCancel()
                return true
            default:
                return false
            }
        }
    }

    final class DraftTextField: NSTextField {
        private var tookInitialFocus = false

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tookInitialFocus = false
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            scheduleInitialFocus()
        }

        @objc private func windowBecameKey(_ notification: Notification) {
            scheduleInitialFocus()
        }

        private func scheduleInitialFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.tookInitialFocus, let window = self.window, window.isKeyWindow else { return }
                if self.currentEditor() != nil {
                    self.tookInitialFocus = true
                } else if window.makeFirstResponder(self) {
                    self.tookInitialFocus = true
                    self.selectText(nil)
                }
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func menu(for event: NSEvent) -> NSMenu? { nil }
        override func rightMouseDown(with event: NSEvent) {}
    }
}
