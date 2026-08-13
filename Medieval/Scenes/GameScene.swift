import SpriteKit

final class GameScene: SKScene {
    var onSelectHex: ((HexID) -> Void)?

    private let titleLabel = SKLabelNode(fontNamed: "Palatino-Bold")
    private let turnLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
    private let mapLayer = SKNode()
    private let overlayLayer = SKNode()
    private let riverLayer = SKNode()
    private let routeLayer = SKNode()
    private let cityLayer = SKNode()
    private let armyLayer = SKNode()
    private let mapContainer = SKNode()
    private static let gridLineWidth: CGFloat = 2
    private static let selectionLineWidth: CGFloat = 5
    /// The vertical scroll delta that counts as one full zoom step. A mouse
    /// wheel tick already exceeds it; a trackpad reaches it over several events.
    private static let fullZoomStepDelta: CGFloat = 10
    private static let minimumZoom: CGFloat = 0.12
    private static let maximumZoom: CGFloat = 2.5
    private static let spriteScale: CGFloat = 2
    private static let nativeTileSize = CGSize(width: 39, height: 43)
    private static let nativeHorizontalStep: CGFloat = 36.5
    private static let nativeVerticalStep: CGFloat = 30
    private let hexRadius: CGFloat = 40
    private let hexHalfWidth: CGFloat = 36.5
    private var hexCenters: [HexID: CGPoint] = [:]
    private var renderedMapID: String?
    private var mapMinimumProjectedX: CGFloat = 0
    private var mapMaximumR = 0
    private var zoom: CGFloat = 1
    private var dragStart: CGPoint?
    private var isDragging = false
    private var lastCameraResetToken = -1

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
        mapContainer.addChild(overlayLayer)
        mapContainer.addChild(riverLayer)
        mapContainer.addChild(routeLayer)
        mapContainer.addChild(cityLayer)
        mapContainer.addChild(armyLayer)
    }

    override func didChangeSize(_: CGSize) {
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 42)
        turnLabel.position = CGPoint(x: size.width / 2, y: size.height - 70)
        clampMapPosition()
    }

    func render(_ state: GameState, map: StaticHexMap, world: WorldState, selectedHexID: HexID?, reachableHexIDs: Set<HexID>, encounterHexIDs: Set<HexID>, previewRoute: MovementRoute?, cameraResetToken: Int) {
        titleLabel.text = map.displayName
        turnLabel.text = "Раунд \(state.turn) · \(state.activePlayer.displayName) · \(phaseName(state.phase))"
        drawMap(map, world: world, selectedHexID: selectedHexID, reachableHexIDs: reachableHexIDs, encounterHexIDs: encounterHexIDs, previewRoute: previewRoute)
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
        guard let id = hexID(at: event.location(in: self)) else { return }
        onSelectHex?(id)
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

    private func drawMap(
        _ map: StaticHexMap,
        world: WorldState,
        selectedHexID: HexID?,
        reachableHexIDs: Set<HexID>,
        encounterHexIDs: Set<HexID>,
        previewRoute: MovementRoute?
    ) {
        rebuildMapIfNeeded(map)
        [overlayLayer, riverLayer, routeLayer, cityLayer, armyLayer].forEach { $0.removeAllChildren() }

        for id in reachableHexIDs {
            guard let center = hexCenters[id] else { continue }
            overlayLayer.addChild(highlight(at: center, color: .init(red: 0.28, green: 0.92, blue: 0.52, alpha: 0.28)))
        }
        for id in encounterHexIDs {
            guard let center = hexCenters[id] else { continue }
            overlayLayer.addChild(highlight(at: center, color: .init(red: 0.95, green: 0.20, blue: 0.17, alpha: 0.38)))
        }

        if let selectedHexID, let center = hexCenters[selectedHexID] {
            overlayLayer.addChild(selectionHighlight(at: center))
        }

        for river in world.riverBoundaries {
            guard let firstCenter = hexCenters[river.boundary.firstHexID],
                  let secondCenter = hexCenters[river.boundary.secondHexID],
                  let path = riverPath(between: firstCenter, and: secondCenter)
            else { continue }

            let border = SKShapeNode(path: path)
            border.name = "river:border"
            border.strokeColor = .init(red: 0.03, green: 0.12, blue: 0.17, alpha: 0.95)
            border.lineCap = .round
            riverLayer.addChild(border)

            let water = SKShapeNode(path: path)
            water.name = "river:water"
            water.strokeColor = .init(red: 0.40, green: 0.84, blue: 0.94, alpha: 1)
            water.lineCap = .round
            riverLayer.addChild(water)
        }
        updateRiverLineWidths()

        if let previewRoute {
            let path = CGMutablePath()
            for (index, id) in previewRoute.hexIDs.enumerated() {
                guard let center = hexCenters[id] else { continue }
                if index == 0 { path.move(to: center) } else { path.addLine(to: center) }
            }
            let line = SKShapeNode(path: path)
            line.strokeColor = .init(red: 1, green: 0.84, blue: 0.28, alpha: 1)
            line.lineWidth = 7 / zoom
            line.lineCap = .round
            line.zPosition = 3
            routeLayer.addChild(line)
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
            label.text = "⚔︎\(army.unitIDs.count)"
            label.fontSize = 16
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: center.x, y: center.y - 23)
            armyLayer.addChild(label)
        }
        let armyUnitIDs = Set(world.armies.flatMap(\.unitIDs))
        let visibleUnits = Dictionary(grouping: world.units.filter { $0.condition != .destroyed && !armyUnitIDs.contains($0.id) }) { unit -> HexID? in
            switch unit.location {
            case let .hex(hexID): hexID
            case let .garrison(cityID): world.cities.first(where: { $0.id == cityID })?.hexID
            case .cargo: nil
            }
        }
        for (hexID, units) in visibleUnits {
            guard let hexID, let center = hexCenters[hexID] else { continue }
            let label = SKLabelNode(fontNamed: "SF Pro Rounded-Bold")
            label.text = units.contains(where: { $0.typeID == "ship" }) ? "⚓︎\(units.count)" : "⚔︎\(units.count)"
            label.fontSize = 16
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: center.x, y: center.y - 23)
            armyLayer.addChild(label)
        }
    }

    private func rebuildMapIfNeeded(_ map: StaticHexMap) {
        guard renderedMapID != map.id || hexCenters.count != map.hexes.count else { return }

        renderedMapID = map.id
        mapLayer.removeAllChildren()
        hexCenters = [:]
        mapMinimumProjectedX = map.hexes
            .map { CGFloat($0.coordinate.q) + CGFloat($0.coordinate.r) / 2 }
            .min() ?? 0
        mapMaximumR = map.hexes.map(\.coordinate.r).max() ?? 0

        for hex in map.hexes {
            let center = point(for: hex.coordinate)
            hexCenters[hex.id] = center
            let textureName = "hex-\(hex.id.rawValue)"
            if Bundle.main.url(forResource: textureName, withExtension: "png") != nil {
                let texture = SKTexture(imageNamed: textureName)
                texture.filteringMode = .nearest
                let node = SKSpriteNode(
                    texture: texture,
                    size: CGSize(
                        width: Self.nativeTileSize.width * Self.spriteScale,
                        height: Self.nativeTileSize.height * Self.spriteScale
                    )
                )
                node.name = "hex:\(hex.id.rawValue)"
                node.position = center
                mapLayer.addChild(node)
            } else {
                let node = SKShapeNode(path: hexPath(center: center))
                node.name = "hex:\(hex.id.rawValue)"
                node.fillColor = terrainColor(hex.terrainID)
                node.strokeColor = .init(white: 0.15, alpha: 0.9)
                node.lineWidth = Self.gridLineWidth
                mapLayer.addChild(node)
            }
        }
    }

    private func hexID(at scenePoint: CGPoint) -> HexID? {
        let mapPoint = mapContainer.convert(scenePoint, from: self)
        let closest = hexCenters.min { first, second in
            squaredDistance(from: first.value, to: mapPoint) < squaredDistance(from: second.value, to: mapPoint)
        }
        guard let closest, hexPath(center: closest.value).contains(mapPoint) else { return nil }
        return closest.key
    }

    private func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let x = first.x - second.x
        let y = first.y - second.y
        return x * x + y * y
    }

    private func resetCamera() {
        let frame = mapLayer.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12)
        let availableWidth = max(size.width - 40, 1)
        let availableHeight = max(size.height - 130, 1)
        let fittedZoom = min(
            min(availableWidth / max(frame.width, 1), availableHeight / max(frame.height, 1)),
            1
        )
        zoom = min(max(fittedZoom, Self.minimumZoom), Self.maximumZoom)
        mapContainer.setScale(zoom)
        updateRiverLineWidths()
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
        updateRiverLineWidths()
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

    private func point(for coordinate: HexCoordinate) -> CGPoint {
        let projectedX = CGFloat(coordinate.q) + CGFloat(coordinate.r) / 2
        let x = Self.nativeTileSize.width * Self.spriteScale / 2
            + Self.nativeHorizontalStep * Self.spriteScale * (projectedX - mapMinimumProjectedX)
        let y = Self.nativeTileSize.height * Self.spriteScale / 2
            + Self.nativeVerticalStep * Self.spriteScale * CGFloat(mapMaximumR - coordinate.r)
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
        let node = SKShapeNode(path: hexPath(center: center, scale: 0.91))
        node.strokeColor = .white
        node.lineWidth = Self.selectionLineWidth
        node.fillColor = .clear
        node.zPosition = 1
        return node
    }

    private func highlight(at center: CGPoint, color: SKColor) -> SKShapeNode {
        let node = SKShapeNode(path: hexPath(center: center, scale: 0.91))
        node.fillColor = color
        node.strokeColor = .clear
        node.zPosition = 1
        return node
    }

    private func hexPath(center: CGPoint, scale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        let vertices = [
            CGPoint(x: 0, y: hexRadius),
            CGPoint(x: hexHalfWidth, y: hexRadius / 2),
            CGPoint(x: hexHalfWidth, y: -hexRadius / 2),
            CGPoint(x: 0, y: -hexRadius),
            CGPoint(x: -hexHalfWidth, y: -hexRadius / 2),
            CGPoint(x: -hexHalfWidth, y: hexRadius / 2),
        ]
        for (index, vertex) in vertices.enumerated() {
            let point = CGPoint(x: center.x + vertex.x * scale, y: center.y + vertex.y * scale)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func riverPath(between first: CGPoint, and second: CGPoint) -> CGPath? {
        let delta = CGPoint(x: second.x - first.x, y: second.y - first.y)
        let length = hypot(delta.x, delta.y)
        guard length > 0 else { return nil }

        let midpoint = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        let halfEdge = CGPoint(x: -delta.y / length * hexRadius / 2, y: delta.x / length * hexRadius / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: midpoint.x - halfEdge.x, y: midpoint.y - halfEdge.y))
        path.addLine(to: CGPoint(x: midpoint.x + halfEdge.x, y: midpoint.y + halfEdge.y))
        return path
    }

    private func updateRiverLineWidths() {
        for node in riverLayer.children.compactMap({ $0 as? SKShapeNode }) {
            node.lineWidth = (node.name == "river:border" ? 11 : 6) / zoom
        }
    }

    /// One colour per terrain type in the MVP content.
    ///
    /// The fallback exists only for terrain the content adds without a colour
    /// here — validation already rejects terrain that nothing defines, so it
    /// should never show up in a shipped map.
    private func terrainColor(_ id: TerrainID) -> SKColor {
        switch id.rawValue {
        case "plains": .init(red: 0.53, green: 0.67, blue: 0.27, alpha: 1)
        case "desert": .init(red: 0.81, green: 0.62, blue: 0.29, alpha: 1)
        case "forest": .init(red: 0.18, green: 0.42, blue: 0.22, alpha: 1)
        case "hills": .init(red: 0.48, green: 0.39, blue: 0.23, alpha: 1)
        case "mountains": .init(red: 0.42, green: 0.43, blue: 0.46, alpha: 1)
        case "swamp": .init(red: 0.25, green: 0.37, blue: 0.30, alpha: 1)
        case "shallows": .init(red: 0.28, green: 0.63, blue: 0.70, alpha: 1)
        case "deep-water": .init(red: 0.10, green: 0.25, blue: 0.52, alpha: 1)
        default: .magenta
        }
    }

    private func phaseName(_ phase: GamePhase) -> String {
        switch phase {
        case .economy: "Економіка"
        case .construction: "Будівництво й найм"
        case .movement: "Рух"
        case .combat: "Бої"
        case .handoff: "Передача ходу"
        case .finished: "Завершено"
        default: "Підготовка"
        }
    }
}
