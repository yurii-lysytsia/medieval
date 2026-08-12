import MedievalDomain
import SpriteKit

final class GameScene: SKScene {
    var onSelectHex: ((HexID) -> Void)?

    private let titleLabel = SKLabelNode(fontNamed: "Palatino-Bold")
    private let turnLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
    private let mapLayer = SKNode()
    private let cityLayer = SKNode()
    private let armyLayer = SKNode()
    private let hexRadius: CGFloat = 46
    private var hexCenters: [HexID: CGPoint] = [:]
    /// Hex positions are measured down from the top of the scene, so a resize
    /// invalidates them. Kept so `didChangeSize` can redraw without waiting for
    /// the next state change to arrive from SwiftUI.
    private var lastDrawn: (map: StaticHexMap, world: WorldState, selectedHexID: HexID?)?

    override func didMove(to _: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .init(red: 0.07, green: 0.12, blue: 0.10, alpha: 1)

        titleLabel.fontSize = 30
        titleLabel.fontColor = .init(red: 0.94, green: 0.78, blue: 0.42, alpha: 1)
        titleLabel.verticalAlignmentMode = .center
        titleLabel.zPosition = 10
        addChild(titleLabel)

        turnLabel.fontSize = 16
        turnLabel.fontColor = .init(white: 0.85, alpha: 1)
        turnLabel.verticalAlignmentMode = .center
        turnLabel.zPosition = 10
        addChild(turnLabel)

        addChild(mapLayer)
        addChild(cityLayer)
        addChild(armyLayer)
    }

    override func didChangeSize(_: CGSize) {
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 42)
        turnLabel.position = CGPoint(x: size.width / 2, y: size.height - 70)
        if let last = lastDrawn {
            drawMap(last.map, world: last.world, selectedHexID: last.selectedHexID)
        }
    }

    func render(_ state: GameState, map: StaticHexMap, world: WorldState, selectedHexID: HexID?) {
        titleLabel.text = map.displayName
        turnLabel.text = "Хід \(state.turn) · \(state.activePlayer.displayName)"
        drawMap(map, world: world, selectedHexID: selectedHexID)
    }

    override func mouseUp(with event: NSEvent) {
        let point = event.location(in: self)
        guard let node = nodes(at: point).first(where: { $0.name?.hasPrefix("hex:") == true }),
              let rawID = node.name?.dropFirst(4)
        else { return }
        onSelectHex?(HexID(rawValue: String(rawID)))
    }

    private func drawMap(_ map: StaticHexMap, world: WorldState, selectedHexID: HexID?) {
        lastDrawn = (map, world, selectedHexID)
        [mapLayer, cityLayer, armyLayer].forEach { $0.removeAllChildren() }
        hexCenters = [:]

        for hex in map.hexes {
            let center = point(for: hex.coordinate, bounds: map.bounds)
            hexCenters[hex.id] = center
            let node = SKShapeNode(path: hexPath(center: center))
            node.name = "hex:\(hex.id.rawValue)"
            node.fillColor = terrainColor(hex.terrainID)
            node.strokeColor = hex.id == selectedHexID ? .white : .init(white: 0.15, alpha: 0.9)
            node.lineWidth = hex.id == selectedHexID ? 5 : 2
            mapLayer.addChild(node)
        }

        for city in world.cities {
            guard let center = hexCenters[city.hexID] else { continue }
            let marker = SKShapeNode(circleOfRadius: 12)
            marker.position = center
            marker.fillColor = .init(red: 0.93, green: 0.77, blue: 0.35, alpha: 1)
            marker.strokeColor = .black
            marker.lineWidth = 2
            cityLayer.addChild(marker)
        }
        for army in world.armies {
            guard let center = hexCenters[army.hexID] else { continue }
            let label = SKLabelNode(fontNamed: "SFProRounded-Bold")
            label.text = "⚔︎\(army.quantity)"
            label.fontSize = 16
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: center.x, y: center.y - 23)
            armyLayer.addChild(label)
        }
    }

    private func point(for coordinate: HexCoordinate, bounds: HexMapBounds) -> CGPoint {
        let q = CGFloat(coordinate.q - bounds.minimumQ)
        let r = CGFloat(coordinate.r - bounds.minimumR)
        let x = 110 + hexRadius * sqrt(3) * (q + r / 2)
        let y = size.height - 155 - hexRadius * 1.5 * r
        return CGPoint(x: x, y: y)
    }

    private func hexPath(center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for index in 0 ..< 6 {
            let angle = CGFloat.pi / 180 * (60 * CGFloat(index) - 30)
            let point = CGPoint(x: center.x + hexRadius * cos(angle), y: center.y + hexRadius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func terrainColor(_ id: TerrainID) -> SKColor {
        switch id.rawValue {
        case "forest": .init(red: 0.18, green: 0.42, blue: 0.22, alpha: 1)
        case "hills": .init(red: 0.48, green: 0.39, blue: 0.23, alpha: 1)
        case "mountains": .init(red: 0.42, green: 0.43, blue: 0.46, alpha: 1)
        case "ocean": .init(red: 0.12, green: 0.29, blue: 0.48, alpha: 1)
        default: .init(red: 0.35, green: 0.51, blue: 0.25, alpha: 1)
        }
    }
}
