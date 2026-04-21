import XCTest
@testable import ThreadGame

// MARK: - DifficultyManager Tests

final class DifficultyManagerTests: XCTestCase {

    // 1. Gap shrinks by ~5% per score milestone (every 5 points)
    func testGapShrinksByFivePercentPerScoreMilestone() {
        let gap0  = DifficultyManager.gapAngleDegrees(for: 0)
        let gap10 = DifficultyManager.gapAngleDegrees(for: 10)
        let gap20 = DifficultyManager.gapAngleDegrees(for: 20)

        XCTAssertLessThan(gap10, gap0, "gap at score 10 should be smaller than at score 0")
        XCTAssertLessThan(gap20, gap10, "gap at score 20 should be smaller than at score 10")

        // At score 10: 2 milestones of 5 → scale = 0.95^2 = 0.9025
        let expectedRatio = pow(0.95, 2.0)
        let actualRatio   = gap10 / gap0
        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.001,
            "gap should shrink by 0.95^milestones per score band")
    }

    // 2. Rotation speed hits documented thresholds exactly
    func testRotationSpeedIncreasesAtCorrectThresholds() {
        XCTAssertEqual(DifficultyManager.rotationSpeed(for: 0),  1.0, accuracy: 0.001, "score 0 → 1.0 rad/s")
        XCTAssertEqual(DifficultyManager.rotationSpeed(for: 4),  1.0, accuracy: 0.001, "score 4 → still 1.0")
        XCTAssertEqual(DifficultyManager.rotationSpeed(for: 5),  1.3, accuracy: 0.001, "score 5 → 1.3 rad/s")
        XCTAssertEqual(DifficultyManager.rotationSpeed(for: 10), 1.6, accuracy: 0.001, "score 10 → 1.6 rad/s")
        XCTAssertEqual(DifficultyManager.rotationSpeed(for: 30), 4.0, accuracy: 0.001, "score 30 → cap 4.0 rad/s")
        XCTAssertLessThanOrEqual(DifficultyManager.rotationSpeed(for: 999), DifficultyManager.maxRotationSpeed,
            "speed must never exceed maxRotationSpeed")
    }

    // 3. Gap never drops below the hard floor regardless of score
    func testGapNeverSmallerThanMinimum() {
        let extremeScores = [50, 100, 500, 1_000, 99_999]
        for score in extremeScores {
            let gap = DifficultyManager.gapAngleDegrees(for: score)
            XCTAssertGreaterThanOrEqual(gap, DifficultyManager.minimumGapDegrees,
                "gap \(gap)° is below minimum at score \(score)")
        }
    }

    // 9. Second ring appears at score 15, not before
    func testSecondRingThresholdFiresAtScore15() {
        XCTAssertEqual(DifficultyManager.ringCount(for: 0),   1, "score 0 → 1 ring")
        XCTAssertEqual(DifficultyManager.ringCount(for: 14),  1, "score 14 → 1 ring")
        XCTAssertEqual(DifficultyManager.ringCount(for: 15),  2, "score 15 → 2 rings")
        XCTAssertEqual(DifficultyManager.ringCount(for: 100), 2, "score 100 → 2 rings")
    }

    // 10. Collision bitmasks are all distinct with no overlapping bits
    func testCollisionCategoryBitmasksAreUnique() {
        let categories: [UInt32] = [
            CollisionCategories.ball,
            CollisionCategories.ringEdge,
            CollisionCategories.scoreZone
        ]
        XCTAssertEqual(Set(categories).count, categories.count,
            "all bitmask values must be distinct")
        XCTAssertEqual(CollisionCategories.ball & CollisionCategories.ringEdge, 0,
            "ball and ringEdge must share no bits")
        XCTAssertEqual(CollisionCategories.ball & CollisionCategories.scoreZone, 0,
            "ball and scoreZone must share no bits")
        XCTAssertEqual(CollisionCategories.ringEdge & CollisionCategories.scoreZone, 0,
            "ringEdge and scoreZone must share no bits")
    }
}

// MARK: - HighScoreStore Tests

final class HighScoreStoreTests: XCTestCase {

