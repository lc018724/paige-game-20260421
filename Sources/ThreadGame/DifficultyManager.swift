import Foundation

/// Pure value-type difficulty calculator.
/// Maps score -> gap size, rotation speed, and ring count.
/// No state — all functions are deterministic for a given score.
public enum DifficultyManager {

    // MARK: - Constants

    /// Smallest gap the ring will ever show (degrees). Hard floor regardless of score.
    public static let minimumGapDegrees: Double = 15.0

    /// Starting gap size at score zero (degrees).
    public static let baseGapDegrees: Double = 60.0

    /// Starting rotation speed at score zero (radians/second).
    public static let baseRotationSpeed: Double = 1.0

    /// Rotation speed ceiling — never exceeds this regardless of score.
    public static let maxRotationSpeed: Double = 4.0

    /// Score at which a second ring appears.
    public static let secondRingScoreThreshold: Int = 15

    // MARK: - Gap size

    /// Returns the gap opening in degrees for the given score.
    /// Shrinks by 5% per score milestone (every 5 points), capped at minimumGapDegrees.
    public static func gapAngleDegrees(for score: Int) -> Double {
        let milestones = score / 5
        // pow(0.95, milestones) for very large milestones underflows to 0.0; max() handles it
        let scale = pow(0.95, Double(milestones))
        return max(baseGapDegrees * scale, minimumGapDegrees)
    }

    // MARK: - Rotation speed

    /// Returns the ring rotation speed in radians/second for the given score.
    /// Steps up at score thresholds 0, 5, 10, 15, 20, 25, 30+.
    public static func rotationSpeed(for score: Int) -> Double {
        let speed: Double
        switch score {
        case 0..<5:   speed = 1.0
        case 5..<10:  speed = 1.3
        case 10..<15: speed = 1.6
        case 15..<20: speed = 2.0
        case 20..<25: speed = 2.5
        case 25..<30: speed = 3.0
        default:      speed = 4.0
        }
        return min(speed, maxRotationSpeed)
    }

    // MARK: - Ring count

    /// Returns how many concentric rings are active for the given score.
    public static func ringCount(for score: Int) -> Int {
        return score >= secondRingScoreThreshold ? 2 : 1
    }
}
