# Modern hex terrain assets

Production terrain sprites imported from `/Users/lysytsia/Documents/Codex/2026-08-12/r/assets/hexes`.

- `hex-terrain-*.png` — the eight gameplay terrain textures.
- `hex-river-edge-ne.png` — a reusable river-edge overlay rotated by the renderer in 60° steps.
- Source size: 384×432 px, pointy-top PNG with alpha transparency.
- Rendered size: 80×90 points. All map cells reuse these textures by terrain type.

The `hex-` prefix is intentional. Xcode flattens synchronized resources into the application bundle, so unique names prevent collisions with the legacy extracted sprites.
