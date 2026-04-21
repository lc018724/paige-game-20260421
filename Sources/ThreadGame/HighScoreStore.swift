import Foundation

/// Thin UserDefaults wrapper for persisting scores, streaks, and unlock state.
/// Accepts an injected UserDefaults instance so tests can use an isolated suite.
public final class HighScoreStore {

    // MARK: - Keys

    private let bestScoreKey      = "bestScore"
    private let totalRunsKey      = "totalRuns"
    private let streakKey         = "currentStreak"
    private let lastPlayedKey     = "lastPlayedDate"
    private let unlockKey         = "unlockPurchased"

    // MARK: - Storage

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read

    public var bestScore: Int {
        defaults.integer(forKey: bestScoreKey)
    }

    public var currentStreak: Int {
        defaults.integer(forKey: streakKey)
    }

    public var totalRuns: Int {
        defaults.integer(forKey: totalRunsKey)
    }

    /// Whether the Thread+ one-time unlock has been purchased and persisted.
    public var isUnlocked: Bool {
        get { defaults.bool(forKey: unlockKey) }
        set { defaults.set(newValue, forKey: unlockKey) }
    }

    // MARK: - Write

    /// Call this after every game-over. Updates best score, run count, and daily streak.
    /// - Parameters:
    ///   - score: The score from the completed run.
    ///   - now:   The current date. Defaults to `Date()`. Injectable for testing.
    public func update(score: Int, now: Date = Date()) {
        // Best score
        if score > bestScore {
            defaults.set(score, forKey: bestScoreKey)
        }

        // Total runs
        defaults.set(totalRuns + 1, forKey: totalRunsKey)

        // Streak: compare calendar days (normalise to midnight to avoid DST edge cases)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        if let lastPlayedDate = defaults.object(forKey: lastPlayedKey) as? Date {
            let lastStart = calendar.startOfDay(for: lastPlayedDate)
            let days = calendar.dateComponents([.day], from: lastStart, to: todayStart).day ?? 0
            switch days {
            case 1:       defaults.set(currentStreak + 1, forKey: streakKey)  // consecutive day
            case let d where d > 1: defaults.set(1, forKey: streakKey)        // gap — reset
            default:      break                                                 // same day — no change
            }
        } else {
            defaults.set(1, forKey: streakKey)  // first ever run
        }

        defaults.set(now, forKey: lastPlayedKey)
    }
}
