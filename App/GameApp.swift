import SwiftUI

/// Entry point for the Thread game app.
/// Sets dark colour scheme globally so the ink-dark background reads correctly
/// on every device without requiring per-view overrides.
@main
struct ThreadGameApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
