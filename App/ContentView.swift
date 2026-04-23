import SwiftUI
import SpriteKit

/// Top-level state machine that routes between the three game screens:
/// menu, active play, and game-over result.
/// Keeping this as a thin coordinator means GameScene and the result screen
/// stay independently testable without the full navigation stack.
struct ContentView: View {

    /// Drives the three-state navigation without an enum overhead.
    @State private var isPlaying: Bool = false
    @State private var isGameOver: Bool = false
    @State private var finalScore: Int = 0
    @State private var bestScore: Int = HighScoreStore().bestScore

    /// Rebuilt on each play so GameScene starts completely fresh.
    @State private var currentScene: GameScene = ContentView.makeScene()

    var body: some View {
        ZStack {
            // Background always visible behind all states.
            Color(red: 0.04, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            if isGameOver {
                ResultView(
                    score: finalScore,
                    bestScore: bestScore,
                    onReplay: startNewGame
                )
                .transition(.opacity)
            } else if isPlaying {
                GameSceneView(scene: currentScene)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                MenuView(bestScore: bestScore, onPlay: startNewGame)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
        .animation(.easeInOut(duration: 0.25), value: isGameOver)
        .onAppear {
            bestScore = HighScoreStore().bestScore
        }
    }

    // MARK: - Private helpers

    private func startNewGame() {
        let scene = ContentView.makeScene()
        scene.onGameOver = { score in
            let store = HighScoreStore()
            store.update(score: score)
            bestScore = store.bestScore
            finalScore = score
            withAnimation {
                isPlaying = false
                isGameOver = true
            }
        }
        currentScene = scene
        withAnimation {
            isGameOver = false
            isPlaying = true
        }
    }

    private static func makeScene() -> GameScene {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }
}

// MARK: - GameSceneView

/// Wraps SpriteView so the rest of the view hierarchy stays SwiftUI-native.
/// Using a separate struct avoids re-creating the SpriteView whenever ContentView rebuilds.
private struct GameSceneView: View {
    let scene: GameScene

    var body: some View {
        SpriteView(scene: scene)
    }
}

// MARK: - MenuView

/// Title screen shown before first play and after dismissing the result screen.
private struct MenuView: View {
    let bestScore: Int
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("THREAD")
                .font(.system(size: 56, weight: .black, design: .serif))
                .foregroundStyle(Color(red: 0.84, green: 0.65, blue: 0.37))
                .tracking(12)

            Text("tap to fire through the gap")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(2)

            Spacer()

            if bestScore > 0 {
                Text("BEST  \(bestScore)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(4)
            }

            Button(action: onPlay) {
                Text("PLAY")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.07))
                    .frame(width: 180, height: 56)
                    .background(Color(red: 0.84, green: 0.65, blue: 0.37))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
            }

            Spacer().frame(height: 60)
        }
    }
}

// MARK: - ResultView

/// Game-over screen. Shows final score, personal best, and a replay button.
struct ResultView: View {
    let score: Int
    let bestScore: Int
    let onReplay: () -> Void

    private var isNewBest: Bool { score >= bestScore && score > 0 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("GAME OVER")
                .font(.system(size: 32, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .tracking(8)

            Text("\(score)")
                .font(.system(size: 96, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.84, green: 0.65, blue: 0.37))

            if isNewBest {
                Text("NEW BEST")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.84, green: 0.65, blue: 0.37))
                    .tracking(6)
            } else if bestScore > 0 {
                Text("BEST  \(bestScore)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(4)
            }

            Spacer()

            Button(action: onReplay) {
                Text("PLAY AGAIN")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.07))
                    .frame(width: 200, height: 56)
                    .background(Color(red: 0.84, green: 0.65, blue: 0.37))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
            }

            Spacer().frame(height: 60)
        }
    }
}
