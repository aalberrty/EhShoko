import SwiftUI
import UIKit

/// The playing canvas in a hosting controller of its own, so a frame of the stage updates
/// that small view graph and its one layer, not the screen around it.
///
/// Inside the screen's own graph, every frame's new drawing was combined up through each of
/// the stage's ancestors to the root of the sheet and committed with it, which was most of
/// the main thread's time per frame. The host takes no touches: the stage's gestures,
/// accessibility and visibility tracking stay on the SwiftUI view around it.
struct StageHost: UIViewControllerRepresentable {
    let playback: StagePlayback
    let palettes: StagePalettes

    func makeUIViewController(context: Context) -> UIHostingController<StageCanvas> {
        let controller = UIHostingController(rootView: StageCanvas(playback: playback, palettes: palettes))
        controller.sizingOptions = []
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityElementsHidden = true
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<StageCanvas>, context: Context) {
        let canvas = StageCanvas(playback: playback, palettes: palettes)
        if controller.rootView != canvas {
            controller.rootView = canvas
        }
    }
}
