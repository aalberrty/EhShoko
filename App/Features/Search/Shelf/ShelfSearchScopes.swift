import EhFeatures
import SwiftUI
import UIKit

/// The scopes, Everywhere, Favourites and Watched, as the system's segmented control in the
/// top bar (`shelf.md` section 6; the glass map's "controls pinned above scrolling content").
///
/// Signed out, Favourites and Watched are dimmed, and a tap on one says why (`refused`)
/// instead of choosing it.
struct ShelfSearchScopes: View {
    let model: SearchSurfaceModel
    let refused: () -> Void

    @Environment(AccountSession.self) private var account

    var body: some View {
        // The model decides from the cookies, which nothing observes; reading the session
        // redraws the dimming when someone signs in or out while the surface is up.
        let _ = account.isLoggedIn
        ShelfSearchScopeControl(
            scopes: SearchScope.allCases.map { scope in
                ShelfSearchScopeControl.Segment(
                    scope: scope, title: scope.localizedName, isAvailable: model.isAvailable(scope)
                )
            },
            selection: model.scope,
            select: { model.scope = $0 },
            refused: refused
        )
    }
}

/// A `UISegmentedControl`, rather than a segmented `Picker`, because a dimmed segment must
/// still answer a tap: a disabled segment takes none, so a tap recogniser on the control
/// finds which segment was under the finger and reports the dimmed ones.
///
/// It is as wide as the bar offers, up to 420 pt, and never narrower than its titles.
struct ShelfSearchScopeControl: UIViewRepresentable {
    struct Segment: Equatable {
        let scope: SearchScope
        let title: String
        let isAvailable: Bool
    }

    let scopes: [Segment]
    let selection: SearchScope
    let select: (SearchScope) -> Void
    let refused: () -> Void

    private static let maximumWidth: CGFloat = 420

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        // The control keeps its own touches; the recogniser only looks at where they land.
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        control.addGestureRecognizer(tap)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.segments != scopes {
            coordinator.segments = scopes
            control.removeAllSegments()
            for (index, segment) in scopes.enumerated() {
                control.insertSegment(withTitle: segment.title, at: index, animated: false)
                control.setEnabled(segment.isAvailable, forSegmentAt: index)
            }
        }
        let index = scopes.firstIndex { $0.scope == selection } ?? UISegmentedControl.noSegment
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView control: UISegmentedControl, context: Context) -> CGSize? {
        let fitting = control.intrinsicContentSize
        let offered = proposal.width ?? fitting.width
        return CGSize(width: max(fitting.width, min(offered, Self.maximumWidth)), height: fitting.height)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ShelfSearchScopeControl?
        var segments: [Segment] = []

        @objc func valueChanged(_ control: UISegmentedControl) {
            guard segments.indices.contains(control.selectedSegmentIndex) else { return }
            parent?.select(segments[control.selectedSegmentIndex].scope)
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let control = recognizer.view as? UISegmentedControl, !segments.isEmpty,
                  control.bounds.width > 0 else { return }
            // Segments share the width equally (the control does not size them by content).
            var index = Int(recognizer.location(in: control).x / (control.bounds.width / CGFloat(segments.count)))
            if control.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                index = segments.count - 1 - index
            }
            guard segments.indices.contains(index), !segments[index].isAvailable else { return }
            parent?.refused()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
