//
//  AppIconPicker.swift  —  PinBoard
//
//  Settings › Appearance › App icon: the icons PinBoard can have on the Home Screen, and the row
//  of small previews to pick one. Each icon has a light, a dark and a tinted look; iOS shows the
//  one that matches the Home Screen by itself.
//
//  The icon belongs to the device, not to a profile: iOS keeps the choice itself (there is
//  nothing to save in AppSettings), so it stays the same whichever profile is open, and iCloud
//  never carries it to the user's other devices.
//
//  The icons are drawn by AppStore/icon/options.swift, which also puts them in the Xcode build
//  (Xcode/App/AppIcon*.icon) with a small preview of each in Assets.xcassets
//  (IconPreview-<Name>). make-project.py lists the same names. A build without them (Swift
//  Playgrounds) shows a line saying the icon can't be changed there.
//

import SwiftUI
import UIKit

/// One of PinBoard's Home Screen icons, in the order the picker shows them: the default first.
enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case moodBoard = "MoodBoard"
    case fourKinds = "FourKinds"
    case pinnedPhoto = "PinnedPhoto"
    case pushPin = "PushPin"
    case foldedNote = "FoldedNote"
    case cardStack = "CardStack"
    case pinP = "PinP"
    case tapedSnapshot = "TapedSnapshot"

    nonisolated var id: String { rawValue }

    /// iOS's name for the icon, as the build lists it; nil is the main icon.
    nonisolated var iconName: String? {
        self == .moodBoard ? nil : "AppIcon-" + rawValue
    }

    /// The small picture of it in the asset catalog (with a dark version).
    nonisolated var previewName: String { "IconPreview-" + rawValue }

    nonisolated var title: String {
        switch self {
        case .moodBoard: return "Mood board"
        case .fourKinds: return "Four kinds"
        case .pinnedPhoto: return "Pinned photo"
        case .pushPin: return "Push-pin"
        case .foldedNote: return "Folded note"
        case .cardStack: return "Card stack"
        case .pinP: return "Pin P"
        case .tapedSnapshot: return "Snapshot"
        }
    }

    /// The choice for the icon iOS says is in use (an unknown name counts as the main icon).
    nonisolated static func choice(forIconName name: String?) -> AppIconChoice {
        guard let name else { return .moodBoard }
        return allCases.first { (choice: AppIconChoice) -> Bool in choice.iconName == name } ?? .moodBoard
    }
}

/// What this copy of the app can do about its icon.
@MainActor
enum AppIconSwitcher {
    /// True when the build carries the other icons (the Xcode build does, a Swift Playgrounds
    /// build doesn't) and iOS lets apps change their icon.
    static var canChange: Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let others = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return !(others?.isEmpty ?? true)
    }

    /// The icon on the Home Screen now.
    static var current: AppIconChoice {
        AppIconChoice.choice(forIconName: UIApplication.shared.alternateIconName)
    }

    /// Changes the icon. iOS then tells the person itself, with a small alert.
    static func use(_ choice: AppIconChoice) async throws {
        try await UIApplication.shared.setAlternateIconName(choice.iconName)
    }
}

/// The App icon row: a scrolling line of the icons, the one in use ringed in the accent colour.
struct AppIconRow: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var current: AppIconChoice = AppIconSwitcher.current
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingsCatalog.title(.appIcon))
            if AppIconSwitcher.canChange {
                icons
            } else {
                Text("This copy of PinBoard has only its main icon. The App Store version lets you choose another.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var icons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(AppIconChoice.allCases) { (choice: AppIconChoice) in
                    tile(choice)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    /// One icon: its preview with iOS's rounded corners, and its name underneath.
    private func tile(_ choice: AppIconChoice) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let chosen = choice == current
        return Button {
            choose(choice)
        } label: {
            VStack(spacing: 6) {
                Image(choice.previewName)
                    .resizable()
                    .frame(width: 62, height: 62)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(chosen ? settings.accentColor : Color.clear, lineWidth: 2.5))
                Text(choice.title)
                    .font(.caption2)
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != current else { return }
        problem = nil
        Task { @MainActor in
            do {
                try await AppIconSwitcher.use(choice)
                current = choice
            } catch {
                problem = "The icon couldn't be changed: \(error.localizedDescription)"
            }
        }
    }
}
