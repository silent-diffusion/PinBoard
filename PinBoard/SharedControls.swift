//
//  SharedControls.swift  —  PinBoard
//
//  Small UI pieces every screen shares: the empty-state view, tag chips, the flow layout, the
//  text fields backed by UIKit (NativeTextField, NativeTextView, TextEditSheet) and the built-in
//  keyboard. Split out of ContentView.swift so each file stays a comfortable size to paste.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - Progress

/// How far a counted job has got, read from its own words: "Importing 3 of 40…", "Syncing with
/// iCloud… 2,100 of 2,500", "Converting 2 of 5 (45%)" (the percent is the current one's). nil:
/// the line has no count — a spinner shows instead. So every job that says how far it is also
/// draws a bar, wherever its line is shown.
enum WorkProgress {
    nonisolated static func fraction(of text: String) -> Double? {
        guard let of = text.range(of: " of ", options: .backwards) else { return nil }
        let separators: Set<Character> = [",", ".", " ", "\u{00A0}", "\u{202F}", "'"]
        let before = String(text[..<of.lowerBound].reversed().prefix { $0.isASCII && $0.isNumber || separators.contains($0) }.reversed())
        let after = String(text[of.upperBound...].prefix { $0.isASCII && $0.isNumber || separators.contains($0) })
        guard let done = Int(before.filter { $0.isASCII && $0.isNumber }),
              let total = Int(after.filter { $0.isASCII && $0.isNumber }), total > 0 else { return nil }
        // "Converting 2 of 5 (45%)": the second is 45% done, so 1.45 of 5.
        if let percentSign = text.range(of: "%)") {
            let digits = String(text[..<percentSign.lowerBound].reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
            if let percent = Int(digits) {
                return min(1, max(0, (Double(done - 1) + Double(min(percent, 100)) / 100) / Double(total)))
            }
        }
        return min(1, max(0, Double(done) / Double(total)))
    }
}

/// A job's line, with a bar under it when it has a count (`fraction`, or read from the words),
/// else a small spinner beside it. Used for long work in Settings and the Hidden section.
struct WorkProgressLine: View {
    let text: String
    var fraction: Double? = nil

    var body: some View {
        if let value = fraction ?? WorkProgress.fraction(of: text) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text).foregroundStyle(.secondary)
                ProgressView(value: value)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared small views

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 420)
        .padding()
        .frame(maxWidth: .infinity)
    }
}

enum TagChipStyle {
    case user, ai, text
}

struct TagChip: View {
    @Environment(\.pinAccent) private var accent
    var text: String
    var style: TagChipStyle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if style == .text {
                    Image(systemName: "text.quote").font(.caption2)
                }
                Text(text)
                    .lineLimit(1)
                Image(systemName: style == .user ? "xmark" : "plus")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(style == .user ? accent.opacity(0.14) : Color(uiColor: .secondarySystemBackground), in: Capsule())
            .foregroundStyle(style == .user ? accent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style == .user ? "Remove tag \(text)" : "Add tag \(text)")
        // A tag the pin has is "on" (tapping takes it off); a suggestion is "off" until added.
        .accessibilityAddTraits(style == .user ? .isSelected : [])
    }
}

/// Lays out chips left-to-right, wrapping onto new lines as needed. A chip
/// wider than the row is squeezed to the row's width instead of sticking out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        if natural.width > maxWidth, maxWidth.isFinite, maxWidth > 0 {
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        return natural
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        // Asked for its size with no width, or an endless one (a List row measuring itself can
        // do that): the natural width of its rows. Never an endless width, which would push the
        // row's other content out of sight.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? usedWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Text fields backed by UIKit
//
// These wrap the UIKit fields directly, so a field can be given focus the moment
// its sheet opens (the keyboard is up straight away), choose its Return key and
// clear button, and say exactly what VoiceOver reads.
//
// They always draw in the light or dark look SwiftUI has where they are
// (`overrideUserInterfaceStyle`), with the text in the system's label color:
// a UIKit view otherwise follows its window, so in a sheet over the dark
// Quick Look it drew black text on the dark list.

