import SpriteKit

/// One side's units standing on one hex, which is what a single map label
/// counts.
private struct UnitStack: Hashable {
    let hexID: HexID?
    let ownerID: WorldPlayerID
}

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
    private static let renderedTileSize = CGSize(width: 80, height: 90)
    private static let horizontalStep: CGFloat = 73
    private static let verticalStep: CGFloat = 60
    private let hexRadius: CGFloat = 40
    private let hexHalfWidth: CGFloat = 36.5
    private var hexCenters: [HexID: CGPoint] = [:]
    private var terrainTextures: [TerrainID: SKTexture] = [:]
    private var riverOverlayTexture: SKTexture?
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
        drawMap(map, state: state, world: world, selectedHexID: selectedHexID, reachableHexIDs: reachableHexIDs, encounterHexIDs: encounterHexIDs, previewRoute: previewRoute)
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

    func handleScrollWheel(with event: NSEvent) {
        // Two-finger trackpad scrolling pans in both axes. Holding Command
        // turns it into zoom, matching the familiar map/canvas convention.
        if event.hasPreciseScrollingDeltas,
           !event.modifierFlags.contains(.command)
        {
            let translation = MapCamera.panTranslation(
                scrollingDeltaX: event.scrollingDeltaX,
                scrollingDeltaY: event.scrollingDeltaY
            )
            mapContainer.position = CGPoint(
                x: mapContainer.position.x + translation.dx,
                y: mapContainer.position.y + translation.dy
            )
            clampMapPosition()
            return
        }

        guard event.scrollingDeltaY != 0 else { return }
        let step = min(abs(event.scrollingDeltaY), Self.fullZoomStepDelta) / Self.fullZoomStepDelta
        let factor = 1 + step * (event.scrollingDeltaY > 0 ? 0.12 : -0.11)
        setZoom(zoom * factor, anchoredAt: event.location(in: self))
    }

    func handleMagnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), anchoredAt: event.location(in: self))
    }

    private func drawMap(
        _ map: StaticHexMap,
        state: GameState,
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
                  let secondCenter = hexCenters[river.boundary.secondHexID]
            else { continue }

            riverLayer.addChild(riverNode(from: firstCenter, to: secondCenter))
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

        let colorByOwner = playerColorsByWorldPlayer(state)
        for city in world.cities {
            guard let center = hexCenters[city.hexID] else { continue }
            cityLayer.addChild(
                cityMarker(
                    at: center,
                    color: ownerColor(city.ownerID, in: colorByOwner),
                    isCapital: city.isCapital
                )
            )
        }
        updateCityMarkerScales()
        for army in world.armies {
            guard let center = hexCenters[army.hexID] else { continue }
            let label = SKLabelNode(fontNamed: "SFProRounded-Bold")
            label.text = "⚔︎\(army.unitIDs.count)"
            label.fontSize = 16
            label.fontColor = ownerColor(army.ownerID, in: colorByOwner)
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: center.x, y: center.y - 23)
            armyLayer.addChild(label)
        }
        let armyUnitIDs = Set(world.armies.flatMap(\.unitIDs))
        // Grouped by owner as well as by hex: a garrison and a besieging force
        // can share a hex, and one label in one colour would credit both to
        // whoever happened to come first.
        let visibleUnits = Dictionary(grouping: world.units.filter { $0.condition != .destroyed && !armyUnitIDs.contains($0.id) }) { unit -> UnitStack in
            let hexID: HexID? = switch unit.location {
            case let .hex(hexID): hexID
            case let .garrison(cityID): world.cities.first(where: { $0.id == cityID })?.hexID
            case .cargo: nil
            }
            return UnitStack(hexID: hexID, ownerID: unit.ownerID)
        }
        for (stack, units) in visibleUnits {
            guard let hexID = stack.hexID, let center = hexCenters[hexID] else { continue }
            let label = SKLabelNode(fontNamed: "SF Pro Rounded-Bold")
            label.text = units.contains(where: { $0.typeID == "ship" }) ? "⚓︎\(units.count)" : "⚔︎\(units.count)"
            label.fontSize = 16
            label.fontColor = ownerColor(stack.ownerID, in: colorByOwner)
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
        terrainTextures = [:]
        mapMinimumProjectedX = map.hexes
            .map { CGFloat($0.coordinate.q) + CGFloat($0.coordinate.r) / 2 }
            .min() ?? 0
        mapMaximumR = map.hexes.map(\.coordinate.r).max() ?? 0

        for hex in map.hexes {
            let center = point(for: hex.coordinate)
            hexCenters[hex.id] = center
            if let texture = terrainTexture(for: hex.terrainID) {
                let node = SKSpriteNode(
                    texture: texture,
                    size: Self.renderedTileSize
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

    private func terrainTexture(for terrainID: TerrainID) -> SKTexture? {
        if let cached = terrainTextures[terrainID] { return cached }
        let name = "hex-terrain-\(terrainID.rawValue)"
        guard Bundle.main.url(forResource: name, withExtension: "png") != nil else { return nil }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .linear
        terrainTextures[terrainID] = texture
        return texture
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
        zoom = MapCamera.fittedZoom(content: frame.size, viewport: size)
        mapContainer.setScale(zoom)
        updateRiverLineWidths()
        updateCityMarkerScales()
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
        let clamped = MapCamera.clampZoom(value)
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
        updateCityMarkerScales()
        clampMapPosition()
    }

    private func clampMapPosition() {
        let frame = mapLayer.calculateAccumulatedFrame().insetBy(dx: -hexRadius, dy: -hexRadius)
        guard frame.width > 0, frame.height > 0 else { return }

        mapContainer.position = MapCamera.clamped(
            position: mapContainer.position,
            content: frame,
            zoom: zoom,
            viewport: size
        )
    }

    private func point(for coordinate: HexCoordinate) -> CGPoint {
        let projectedX = CGFloat(coordinate.q) + CGFloat(coordinate.r) / 2
        let x = Self.renderedTileSize.width / 2
            + Self.horizontalStep * (projectedX - mapMinimumProjectedX)
        let y = Self.renderedTileSize.height / 2
            + Self.verticalStep * CGFloat(mapMaximumR - coordinate.r)
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

    /// The owner colours of the match, keyed the way the world names its
    /// players. `GameState` holds the colours and `WorldState` the cities, so
    /// the two are joined here rather than in either of them.
    private func playerColorsByWorldPlayer(_ state: GameState) -> [WorldPlayerID: PlayerColor] {
        Dictionary(
            state.players.compactMap { player in player.worldPlayerID.map { ($0, player.color) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func ownerColor(_ ownerID: WorldPlayerID?, in colors: [WorldPlayerID: PlayerColor]) -> SKColor {
        guard let ownerID, let color = colors[ownerID] else { return Self.neutralOwnerColor }
        return markerColor(color)
    }

    private static let neutralOwnerColor = SKColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)

    /// The same four colours the HUD uses, so the dot next to a player's name
    /// and their holdings on the map read as one side.
    private func markerColor(_ color: PlayerColor) -> SKColor {
        switch color {
        case .red: .init(red: 0.90, green: 0.22, blue: 0.21, alpha: 1)
        case .blue: .init(red: 0.20, green: 0.47, blue: 0.95, alpha: 1)
        case .green: .init(red: 0.24, green: 0.72, blue: 0.35, alpha: 1)
        case .gold: .init(red: 0.98, green: 0.80, blue: 0.18, alpha: 1)
        }
    }

    /// A capital is a star and an ordinary city a disc, so the two stay apart
    /// even for a player who cannot tell the owner colours apart.
    private func cityMarker(at center: CGPoint, color: SKColor, isCapital: Bool) -> SKNode {
        let node = SKShapeNode(
            path: isCapital
                ? starPath(radius: Self.capitalMarkerRadius)
                : CGPath(
                    ellipseIn: CGRect(
                        x: -Self.cityMarkerRadius,
                        y: -Self.cityMarkerRadius,
                        width: Self.cityMarkerRadius * 2,
                        height: Self.cityMarkerRadius * 2
                    ),
                    transform: nil
                )
        )
        node.name = isCapital ? "city:capital" : "city:marker"
        node.position = center
        node.fillColor = color
        node.strokeColor = .init(white: 0.08, alpha: 0.95)
        node.lineWidth = 2
        node.zPosition = 4
        return node
    }

    private static let cityMarkerRadius: CGFloat = 12
    private static let capitalMarkerRadius: CGFloat = 17
    /// How far a marker may be blown up as the map shrinks. Past this it would
    /// spill over its own hex and hide its neighbours.
    private static let maximumCityMarkerScale: CGFloat = 2.4

    /// Markers are drawn in map coordinates, so zooming out to the whole of
    /// Europe would shrink a capital to a couple of pixels. Growing them as the
    /// map shrinks keeps who-owns-what legible at every zoom.
    private func updateCityMarkerScales() {
        let scale = min(max(1 / zoom, 1), Self.maximumCityMarkerScale)
        for node in cityLayer.children {
            node.setScale(scale)
        }
    }

    private func starPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 5
        for index in 0 ..< points * 2 {
            let isOuter = index % 2 == 0
            let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let length = isOuter ? radius : radius * 0.44
            let point = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
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

    private func riverNode(from first: CGPoint, to second: CGPoint) -> SKNode {
        if riverOverlayTexture == nil,
           Bundle.main.url(forResource: "hex-river-edge-ne", withExtension: "png") != nil
        {
            let texture = SKTexture(imageNamed: "hex-river-edge-ne")
            texture.filteringMode = .linear
            riverOverlayTexture = texture
        }
        if let riverOverlayTexture {
            let node = SKSpriteNode(texture: riverOverlayTexture, size: Self.renderedTileSize)
            let direction = atan2(second.y - first.y, second.x - first.x)
            let sixtyDegrees = CGFloat.pi / 3
            node.zRotation = round((direction - sixtyDegrees) / sixtyDegrees) * sixtyDegrees
            node.name = "river:overlay"
            node.position = first
            node.zPosition = 2
            return node
        }

        let container = SKNode()
        guard let path = riverPath(between: first, and: second) else { return container }
        let border = SKShapeNode(path: path)
        border.name = "river:border"
        border.strokeColor = .init(red: 0.03, green: 0.12, blue: 0.17, alpha: 0.95)
        border.lineCap = .round
        container.addChild(border)
        let water = SKShapeNode(path: path)
        water.name = "river:water"
        water.strokeColor = .init(red: 0.40, green: 0.84, blue: 0.94, alpha: 1)
        water.lineCap = .round
        container.addChild(water)
        return container
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
