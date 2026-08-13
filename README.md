# Medieval

Native macOS 2D strategy game. The app uses SwiftUI for its shell and SpriteKit
for the game board. Game rules live in a UI-independent domain module.

## Architecture

`MedievalDomain` builds as a framework: game rules and state, with no UI
dependencies. The app links and embeds it rather than compiling those sources
itself, so the boundary is enforced by the compiler — app code reaches the
rules only through `import MedievalDomain` and only through the module's
`public` surface.

Every target owns one top-level folder of the same name, and each folder is
synchronized, so a new file dropped into it joins its target with no project
changes.

Content resources live in the framework's own bundle, reached through
`Bundle(for:)`, so the app and the tests read the same file.

## Structure

- `Medieval` — the app: entry point, navigation, SwiftUI views, SpriteKit scenes
  - `App` — entry point and navigation
  - `Persistence` — save-storage boundary
  - `Scenes` — SpriteKit board scenes
  - `UI` — SwiftUI views and the SpriteKit bridge
- `MedievalDomain` — deterministic game state and rules, without UI dependencies
- `MedievalTests` — unit tests for the domain
- `MedievalTestsUI` — UI tests that drive the running app

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), for the local
  checks: `brew install swiftformat`

## Development

Open `Medieval.xcodeproj` in Xcode and run the `Medieval` scheme.

Run all local checks—formatting, domain-rule tests, and an unsigned macOS Debug
build—from the repository root:

```sh
./Scripts/verify.sh
```

UI tests are not part of that gate: they need a signed build, drive the real
window server, and take minutes. Run them on their own:

```sh
./Scripts/verify-ui.sh
```

XCUITest inspects every running application, so a background app that never
settles can stall a launch test. Quit noisy background apps if one hangs.

To automatically apply the repository formatting rules:

```sh
swiftformat Medieval MedievalTests MedievalTestsUI
```

The supported macOS range and the compatibility-build command are documented in
[Docs/macOS-support.md](Docs/macOS-support.md).
