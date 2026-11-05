//
//  PinPageLink.swift  —  PinBoard
//
//  The "Link" section of a pin's page, written as part of `PinDetailView`: where a
//  picture, video or text pin came from, with "Add link", "Edit link" and "Remove link"
//  right there. They are the ⋯ menu's "Add link…" / "Edit link…" (the address sheet,
//  SourceLinks.swift) and the store's `setSourceLink`, so the page and the menu always
//  behave the same. (A link pin's own address has its own panel and pencil, under the title.)
//

import SwiftUI
import UIKit
import Foundation

extension PinDetailView {
    /// The "Link" section. A stored picture, video or text pin always has it: "No link yet." with
    /// "Add link", or its link with a pencil (Edit link) and a remove button. A web result that isn't
    /// saved yet only shows where it came from (it has no link of its own to change yet), and a link
    /// pin shows nothing here.
    @ViewBuilder
    func sourceSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        let editable = PinPageSourceRows.offersEditLink(kind: pin.kind, isDraft: isDraft)
        let address = (pin.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !pin.isLink, editable || !address.isEmpty {
            sectionHeader("Link", icon: "link")
            if address.isEmpty {
                noLinkRow(pin)
            } else {
                linkRow(pin, address: address, editable: editable)
            }
        }
    }

    /// "No link yet." and the "Add link" button (the ⋯ menu's "Add link…").
    private func noLinkRow(_ pin: Pin) -> some View {
        HStack {
            Text("No link yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                pinActions.perform(.addLink, on: [pin.id], side: pageScope, place: .pinPage)
            } label: {
                Label("Add link", systemImage: "link.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// The link: its credit or "Open source page" (opens the page), the address under it, then the
    /// pencil and the remove button. The row is at least 44 pt tall, so it is easy to hit.
    private func linkRow(_ pin: Pin, address: String, editable: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "safari")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // only decoration: the link says it
            VStack(alignment: .leading, spacing: 2) {
                linkTitle(pin, address: address)
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 44, alignment: .leading)
            Spacer(minLength: 0)
            if editable {
                roundButton("pencil", label: "Edit link") {
                    pinActions.perform(.editLink, on: [pin.id], side: pageScope, place: .pinPage)
                }
                removeLinkButton(pin)
            }
        }
    }

    /// The credit ("Photo by Name · Unsplash") or "Open source page", opening the page. An address
    /// that isn't a web address (one from long ago) is only shown, not opened.
    @ViewBuilder
    private func linkTitle(_ pin: Pin, address: String) -> some View {
        let name = pin.credit ?? "Open source page"
        if let url = PinActionRules.webAddress(in: address) {
            Link(destination: url) {
                Text(name)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
            }
        } else {
            Text(name)
                .font(.subheadline)
        }
    }

    /// Takes the link away — after a second tap on "Remove link" in its small menu, so a slip of the
    /// finger never removes it. The pin stays; only its address goes. It is the address sheet's
    /// "Remove link": the same store call and the same short message ("Link removed.").
    private func removeLinkButton(_ pin: Pin) -> some View {
        let id = pin.id
        return Menu {
            Button("Remove link", systemImage: "trash", role: .destructive) {
                removeSourceLink(of: id)
            }
        } label: {
            roundButtonLook {
                Image(systemName: "xmark")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove link")
    }

    /// Like the presenter's save of the address sheet with an empty field (PinActionsPresenter.swift).
    private func removeSourceLink(of id: UUID) {
        guard let pin = store.livePin(id) else { return }
        let hadLink = PinActionRules.hasLink(pin)
        let changed = store.setSourceLink(of: id, to: "")
        let outcome = SourceLinkOutcome.of(hadLink: hadLink, typed: "", changed: changed)
        importFlow.flash(outcome.text, symbol: outcome.symbol)
    }
}
