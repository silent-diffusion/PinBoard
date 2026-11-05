//
//  MediaPager.swift  —  PinBoard
//
//  The windowed pager shared by the pin page (sideways) and Quick Look
//  (up and down): a UIPageViewController that keeps only a few pages alive,
//  and the picture page it shows for stored pins.
//

import SwiftUI
import UIKit
import Foundation


// MARK: - The pager (pin page and Quick Look)

/// One persistent pager over a whole list. Page `i` always shows item `i`, so a
/// long swipe can never skip or land on the wrong item, and nothing is rebuilt
/// while a swipe is in progress. Built on UIPageViewController, which creates
/// pages lazily (the one in front and its neighbours) and pages natively —
/// sideways (the pin page) or up and down (Quick Look's feed).
struct MediaPager<Page: View>: UIViewControllerRepresentable {
    let count: Int
    @Binding var index: Int
    var spacing: CGFloat = 0
    var orientation: UIPageViewController.NavigationOrientation = .horizontal
    /// The pages don't move under a finger while this is true (Quick Look, while a finger holds
    /// on a video to play it at 2× — dragging down then locks the speed and must not page).
    var isPagingLocked = false
    /// What is at a position — so a page keeps its own state (loaded picture,
    /// zoom) only for as long as the same item is at that position.
    let pageID: (Int) -> AnyHashable
    @ViewBuilder let page: (Int) -> Page

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow
    @Environment(\.pinAccent) private var accent

    private var clampedIndex: Int { min(max(index, 0), max(count - 1, 0)) }