    var store: HighScoreStore!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.thread.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        store = HighScoreStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // 4. Best score updates when new score beats it
    func testHighScoreUpdatesOnBeat() {
        store.update(score: 47)
        XCTAssertEqual(store.bestScore, 47)

        store.update(score: 55)
        XCTAssertEqual(store.bestScore, 55)
    }

    // 5. Best score does NOT regress when new score is lower
    func testHighScoreDoesNotRegressOnLowerScore() {
        store.update(score: 47)
        store.update(score: 12)
        XCTAssertEqual(store.bestScore, 47, "bestScore must not decrease on a lower run")
    }

    // 6. Streak increments when played on consecutive calendar days
    func testStreakIncrementsOnConsecutiveDay() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.update(score: 5, now: yesterday)
        XCTAssertEqual(store.currentStreak, 1)

        store.update(score: 10, now: Date())
        XCTAssertEqual(store.currentStreak, 2, "streak should increment after consecutive day")
    }

    // 7. Streak resets to 1 after a gap of more than 1 day
    func testStreakResetsAfterGap() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        store.update(score: 5, now: threeDaysAgo)
        XCTAssertEqual(store.currentStreak, 1)

        store.update(score: 10, now: Date())
        XCTAssertEqual(store.currentStreak, 1, "streak should reset to 1 after a 3-day gap")
    }

    // 8. Unlock flag persists across a new HighScoreStore instance (same defaults suite)
    func testUnlockFlagPersistsAcrossStoreManagerInit() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "unlockPurchased")

        let newStore = HighScoreStore(defaults: defaults)
        XCTAssertTrue(newStore.isUnlocked,
            "isUnlocked must read persisted value from UserDefaults on init")
    }
}

// MARK: - GameState Integration Tests

final class GameStateTests: XCTestCase {

    // INT-1: Fresh state has correct default values
    func testGameStateStartsWithThreeLivesAndZeroScore() {
        let state = GameState()
        XCTAssertEqual(state.lives, 3)
        XCTAssertEqual(state.score, 0)
        XCTAssertFalse(state.isOver)
    }

    // INT-2: threadSuccess increments score and returns correct event
    func testThreadSuccessIncrementsScore() {
        let state = GameState()
        let event = state.threadSuccess()
        XCTAssertEqual(event, .threadSuccess)
        XCTAssertEqual(state.score, 1)
        XCTAssertEqual(state.lives, 3, "lives must not change on thread success")
    }

    // INT-3: ringHit decrements lives and transitions to gameOver after three hits
    func testRingHitDecreasesLivesAndTriggersGameOver() {
        let state = GameState()

        XCTAssertEqual(state.ringHit(), .ringHit)
        XCTAssertEqual(state.lives, 2)
        XCTAssertFalse(state.isOver)

        XCTAssertEqual(state.ringHit(), .ringHit)
        XCTAssertEqual(state.lives, 1)
        XCTAssertFalse(state.isOver)

        XCTAssertEqual(state.ringHit(), .gameOver)
        XCTAssertEqual(state.lives, 0)
        XCTAssertTrue(state.isOver)
    }

    // INT-4: Difficulty values update live as score increases
    func testDifficultyValuesUpdateWithScore() {
        let state = GameState()
        let initialGap   = state.currentGapDegrees
        let initialSpeed = state.currentRotationSpeed
        let initialRings = state.ringCount

        // Advance score to 15 to trigger second ring + tighter gap
        for _ in 0..<15 { state.threadSuccess() }

        XCTAssertLessThan(state.currentGapDegrees, initialGap,
            "gap should shrink after 15 successful threads")
        XCTAssertGreaterThan(state.currentRotationSpeed, initialSpeed,
            "speed should increase after 15 successful threads")
        XCTAssertGreaterThan(state.ringCount, initialRings,
            "ringCount should increase at score 15")
        XCTAssertEqual(state.ringCount, 2)
    }

    // INT-5: Events after isOver are safely ignored
    func testNoStateChangesAfterGameOver() {
        let state = GameState()
        state.ringHit(); state.ringHit(); state.ringHit()
        XCTAssertTrue(state.isOver)

        let eventAfterOver = state.threadSuccess()
        XCTAssertEqual(eventAfterOver, .gameOver,
            "threadSuccess after game over must return .gameOver and not change score")
        XCTAssertEqual(state.score, 0, "score must not change after game over")
    }
}
