import MedievalDomain
import SpriteKit

final class GameScene: SKScene {
    var onSelectHex: ((HexID) -> Void)?

    private let titleLabel = SKLabelNode(fontNamed: "Palatino-Bold")
    private let turnLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
    private let mapLayer = SKNode()
    private let cityLayer = SKNode()
    private let armyLayer = SKNode()
    private let mapContainer = SKNode()
    private static let gridLineWidth: CGFloat = 2
    private static let selectionLineWidth: CGFloat = 5
    /// The vertical scroll delta that counts as one full zoom step. A mouse
    /// wheel tick already exceeds it; a trackpad reaches it over several events.
    private static let fullZoomStepDelta: CGFloat = 10
    private static let minimumZoom: CGFloat = 0.65
    private static let maximumZoom: CGFloat = 2.5
    private let hexRadius: CGFloat = 46
    private var hexCenters: [HexID: CGPoint] = [:]
    private var zoom: CGFloat = 1
    private var dragStart: CGPoint?
    private var isDragging = false
    private var lastCameraResetToken = -1
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

        addChild(mapContainer)
        mapContainer.addChild(mapLayer)
        mapContainer.addChild(cityLayer)
        mapContainer.addChild(armyLayer)
    }

    override func didChangeSize(_: CGSize) {
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 42)
        turnLabel.position = CGPoint(x: size.width / 2, y: size.height - 70)
        if let last = lastDrawn {
            drawMap(last.map, world: last.world, selectedHexID: last.selectedHexID)
        }
    }

    func render(_ state: GameState, map: StaticHexMap, world: WorldState, selectedHexID: HexID?, cameraResetToken: Int) {
        titleLabel.text = map.displayName
        turnLabel.text = "Хід \(state.turn) · \(state.activePlayer.displayName)"
        drawMap(map, world: world, selectedHexID: selectedHexID)
        if lastCameraResetToken != cameraResetToken {
            lastCameraResetToken = cameraResetToken
            resetCamera()
        } else {
            clampMapPosition()
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard !isDragging else {
            isDragging = false
            return
        }
        let point = event.location(in: self)
        guard let node = nodes(at: point).first(where: { $0.name?.hasPrefix("hex:") == true }),
              let rawID = node.name?.dropFirst(4)
        else { return }
        onSelectHex?(HexID(rawValue: String(rawID)))
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.location(in: self)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.location(in: self)
        guard let dragStart else { return }
        let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
        if abs(delta.x) > 2 || abs(delta.y) > 2 { isDragging = true }
        mapContainer.position = CGPoint(x: mapContainer.position.x + delta.x, y: mapContainer.position.y + delta.y)
        self.dragStart = point
        clampMapPosition()
    }

    override func scrollWheel(with event: NSEvent) {
        // A horizontal scroll reports a vertical delta of zero. Without this
        // guard it fell through to the "scrolled down" branch, so swiping
        // sideways on a trackpad zoomed the map out.
        guard event.scrollingDeltaY != 0 else { return }

        // A trackpad emits a stream of small precise deltas where a mouse emits
        // one coarse tick, so a fixed step per event made the trackpad lurch.
        let step = min(abs(event.scrollingDeltaY), Self.fullZoomStepDelta) / Self.fullZoomStepDelta
        let factor = 1 + step * (event.scrollingDeltaY > 0 ? 0.12 : -0.11)
        setZoom(zoom * factor, anchoredAt: event.location(in: self))
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), anchoredAt: event.location(in: self))
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
            node.strokeColor = .init(white: 0.15, alpha: 0.9)
            node.lineWidth = Self.gridLineWidth
            mapLayer.addChild(node)
        }

        if let selectedHexID, let center = hexCenters[selectedHexID] {
            mapLayer.addChild(selectionHighlight(at: center))
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

    private func resetCamera() {
        zoom = 1
        mapContainer.setScale(zoom)
        mapContainer.position = .zero
        clampMapPosition()
    }

    /// Zooms, keeping the scene point under `anchor` where it is.
    ///
    /// Scaling a node moves everything towards or away from its origin, so an
    /// unanchored zoom slides the map out from under the pointer. Offsetting the
    /// container by the same ratio pins whatever the player is looking at:
    /// the anchor's position inside the container is `(anchor - position) / zoom`,
    /// and holding it still across the change gives
    /// `position' = anchor - (anchor - position) * zoom' / zoom`.
    private func setZoom(_ value: CGFloat, anchoredAt anchor: CGPoint?) {
        let clamped = min(max(value, Self.minimumZoom), Self.maximumZoom)
        guard clamped != zoom else { return }

        if let anchor {
            let ratio = clamped / zoom
            mapContainer.position = CGPoint(
                x: anchor.x - (anchor.x - mapContainer.position.x) * ratio,
                y: anchor.y - (anchor.y - mapContainer.position.y) * ratio
            )
        }
        zoom = clamped
        mapContainer.setScale(zoom)
        clampMapPosition()
    }

    private func clampMapPosition() {
        let frame = mapLayer.calculateAccumulatedFrame().insetBy(dx: -hexRadius, dy: -hexRadius)
        guard frame.width > 0, frame.height > 0 else { return }

        let scaledWidth = frame.width * zoom
        let scaledHeight = frame.height * zoom
        let horizontal: CGFloat = if scaledWidth <= size.width {
            size.width / 2 - (frame.midX * zoom)
        } else {
            min(max(mapContainer.position.x, size.width - frame.maxX * zoom), -frame.minX * zoom)
        }
        let vertical: CGFloat = if scaledHeight <= size.height - 100 {
            (size.height - 100) / 2 - (frame.midY * zoom) - 35
        } else {
            min(max(mapContainer.position.y, 20 - frame.minY * zoom), size.height - 100 - frame.maxY * zoom)
        }
        mapContainer.position = CGPoint(x: horizontal, y: vertical)
    }

    private func point(for coordinate: HexCoordinate, bounds: HexMapBounds) -> CGPoint {
        let q = CGFloat(coordinate.q - bounds.minimumQ)
        let r = CGFloat(coordinate.r - bounds.minimumR)
        let x = 110 + hexRadius * sqrt(3) * (q + r / 2)
        let y = size.height - 155 - hexRadius * 1.5 * r
        return CGPoint(x: x, y: y)
    }

    /// The selection outline drawn wholly inside its hex.
    ///
    /// SpriteKit centres a stroke on its path, so half of it would sit in the
    /// neighbouring hexes — and those are drawn afterwards, so their fill
    /// painted over it and the highlight came out clipped on every side that
    /// had a later neighbour. Insetting the path by half the line width keeps
    /// the outline on the selected hex's own ground.
    private func selectionHighlight(at center: CGPoint) -> SKShapeNode {
        // A hexagon's edges sit at `radius * cos(30°)` from the centre, so
        // moving them inwards by `d` costs `d / cos(30°)` of radius.
        let inset = Self.selectionLineWidth / 2 / cos(.pi / 6)
        let node = SKShapeNode(path: hexPath(center: center, radius: hexRadius - inset))
        node.strokeColor = .white
        node.lineWidth = Self.selectionLineWidth
        node.fillColor = .clear
        node.zPosition = 1
        return node
    }

    private func hexPath(center: CGPoint, radius: CGFloat? = nil) -> CGPath {
        let radius = radius ?? hexRadius
        let path = CGMutablePath()
        for index in 0 ..< 6 {
            let angle = CGFloat.pi / 180 * (60 * CGFloat(index) - 30)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// One colour per terrain type in the MVP content.
    ///
    /// The fallback exists only for terrain the content adds without a colour
    /// here — validation already rejects terrain that nothing defines, so it
    /// should never show up in a shipped map.
    private func terrainColor(_ id: TerrainID) -> SKColor {
        switch id.rawValue {
        case "plains": .init(red: 0.35, green: 0.51, blue: 0.25, alpha: 1)
        case "desert": .init(red: 0.76, green: 0.68, blue: 0.42, alpha: 1)
        case "forest": .init(red: 0.18, green: 0.42, blue: 0.22, alpha: 1)
        case "hills": .init(red: 0.48, green: 0.39, blue: 0.23, alpha: 1)
        case "mountains": .init(red: 0.42, green: 0.43, blue: 0.46, alpha: 1)
        case "swamp": .init(red: 0.30, green: 0.35, blue: 0.22, alpha: 1)
        case "shallows": .init(red: 0.28, green: 0.53, blue: 0.63, alpha: 1)
        case "deep-water": .init(red: 0.12, green: 0.29, blue: 0.48, alpha: 1)
        default: .init(red: 0.55, green: 0.20, blue: 0.55, alpha: 1)
        }
    }
}
