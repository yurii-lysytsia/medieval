import MedievalDomain
import SpriteKit

final class GameScene: SKScene {
    var onEndTurn: (() -> Void)?

    private let titleLabel = SKLabelNode(fontNamed: "Palatino-Bold")
    private let turnLabel = SKLabelNode(fontNamed: "SF Pro Rounded")

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .init(red: 0.07, green: 0.12, blue: 0.10, alpha: 1)

        titleLabel.fontSize = 38
        titleLabel.fontColor = .init(red: 0.94, green: 0.78, blue: 0.42, alpha: 1)
        titleLabel.verticalAlignmentMode = .center
        addChild(titleLabel)

        turnLabel.fontSize = 18
        turnLabel.fontColor = .init(white: 0.85, alpha: 1)
        turnLabel.verticalAlignmentMode = .center
        addChild(turnLabel)

        drawBoard()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 76)
        turnLabel.position = CGPoint(x: size.width / 2, y: size.height - 118)
    }

    func render(_ state: GameState) {
        titleLabel.text = "MEDIEVAL"
        turnLabel.text = "Хід \(state.turn) · \(state.activePlayer.displayName)"
    }

    override func mouseUp(with event: NSEvent) {
        onEndTurn?()
    }

    private func drawBoard() {
        let board = SKShapeNode(rect: CGRect(x: 80, y: 80, width: 800, height: 480), cornerRadius: 20)
        board.strokeColor = .init(red: 0.55, green: 0.38, blue: 0.18, alpha: 1)
        board.fillColor = .init(red: 0.13, green: 0.21, blue: 0.16, alpha: 1)
        board.lineWidth = 3
        addChild(board)
    }
}