struct NativeTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var returnKey: UIReturnKeyType
    var autocapitalization: UITextAutocapitalizationType
    var autocorrection: Bool
    var autoFocus: Bool
    var font: UIFont
    var alignment: NSTextAlignment
    var secure: Bool
    var showsClearButton: Bool
    /// What VoiceOver calls the field (nil: its placeholder, which can be vague — "Optional").
    var accessibilityLabel: String?
    var onSubmit: () -> Void

    init(placeholder: String,
         text: Binding<String>,
         returnKey: UIReturnKeyType = .done,
         autocapitalization: UITextAutocapitalizationType = .sentences,
         autocorrection: Bool = true,
         autoFocus: Bool = false,
         font: UIFont = .preferredFont(forTextStyle: .body),
         alignment: NSTextAlignment = .natural,
         secure: Bool = false,
         showsClearButton: Bool = true,
         accessibilityLabel: String? = nil,
         onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self._text = text
        self.returnKey = returnKey
        self.autocapitalization = autocapitalization
        self.autocorrection = autocorrection
        self.autoFocus = autoFocus
        self.font = font
        self.alignment = alignment
        self.secure = secure
        self.showsClearButton = showsClearButton
        self.accessibilityLabel = accessibilityLabel
        self.onSubmit = onSubmit
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.returnKeyType = returnKey
        field.autocapitalizationType = autocapitalization
        field.autocorrectionType = autocorrection ? .default : .no
        field.font = font
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = alignment
        field.isSecureTextEntry = secure
        field.clearButtonMode = showsClearButton ? .whileEditing : .never
        field.textColor = .label
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let style = NativeTextField.interfaceStyle(for: context.environment.colorScheme)
        if field.overrideUserInterfaceStyle != style { field.overrideUserInterfaceStyle = style }
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        if let accessibilityLabel, field.accessibilityLabel != accessibilityLabel { field.accessibilityLabel = accessibilityLabel }
        if field.isSecureTextEntry != secure { field.isSecureTextEntry = secure }
        if autoFocus, !context.coordinator.didAutoFocus {
            context.coordinator.didAutoFocus = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)   // let the sheet finish appearing
                NativeTextField.focus(field)
            }
        }
    }

    /// UIKit's light or dark look for SwiftUI's color scheme where the field is.
    static func interfaceStyle(for scheme: ColorScheme) -> UIUserInterfaceStyle {
        scheme == .dark ? .dark : .light
    }

    /// Makes the field's window the key window first, then asks for focus.
    /// Without the key window, iPadOS never shows a keyboard or delivers keys.
    @MainActor
    static func focus(_ view: UIView) {
        if let window = view.window, !window.isKeyWindow {
            window.makeKey()
        }
        view.becomeFirstResponder()
    }

    /// Puts the keyboard away, whichever field has it.
    @MainActor
    static func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeTextField
        var didAutoFocus = false

        init(_ parent: NativeTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if let window = textField.window, !window.isKeyWindow {
                window.makeKey()
            }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}

/// Multi-line version (for notes).
struct NativeTextView: UIViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = .label
        view.delegate = context.coordinator
        view.isScrollEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let style = NativeTextField.interfaceStyle(for: context.environment.colorScheme)
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        if view.text != text { view.text = text }
        if autoFocus, !context.coordinator.didAutoFocus {
            context.coordinator.didAutoFocus = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                NativeTextField.focus(view)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeTextView
        var didAutoFocus = false

        init(_ parent: NativeTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }
    }
}

/// A small sheet for editing one piece of text (title, note, board name…).
/// Opens with the keyboard already up.
/// Once the text has been changed, a swipe down no longer closes the sheet (that would
/// throw the edit away); Cancel and Save stay the ways out.
struct TextEditSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let title: String
    let placeholder: String
    let multiline: Bool
    /// A name that must not be empty (a board, a profile): Save waits for some text.
    let requiresText: Bool
    let onSave: (String) -> Void
    /// The text the sheet opened with (to tell whether anything was changed).
    private let initial: String
    @State private var text: String

    init(title: String, placeholder: String, initial: String, multiline: Bool = false, requiresText: Bool = false,
         onSave: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.multiline = multiline
        self.requiresText = requiresText
        self.onSave = onSave
        self.initial = initial
        self._text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if multiline {
                    NativeTextView(text: $text, autoFocus: true)
                        .frame(minHeight: 120, maxHeight: 200)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    NativeTextField(placeholder: placeholder, text: $text, autoFocus: true) {
                        save()
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(requiresText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(text != initial)   // an edit is never lost to a swipe
    }

    /// Save, Return on the keyboard and the built-in keyboard's Done all end here. A name that
    /// must not be empty keeps the sheet open until something is typed (the Save button is
    /// dimmed meanwhile; Return and Done simply do nothing).
    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresText && trimmed.isEmpty { return }
        onSave(trimmed)
        dismiss()
    }
}
