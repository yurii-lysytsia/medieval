# Medieval

Native macOS 2D strategy game. The app uses SwiftUI for its shell and SpriteKit
for the game board. Game rules live in a UI-independent domain module.

## Architecture

`Medieval/Domain` builds as the `MedievalDomain` framework: game rules and
state, with no UI dependencies. The app links and embeds it rather than
compiling those sources itself, so the boundary is enforced by the compiler —
app code reaches the rules only through `import MedievalDomain` and only
through the module's `public` surface.

The project has three targets: the `Medieval` app, the `MedievalDomain`
framework, and the `MedievalDomainTests` bundle. Each owns a synchronized
folder, so a new file dropped into `Medieval/Domain` or
`Tests/MedievalDomainTests` joins its target with no project changes.
`EXCLUDED_SOURCE_FILE_NAMES` keeps the domain folder out of the app target,
which sweeps `Medieval/` as a whole.

Content resources live in the framework's own bundle, reached through
`Bundle(for:)`, so the app and the tests read the same file.

## Structure

- `Medieval/App` — application entry point and navigation
- `Medieval/Domain` — deterministic game state and rules, without UI dependencies
- `Medieval/Persistence` — save-storage boundary
- `Medieval/Scenes` — SpriteKit board scenes
- `Medieval/UI` — SwiftUI views and SpriteKit bridge

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

To automatically apply the repository formatting rules:

```sh
swiftformat Medieval Tests
```

The supported macOS range and the compatibility-build command are documented in
[Docs/macOS-support.md](Docs/macOS-support.md).
