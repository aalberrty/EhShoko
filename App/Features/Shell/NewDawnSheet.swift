import EhFeatures
import EhModels
import SwiftUI

/// The daily "New Dawn" reward (legacy `NewDawnView`): the sun (with rays in light mode) in the
/// top-trailing corner, two title lines and the rewards.
///
/// A sheet below full height on the look's tokens (`Design/designs/README.md` section 13): the
/// system's sheet is the ground, so its glass shows on iOS 26, where legacy filled it with a sky
/// gradient. The sun takes the look's rating colour, the text its label colours and its title
/// face. The text scrolls when it does not fit, at large text sizes.
struct NewDawnSheet: View {
    let greeting: Greeting

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.look) private var look
    @State private var width: CGFloat = 0

    /// Centred on the sheet's top-trailing corner, so a quarter of it shows. Legacy sized the
    /// sun from the window width; this uses the sheet's own width.
    private var sunWidth: CGFloat { width * 0.4 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Rays are a shape, not a colour: legacy drew them only in the light appearance.
            Sun(width: sunWidth, color: look.rating, showsRays: colorScheme == .light)
                .offset(x: sunWidth / 2, y: -sunWidth / 2)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    line(L10n.Localizable.NewDawnView.Title.first, font: .largeTitle, color: look.label)
                    line(L10n.Localizable.NewDawnView.Title.second, font: .title2, color: look.secondaryLabel)
                    line(greeting.gainContent ?? "", font: .title3, color: look.label)
                        .padding(.top, 40)
                }
                .padding(.horizontal, Tokens.Spacing.xLarge)
                // Below the sun and the tips of its rays.
                .padding(.top, sunWidth * 0.8)
                .padding(.bottom, Tokens.Spacing.xLarge)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func line(_ text: String, font: Font, color: Color) -> some View {
        Text(text)
            .font(font)
            .fontWeight(.bold)
            .fontDesign(look.titleDesign)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Sun: View {
    let width: CGFloat
    let color: Color
    let showsRays: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: width, height: width)
            if showsRays {
                ForEach(0..<8, id: \.self) { index in
                    ray(at: Double(index) * 45)
                }
            }
        }
    }

    /// One of eight rays around the sun, `degrees` clockwise from the top.
    private func ray(at degrees: Double) -> some View {
        let beam = width / 10
        let distance = width / 1.2
        let radians = degrees * .pi / 180
        return RoundedRectangle(cornerRadius: beam / 3)
            .fill(color)
            .frame(width: beam, height: beam * 5)
            .rotationEffect(.degrees(degrees))
            .offset(x: distance * sin(radians), y: -distance * cos(radians))
    }
}

// MARK: Presentation

extension View {
    /// Presents `router.presentedGreeting` as the New Dawn sheet with a light haptic, at the
    /// medium height; it can be pulled up when large text does not fit.
    ///
    /// Only one view can present a sheet at a time, so the shell attaches this to the tabs and
    /// to the gallery sheet and marks the one on top with `isTopmost`.
    func newDawnSheet(router: AppRouter, isTopmost: Bool) -> some View {
        modifier(NewDawnPresenter(router: router, isTopmost: isTopmost))
    }
}

private struct NewDawnPresenter: ViewModifier {
    let router: AppRouter
    let isTopmost: Bool

    func body(content: Content) -> some View {
        content
            .sheet(item: greeting) { greeting in
                NewDawnSheet(greeting: greeting)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isTopmost ? router.presentedGreeting : nil) { _, new in
                new != nil
            }
    }

    private var greeting: Binding<Greeting?> {
        Binding(
            get: { isTopmost ? router.presentedGreeting : nil },
            set: { if $0 == nil, isTopmost { router.presentedGreeting = nil } }
        )
    }
}

#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            NewDawnSheet(greeting: .mock)
        }
}
