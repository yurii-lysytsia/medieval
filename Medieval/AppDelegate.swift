import SwiftUI

@main
struct MedievalApp: App {
    @StateObject private var game = GameStore()

    var body: some Scene {
        WindowGroup {
            ContentView(game: game)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1_280, height: 800)
    }
}
