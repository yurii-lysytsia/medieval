import CoreGraphics
@testable import Medieval
import Testing

struct MapCameraTests {
    private let viewport = CGSize(width: 800, height: 600)
    /// Taller and wider than the viewport, so both axes have somewhere to go.
    private let content = CGRect(x: 0, y: 0, width: 2000, height: 1800)

    @Test func dragsVerticallyWhenTheMapIsTallerThanTheViewport() {
        let up = MapCamera.clamped(position: CGPoint(x: -100, y: 200), content: content, zoom: 1, viewport: viewport)
        let down = MapCamera.clamped(position: CGPoint(x: -100, y: -400), content: content, zoom: 1, viewport: viewport)

        #expect(up.y != down.y)
        #expect(up.y > down.y)
    }

    @Test func stopsAtTheMapEdgesOnBothAxes() {
        let farUp = MapCamera.clamped(position: CGPoint(x: 9000, y: 9000), content: content, zoom: 1, viewport: viewport)
        let farDown = MapCamera.clamped(position: CGPoint(x: -9000, y: -9000), content: content, zoom: 1, viewport: viewport)

        // Dragged as far down as it goes, the map's bottom edge rests on the
        // bottom inset; as far up, its top edge rests under the HUD band.
        #expect(farUp.y == MapCamera.bottomInset - content.minY)
        #expect(farDown.y == viewport.height - MapCamera.topInset - content.maxY)
        #expect(farUp.x == -content.minX)
        #expect(farDown.x == viewport.width - content.maxX)
    }

    @Test func centersAMapSmallerThanTheViewport() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 100)
        let dragged = MapCamera.clamped(position: CGPoint(x: 300, y: 300), content: small, zoom: 1, viewport: viewport)
        let untouched = MapCamera.clamped(position: .zero, content: small, zoom: 1, viewport: viewport)

        #expect(dragged == untouched)
        #expect(dragged.x == (viewport.width - small.width) / 2)
        let band = viewport.height - MapCamera.topInset - MapCamera.bottomInset
        #expect(dragged.y == MapCamera.bottomInset + (band - small.height) / 2)
    }

    @Test func scalesTheBoundsWithZoom() {
        let zoomedOut = MapCamera.clamped(position: CGPoint(x: 0, y: -9000), content: content, zoom: 0.5, viewport: viewport)

        #expect(zoomedOut.y == viewport.height - MapCamera.topInset - content.maxY * 0.5)
    }

    @Test func fitsTheWholeMapWithoutMagnifying() {
        let large = MapCamera.fittedZoom(content: CGSize(width: 4000, height: 3000), viewport: viewport)
        let small = MapCamera.fittedZoom(content: CGSize(width: 100, height: 80), viewport: viewport)

        #expect(large < 1)
        #expect(large >= MapCamera.minimumZoom)
        #expect(small == 1)
    }

    /// The map follows the fingers. AppKit hands over scroll deltas measured
    /// with y downwards while the scene has y upwards, so the vertical one is
    /// turned round and the horizontal one is not.
    @Test func panningFollowsTheFingersOnBothAxes() {
        let fingersDown = MapCamera.panTranslation(scrollingDeltaX: 0, scrollingDeltaY: 12)
        let fingersUp = MapCamera.panTranslation(scrollingDeltaX: 0, scrollingDeltaY: -12)
        let fingersRight = MapCamera.panTranslation(scrollingDeltaX: 9, scrollingDeltaY: 0)

        #expect(fingersDown.dy == -12)
        #expect(fingersUp.dy == 12)
        #expect(fingersRight.dx == 9)
    }

    @Test func keepsZoomWithinItsLimits() {
        #expect(MapCamera.clampZoom(0.001) == MapCamera.minimumZoom)
        #expect(MapCamera.clampZoom(40) == MapCamera.maximumZoom)
        #expect(MapCamera.clampZoom(1.5) == 1.5)
    }
}
