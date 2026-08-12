# Medieval

Native macOS 2D strategy game. The app uses SwiftUI for its shell and SpriteKit
for the game board. Game rules live in a UI-independent domain module.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer

## Development

Open `Medieval.xcodeproj` in Xcode and run the `Medieval` scheme.

Run domain-rule tests from the repository root:

```sh
swift test
```
