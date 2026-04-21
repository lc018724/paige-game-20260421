import Foundation

/// Events emitted by the game loop after each player input.
public enum GameEvent: Equatable {
    case threadSuccess   // Ball passed cleanly through the gap
    case ringHit         // Ball struck the solid ring edge
    case gameOver        // Lives exhausted after a ring hit
}

/// Observable game state for the Thread mechanic.
/// Pure logic — no SpriteKit or UIKit imports so it can be unit-tested anywhere.
public final class GameState {

    // MARK: - State

    public private(set) var score: Int = 0
    public private(set) var lives: Int
    public private(set) var isOver: Bool = false

    // MARK: - Init

    public init(lives: Int = 3) {
        self.lives = lives
    }

    // MARK: - Input handlers

    /// Call when the ball passes cleanly through the gap.
    @discardableResult
    public func threadSuccess() -> GameEvent {
        guard !isOver else { return .gameOver }
        score += 1
        return .threadSuccess
    }

    /// Call when the ball's physics body contacts the solid ring edge.
    @discardableResult
    public func ringHit() -> GameEvent {
        guard !isOver else { return .gameOver }
        lives -= 1
        if lives <= 0 {
            lives = 0
            isOver = true
            return .gameOver
        }
        return .ringHit
    }

    // MARK: - Derived difficulty values (delegated to DifficultyManager)

    /// Current gap opening in degrees, shrinks as score increases.
    public var currentGapDegrees: Double {
        DifficultyManager.gapAngleDegrees(for: score)
    }

    /// Current ring rotation speed in radians/second.
    public var currentRotationSpeed: Double {
        DifficultyManager.rotationSpeed(for: score)
    }

    /// Number of active rings for this score (1 or 2).
    public var ringCount: Int {
        DifficultyManager.ringCount(for: score)
    }
}
