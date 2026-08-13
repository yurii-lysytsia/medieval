import SpriteKit
import SwiftUI

/// SpriteKit forwards mouse clicks to its scene, but keeps scrolling and
/// magnification events on `SKView`. Forward those events explicitly so the
/// strategic-map camera receives mouse-wheel and trackpad input.
private final class InteractiveMapView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard let scene = scene as? GameScene else {
            super.scrollWheel(with: event)
            return
        }
        scene.handleScrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard let scene = scene as? GameScene else {
            super.magnify(with: event)
            return
        }
        scene.handleMagnify(with: event)
    }
}

struct GameView: NSViewRepresentable {
    let state: GameState
    let map: StaticHexMap
    let world: WorldState
    let selectedHexID: HexID?
    let reachableHexIDs: Set<HexID>
    let encounterHexIDs: Set<HexID>
    let previewRoute: MovementRoute?
    let cameraResetToken: Int
    let onSelectHex: (HexID) -> Void

    func makeNSView(context _: Context) -> SKView {
        let view = InteractiveMapView()
        let scene = GameScene(size: CGSize(width: 960, height: 640))
        scene.onSelectHex = onSelectHex
        scene.render(state, map: map, world: world, selectedHexID: selectedHexID, reachableHexIDs: reachableHexIDs, encounterHexIDs: encounterHexIDs, previewRoute: previewRoute, cameraResetToken: cameraResetToken)
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context _: Context) {
        guard let scene = view.scene as? GameScene else { return }
        scene.onSelectHex = onSelectHex
        scene.render(state, map: map, world: world, selectedHexID: selectedHexID, reachableHexIDs: reachableHexIDs, encounterHexIDs: encounterHexIDs, previewRoute: previewRoute, cameraResetToken: cameraResetToken)
    }
}
