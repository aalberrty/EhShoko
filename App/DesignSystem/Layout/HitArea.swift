import SwiftUI

// A small inline button ("All 48", "Sort", "Try again", "Vote") is drawn as a line of text,
// 15 to 18 pt high, but its target should be 44 pt (Human Interface Guidelines). The label is
// padded inside the button, which makes the button and its accessibility frame that tall, and
// the padding is taken back outside it, so that nothing around the button moves.
//
//     Button(action: action) { Text(title).hitAreaOutset() }
//         .hitAreaOutsetReturned()

nonisolated enum HitArea {
    /// Around a line of footnote to subheadline text: 15 + 2 × 15 = 45 pt.
    static let inlineText = EdgeInsets(top: 15, leading: 0, bottom: 15, trailing: 0)
    /// Around a short word ("Vote"), which is also narrower than 44 pt.
    static let shortWord = EdgeInsets(top: 15, leading: 8, bottom: 15, trailing: 8)
}

extension View {
    /// In a small button's label: the label, and so the button, reaches `outset` further on
    /// each side, all of it a target.
    func hitAreaOutset(_ outset: EdgeInsets = HitArea.inlineText) -> some View {
        padding(outset).contentShape(.rect)
    }

    /// On the button whose label has `hitAreaOutset`: the same outset taken back out of the
    /// layout.
    func hitAreaOutsetReturned(_ outset: EdgeInsets = HitArea.inlineText) -> some View {
        padding(EdgeInsets(top: -outset.top, leading: -outset.leading, bottom: -outset.bottom, trailing: -outset.trailing))
    }
}
