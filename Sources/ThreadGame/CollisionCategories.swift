import Foundation

/// Bitmask constants for SpriteKit physics contact/collision filtering.
/// Each category must be a unique power of 2 so bitwise OR/AND comparisons work correctly.
public enum CollisionCategories {
    public static let ball: UInt32      = 0b00001  // 1
    public static let ringEdge: UInt32  = 0b00010  // 2
    public static let scoreZone: UInt32 = 0b00100  // 4
}
