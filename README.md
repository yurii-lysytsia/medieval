# Medieval

Native macOS 2D strategy game. The app uses SwiftUI for its shell and SpriteKit
for the game board. Game rules live in a UI-independent domain module.

## Architecture

`Medieval/Domain` is the `MedievalDomain` Swift package: game rules and state,
with no UI dependencies. The app target links it as a package product rather
than compiling those sources itself, so the boundary is enforced by the
compiler — app code reaches the rules only through `import MedievalDomain` and
only through the module's `public` surface.

`EXCLUDED_SOURCE_FILE_NAMES` keeps `Medieval/Domain` out of the app target's
synchronized file group. New rule files dropped into that folder join the
package automatically and need no project changes.

## Structure

- `Medieval/App` — application entry point and navigation
- `Medieval/Domain` — deterministic game state and rules, without UI dependencies
- `Medieval/Persistence` — save-storage boundary
- `Medieval/Scenes` — SpriteKit board scenes
- `Medieval/UI` — SwiftUI views and SpriteKit bridge

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer

## Development

Open `Medieval.xcodeproj` in Xcode and run the `Medieval` scheme.

Run domain-rule tests from the repository root:

```sh
swift test
```
