import MedievalDomain
import SpriteKit
import SwiftUI

struct GameView: NSViewRepresentable {
    let state: GameState
    let map: StaticHexMap
    let world: WorldState
    let selectedHexID: HexID?
    let cameraResetToken: Int
    let onSelectHex: (HexID) -> Void

    func makeNSView(context _: Context) -> SKView {
        let view = SKView()
        let scene = GameScene(size: CGSize(width: 960, height: 640))
        scene.onSelectHex = onSelectHex
        scene.render(state, map: map, world: world, selectedHexID: selectedHexID, cameraResetToken: cameraResetToken)
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context _: Context) {
        guard let scene = view.scene as? GameScene else { return }
        scene.onSelectHex = onSelectHex
        scene.render(state, map: map, world: world, selectedHexID: selectedHexID, cameraResetToken: cameraResetToken)
    }
}