    /// A page with the app's environment, which UIKit-hosted views do not inherit.
    /// Pages fill their box edge to edge (a hosted view would otherwise inset its
    /// content whenever the box scrolls under the navigation bar).
    fileprivate func wrapped(_ i: Int) -> AnyView {
        AnyView(page(i)
            .id(pageID(i))
            .ignoresSafeArea()
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(importFlow)
            .environment(\.pinAccent, accent)
            .tint(accent))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: orientation,
                                              options: spacing > 0 ? [.interPageSpacing: spacing] : nil)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        if count > 0 {
            controller.setViewControllers([context.coordinator.host(for: clampedIndex)], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        // How the list changed is judged against what the live pages show now, before they are refreshed.
        coordinator.noteCount(count, pageID: pageID, controller: controller)
        coordinator.parent = self
        coordinator.setPagingLocked(isPagingLocked, in: controller)
        // Every live page depends on the current index (what to load, whether it plays).
        for (i, host) in coordinator.hosts where i < count {
            host.pageKey = pageID(i)
            host.rootView = wrapped(i)
        }
        guard count > 0 else { return }
        coordinator.syncIfNeeded(controller)
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MediaPager
        var hosts: [Int: PageHost] = [:]
        private var isTransitioning = false      // a swipe is in progress
        private var isMoving = false             // a move started by code is animating
        private var lastCount: Int
        /// The list changed under the pages (a deletion): the controller needs a fresh start.
        private var needsReset = false
        /// Items were only added at the end while this page was the last one: the
        /// controller must be asked again for the page after it (it remembers "none").
        private var refreshAfterPage: Int? = nil

        init(_ parent: MediaPager) {
            self.parent = parent
            lastCount = parent.count
        }

        func host(for i: Int) -> PageHost {
            if let existing = hosts[i] {
                existing.pageKey = parent.pageID(i)
                existing.rootView = parent.wrapped(i)
                return existing
            }
            let host = PageHost(rootView: parent.wrapped(i))
            host.pageIndex = i
            host.pageKey = parent.pageID(i)
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            host.view.backgroundColor = .clear
            hosts[i] = host
            return host
        }

        /// Switches the pager's own scrolling off and on. (A UIPageViewController has one scroll view
        /// inside; its gestures are what page.)
        func setPagingLocked(_ locked: Bool, in controller: UIPageViewController) {
            for case let scroll as UIScrollView in controller.view.subviews {
                if scroll.isScrollEnabled == locked { scroll.isScrollEnabled = !locked }
            }
        }

        func shownIndex(in controller: UIPageViewController) -> Int? {
            (controller.viewControllers?.first as? PageHost)?.pageIndex
        }

        /// Records a change in the number of items. Growth at the end (every live
        /// page still shows the same item) keeps the page in front exactly as it is;
        /// anything else (a deletion) resets the controller at the current position.
        func noteCount(_ count: Int, pageID: (Int) -> AnyHashable, controller: UIPageViewController) {
            guard count != lastCount else { return }
            let old = lastCount
            lastCount = count
            let appendedOnly = count > old && hosts.allSatisfy { i, host in i >= old || host.pageKey == pageID(i) }
            if !appendedOnly {
                needsReset = true
                refreshAfterPage = nil
            } else if old > 0 {
                // Only the page that was last has a stale "nothing after me"; a swipe
                // in progress asks again by itself when it lands.
                refreshAfterPage = old - 1
            }
        }

        /// Brings the controller to the index the binding asks for — never while a
        /// swipe or an earlier move is still animating (overlapping transitions
        /// break UIPageViewController); it is tried again when that finishes.
        func syncIfNeeded(_ controller: UIPageViewController) {
            let count = parent.count
            guard count > 0, !isTransitioning, !isMoving else { return }
            let target = min(max(parent.index, 0), count - 1)
            if needsReset || shownIndex(in: controller) == nil {
                // The list changed (a deletion): hand the controller the current page again so
                // the neighbours it cached are fetched again.
                needsReset = false
                refreshAfterPage = nil
                hosts = hosts.filter { $0.key < count }
                controller.setViewControllers([host(for: target)], direction: .forward, animated: false)
                trimHosts(around: target)
            } else if let shown = shownIndex(in: controller), shown != target {
                // Moved by code (arrow keys, a deleted page): page there, one move at a time.
                refreshAfterPage = nil          // landing asks for the new neighbours anyway
                isMoving = true
                controller.setViewControllers([host(for: target)], direction: target > shown ? .forward : .reverse, animated: true) { [weak self, weak controller] _ in
                    guard let self else { return }
                    self.isMoving = false
                    self.trimHosts(around: target)
                    if let controller { self.syncIfNeeded(controller) }   // the binding may have moved on meanwhile
                }
            } else if let stale = refreshAfterPage {
                // More items arrived while the last page was in front: the same page (same
                // host, nothing reloads) is handed over again so "what comes next" is asked anew.
                refreshAfterPage = nil
                if let shown = shownIndex(in: controller), shown == stale, let current = hosts[shown] {
                    controller.setViewControllers([current], direction: .forward, animated: false)
                }
            }
        }

        private func trimHosts(around i: Int) {
            // Pages far from here can go; the ones nearby stay ready for a swipe back.
            hosts = hosts.filter { abs($0.key - i) <= 3 }
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let i = (viewController as? PageHost)?.pageIndex, i > 0, i - 1 < parent.count else { return nil }
            return host(for: i - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let i = (viewController as? PageHost)?.pageIndex, i + 1 < parent.count else { return nil }
            return host(for: i + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            guard let i = shownIndex(in: pageViewController) else { return }
            if completed, parent.index != i { parent.index = i }
            trimHosts(around: i)
            syncIfNeeded(pageViewController)   // anything that had to wait (a deletion, a key press, new items)
        }
    }
}

/// A page of the pager: a hosted SwiftUI view that knows its position and
/// which item it was last given.
final class PageHost: UIHostingController<AnyView> {
    var pageIndex = 0
    var pageKey: AnyHashable? = nil
}

/// How much of an item a page loads, by its distance from the page in front.
enum PageQuality: Equatable {
    case full, thumbnail, placeholder

    init(distance: Int) {
        if distance <= 1 { self = .full } else if distance == 2 { self = .thumbnail } else { self = .placeholder }
    }
}

/// A stored picture (or a video's poster, or a link's preview) in the pager. It loads again when
/// the picture file is rewritten (turned, flipped, cropped: `Pin.pictureRevision` goes up).
struct StoredImagePage: View {
    @EnvironmentObject private var store: LibraryStore
    let pin: Pin
    var quality: PageQuality = .full
    @State private var image: UIImage? = nil

    var body: some View {
        let shown = image ?? (quality == .placeholder ? nil : (store.cachedFullImage(for: pin) ?? store.cachedThumbnail(for: pin)))
        Color(uiColor: .secondarySystemFill)
            .overlay {
                if let shown {
                    Image(uiImage: shown).resizable().scaledToFit()
                } else if quality != .placeholder {
                    ProgressView()
                }
            }
            .overlay(alignment: .center) {
                if pin.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            }
            .clipped()
            .task(id: "\(pin.id)|\(quality)|\(pin.pictureRevision)|\(pin.updatedAt.timeIntervalSince1970)") {
                switch quality {
                case .full:
                    // (a full picture that couldn't come from iCloud leaves the thumbnail on screen)
                    if let full = await store.fullImage(for: pin) {
                        image = full
                    } else {
                        image = await store.thumbnail(for: pin)
                    }
                case .thumbnail:
                    image = await store.thumbnail(for: pin)
                case .placeholder:
                    image = nil
                }
            }
    }
}
