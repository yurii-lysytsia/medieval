import MedievalDomain
import SpriteKit
import SwiftUI

struct GameView: NSViewRepresentable {
    let state: GameState
    let onEndTurn: () -> Void

    func makeNSView(context _: Context) -> SKView {
        let view = SKView()
        let scene = GameScene(size: CGSize(width: 960, height: 640))
        scene.onEndTurn = onEndTurn
        scene.render(state)
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context _: Context) {
        guard let scene = view.scene as? GameScene else { return }
        scene.onEndTurn = onEndTurn
        scene.render(state)
    }
}
