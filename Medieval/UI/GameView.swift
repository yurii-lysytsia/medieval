import MedievalDomain
import SpriteKit
import SwiftUI

struct GameView: NSViewRepresentable {
    let state: GameState
    let onAction: (GameAction) -> Void

    func makeNSView(context: Context) -> SKView {
        let view = SKView()
        let scene = GameScene(size: CGSize(width: 960, height: 640))
        scene.onAction = onAction
        scene.render(state)
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        guard let scene = view.scene as? GameScene else { return }
        scene.onAction = onAction
        scene.render(state)
    }
}
