import CoreGraphics

/// Where the strategic map may sit inside the scene, and how far it may zoom.
///
/// The maths lives here rather than in `GameScene` so it can be exercised
/// without a window: the camera is pure geometry, and the bug it was extracted
/// for — a vertical clamp whose bounds were the wrong way round, pinning the
/// map to one position — is invisible in code review but obvious in a test.
struct MapCamera: Equatable {
    /// Room kept clear at the top of the scene for the map title and the turn
    /// line, and at the bottom so the lowest hexes are not flush with the edge.
    static let topInset: CGFloat = 100
    static let bottomInset: CGFloat = 20
    static let minimumZoom: CGFloat = 0.12
    static let maximumZoom: CGFloat = 2.5

    /// The zoom that shows the whole map at once, never magnifying past 1:1.
    static func fittedZoom(content: CGSize, viewport: CGSize) -> CGFloat {
        let available = CGSize(
            width: max(viewport.width - 40, 1),
            height: max(viewport.height - topInset - bottomInset - 10, 1)
        )
        let fitted = min(
            min(available.width / max(content.width, 1), available.height / max(content.height, 1)),
            1
        )
        return clampZoom(fitted)
    }

    static func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumZoom), maximumZoom)
    }

    /// Keeps the map over the viewport: it may be dragged until an edge reaches
    /// the corresponding edge of the visible area, and no further. A map smaller
    /// than the viewport ignores the drag entirely and stays centred, because
    /// there is nothing off screen to bring into view.
    ///
    /// `content` is the map's frame in its own coordinates, so the scaled edges
    /// are `content.minX * zoom + position.x` and `content.maxX * zoom + position.x`.
    static func clamped(
        position: CGPoint,
        content: CGRect,
        zoom: CGFloat,
        viewport: CGSize
    ) -> CGPoint {
        CGPoint(
            x: clampedAxis(
                position.x,
                contentMinimum: content.minX * zoom,
                contentLength: content.width * zoom,
                viewportMinimum: 0,
                viewportLength: viewport.width
            ),
            y: clampedAxis(
                position.y,
                contentMinimum: content.minY * zoom,
                contentLength: content.height * zoom,
                viewportMinimum: bottomInset,
                viewportLength: max(viewport.height - topInset - bottomInset, 0)
            )
        )
    }

    private static func clampedAxis(
        _ value: CGFloat,
        contentMinimum: CGFloat,
        contentLength: CGFloat,
        viewportMinimum: CGFloat,
        viewportLength: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else {
            return viewportMinimum + (viewportLength - contentLength) / 2 - contentMinimum
        }
        // The map covers the viewport, so its low edge may not rise above the
        // viewport's low edge, and its high edge may not fall below the high one.
        let lowest = viewportMinimum + viewportLength - (contentMinimum + contentLength)
        let highest = viewportMinimum - contentMinimum
        return min(max(value, lowest), highest)
    }
}
