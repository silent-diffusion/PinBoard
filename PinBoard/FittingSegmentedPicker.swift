//
//  FittingSegmentedPicker.swift  —  PinBoard
//
//  A segmented switch (the system's own control, so it looks like every other one) whose labels
//  are never cut short with "…". SwiftUI's segmented Picker gives every segment the same width,
//  so one long label ("Unsorted (12)") is cut while its neighbours have room to spare, and its
//  words can't be made smaller. This one tries, in turn, until one fits the width it is given:
//    1. the segments at the system's usual size (footnote, 13 pt at the default text size), sized
//       by their words when equal widths don't fit;
//    2. the same a step smaller: caption (12 pt), then caption 2 (11 pt);
//    3. with a larger text size that is not one of the accessibility sizes: 11 pt whatever the text
//       size (the system's own segmented control never grows with the text size either);
//    4. only at the accessibility text sizes, when nothing above fits: one full-width menu button
//       showing the chosen section, with all of them in its menu, same words.
//  Steps 1 and 2 follow the person's text size (Dynamic Type).
//

import SwiftUI
import UIKit

/// One segment: its value and its words.
struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

struct FittingSegmentedPicker<Value: Hashable>: View {
    /// What the switch is for, for VoiceOver ("Section", "Filter").
    let title: String
    @Binding var selection: Value
    let options: [SegmentOption<Value>]

    /// The sizes tried, largest first (the words never get smaller than caption 2).
    private static var styles: [UIFont.TextStyle] { [.footnote, .caption1, .caption2] }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(FittingSegmentedPicker.styles, id: \.self) { (style: UIFont.TextStyle) in
                SegmentedControlView(selection: $selection,
                                     options: options,
                                     font: font(style),
                                     title: title)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                SegmentedControlView(selection: $selection,
                                     options: options,
                                     font: UIFont.systemFont(ofSize: 11, weight: .medium),
                                     title: title)
            }
            menu
        }
    }

    private func font(_ style: UIFont.TextStyle) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        return UIFont.systemFont(ofSize: base.pointSize, weight: .medium)
    }

    /// The last resort: the chosen section's name with a chevron, the others in a menu.
    private var menu: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { (option: SegmentOption<Value>) in
                    Text(option.label).tag(option.value)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first(where: { $0.value == selection })?.label ?? "")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(title)
        .accessibilityValue(options.first(where: { $0.value == selection })?.label ?? "")
    }
}

/// The system segmented control with one font. Asked for its ideal width (by `ViewThatFits`) it
/// answers the least it needs: each segment as wide as its own words. Given a width, it fills it —
/// with equal segments when they fit, otherwise each sized by its words.
private struct SegmentedControlView<Value: Hashable>: UIViewRepresentable {
    @Binding var selection: Value
    let options: [SegmentOption<Value>]
    let font: UIFont
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = options.map { $0.value }
        if control.numberOfSegments != options.count {
            control.removeAllSegments()
            for (index, option) in options.enumerated() {
                control.insertSegment(withTitle: option.label, at: index, animated: false)
            }
        } else {
            for (index, option) in options.enumerated() where control.titleForSegment(at: index) != option.label {
                control.setTitle(option.label, forSegmentAt: index)
            }
        }
        control.setTitleTextAttributes([.font: font], for: .normal)
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)], for: .selected)
        control.selectedSegmentIndex = options.firstIndex(where: { $0.value == selection }) ?? UISegmentedControl.noSegment
        control.accessibilityLabel = title
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView control: UISegmentedControl, context: Context) -> CGSize? {
        control.apportionsSegmentWidthsByContent = true
        let least = control.intrinsicContentSize
        guard let width = proposal.width, width.isFinite else { return least }
        // Equal segments when they fit (the usual look), otherwise by their words.
        control.apportionsSegmentWidthsByContent = false
        let equal = control.intrinsicContentSize.width
        control.apportionsSegmentWidthsByContent = equal > width
        return CGSize(width: max(width, least.width), height: least.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value] = []

        init(selection: Binding<Value>) {
            self.selection = selection
        }

        @objc func changed(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            guard values.indices.contains(index) else { return }
            selection.wrappedValue = values[index]
        }
    }
}
