import SpriteKit
import UIKit

/// SpriteKit scene that owns all visual and collision logic for a single Thread run.
///
/// Responsibilities:
/// - Draw the gold spinning ring as an arc SKShapeNode (gap is the missing sector).
/// - Move the white ball upward on tap via a physics impulse.
/// - Detect pass-through and ring-hit each frame in update() using angle math.
/// - Drive GameState and DifficultyManager for score/lives/difficulty.
/// - Call onGameOver(_:) when lives reach zero so ContentView can transition.
///
/// Collision detection is intentionally manual (angle math in update) rather than
/// physics contact delegates. Curved physics bodies on thin arcs are notoriously
/// inaccurate in SpriteKit at the speeds this game uses. Angle math on a known
/// radius is both cheaper and more reliable.
final class GameScene: SKScene {

    // MARK: - Callback

    /// Set by ContentView before the scene is presented.
    /// Called once on the main thread when lives reach zero.
    var onGameOver: ((Int) -> Void)?

    // MARK: - Game model

    private let gameState = GameState()

    // MARK: - Visual constants

    private let ringRadius: CGFloat = 100
    private let ballRadius: CGFloat = 10
    private let ringLineWidth: CGFloat = 8

    private let goldColor  = UIColor(red: 0.84, green: 0.65, blue: 0.37, alpha: 1)
    private let redColor   = UIColor(red: 0.9,  green: 0.2,  blue: 0.2,  alpha: 1)
    private let whiteColor = UIColor.white

    // MARK: - Node references

    private var ringNode: SKShapeNode!
    private var ballNode: SKShapeNode!
    private var scoreLabel: SKLabelNode!
    private var livesLabel: SKLabelNode!

    // MARK: - State tracking

    /// Tracks whether the ball was below the ring on the previous frame.
    /// Used to detect the upward crossing event once per throw.
    private var ballWasBelowRing: Bool = true

    /// True while we are in the post-hit flash cooldown so we don't double-count.
    private var isInHitCooldown: Bool = false

    /// True while we are waiting for the ring to rebuild after a successful thread.
    private var isRebuildingRing: Bool = false

    // MARK: - Ball physics

    private var ballStartY: CGFloat { -size.height * 0.35 }
    private var ballStartPosition: CGPoint { CGPoint(x: 0, y: ballStartY) }

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        setupRing()
        setupBall()
        setupHUD()
        updateHUD()
    }

    // MARK: - Node setup

    private func setupRing() {
        ringNode = makeRingNode(
            gapDegrees: gameState.currentGapDegrees,
            rotationSpeed: gameState.currentRotationSpeed
        )
        ringNode.position = CGPoint(x: 0, y: size.height * 0.05)
        addChild(ringNode)
    }

    private func makeRingNode(gapDegrees: Double, rotationSpeed: Double) -> SKShapeNode {
        let gapHalf = CGFloat(gapDegrees / 2) * .pi / 180
        // Gap center is at the top (pi/2). The arc is drawn from just past the gap
        // going clockwise around the full circle, stopping just before the gap reopens.
        let gapCenter = CGFloat.pi / 2
        let arcStart = gapCenter + gapHalf
        let arcEnd   = gapCenter - gapHalf

        let path = CGMutablePath()
        // clockwise: false means counter-clockwise in UIKit coords (y-axis flipped in SK),
        // but SpriteKit's coordinate system has y up, so this draws CW visually.
        path.addArc(
            center: .zero,
            radius: ringRadius,
            startAngle: arcStart,
            endAngle: arcEnd,
            clockwise: false
        )

        let node = SKShapeNode(path: path)
        node.strokeColor = goldColor
        node.fillColor = .clear
        node.lineWidth = ringLineWidth
        node.lineCap = .round
        node.name = "ring"

        // Continuous rotation. period = 2pi / radPerSec
        let period = (2.0 * Double.pi) / max(rotationSpeed, 0.01)
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: period)
        node.run(SKAction.repeatForever(spin), withKey: "spin")

        return node
    }

    private func setupBall() {
        ballNode = SKShapeNode(circleOfRadius: ballRadius)
        ballNode.fillColor = whiteColor
        ballNode.strokeColor = .clear
        ballNode.glowWidth = 3
        ballNode.name = "ball"

        ballNode.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
        guard let body = ballNode.physicsBody else { return }
        body.categoryBitMask    = CollisionCategories.ball
        body.collisionBitMask   = 0          // no physics collisions; we detect manually
        body.contactTestBitMask = 0
        body.allowsRotation     = false
        body.restitution        = 0
        body.friction           = 0
        body.linearDamping      = 0

        ballNode.position = ballStartPosition
        addChild(ballNode)
    }

    private func setupHUD() {
        scoreLabel = SKLabelNode(fontNamed: "Georgia-Bold")
        scoreLabel.fontSize = 48
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .top
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: 0, y: size.height * 0.5 - 60)
        scoreLabel.zPosition = 10
        addChild(scoreLabel)

        livesLabel = SKLabelNode(fontNamed: "Georgia")
        livesLabel.fontSize = 22
        livesLabel.fontColor = goldColor
        livesLabel.verticalAlignmentMode = .top
        livesLabel.horizontalAlignmentMode = .center
        livesLabel.position = CGPoint(x: 0, y: size.height * 0.5 - 120)
        livesLabel.zPosition = 10
        addChild(livesLabel)
    }

    private func updateHUD() {
        scoreLabel.text = "\(gameState.score)"
        livesLabel.text = String(repeating: "♥ ", count: gameState.lives)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gameState.isOver else { return }
        guard let body = ballNode.physicsBody else { return }
        // Reset vertical velocity so every tap gives a consistent arc.
        body.velocity = .zero
        body.applyImpulse(CGVector(dx: 0, dy: 32))
        ballWasBelowRing = ballNode.position.y < ringNode.position.y
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameState.isOver, !isRebuildingRing, !isInHitCooldown else { return }

        let ballY = ballNode.position.y
        let ringY = ringNode.position.y
        let ballIsNowBelowRing = ballY < ringY

        // Detect upward crossing (ball just passed ring plane going up).
        if ballWasBelowRing && !ballIsNowBelowRing {
            handleRingCrossing()
        }

        ballWasBelowRing = ballIsNowBelowRing

        // Reset ball when it falls well below start point.
        if ballY < ballStartY - 60 {
            resetBall()
        }
    }

    private func handleRingCrossing() {
        let inGap = isBallInGap()

        if inGap {
            handleThreadSuccess()
        } else {
            handleRingHit()
        }
    }

    // MARK: - Gap math

    /// Returns true if the ball's current angle relative to the ring center falls
    /// within the rotating gap sector.
    private func isBallInGap() -> Bool {
        let ringZRot = ringNode.zRotation
        let gapCenterWorld = CGFloat.pi / 2 + ringZRot

        let ballRelX = ballNode.position.x - ringNode.position.x
        let ballRelY = ballNode.position.y - ringNode.position.y
        let angle = atan2(ballRelY, ballRelX)

        var diff = angle - gapCenterWorld
        // Normalize to -pi...pi
        while diff > .pi  { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }

        let gapHalf = CGFloat(gameState.currentGapDegrees / 2) * .pi / 180
        return abs(diff) <= gapHalf
    }

    // MARK: - Event handling

    private func handleThreadSuccess() {
        let event = gameState.threadSuccess()
        guard event == .threadSuccess else { return }

        updateHUD()

        // Brief scale pulse on score label for feedback.
        let pop = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.08),
            SKAction.scale(to: 1.0, duration: 0.12)
        ])
        scoreLabel.run(pop)

        // Rebuild ring with updated difficulty after a short pause.
        isRebuildingRing = true
        run(SKAction.wait(forDuration: 0.4)) { [weak self] in
            self?.rebuildRing()
            self?.isRebuildingRing = false
        }
    }

    private func handleRingHit() {
        let event = gameState.ringHit()
        updateHUD()

        isInHitCooldown = true
        flashBallRed()

        run(SKAction.wait(forDuration: 0.6)) { [weak self] in
            guard let self else { return }
            self.ballNode.fillColor = self.whiteColor
            self.isInHitCooldown = false
            self.resetBall()

            if event == .gameOver {
                self.handleGameOver()
            }
        }
    }

    private func handleGameOver() {
        // Brief pause so the player can see the final state before transition.
        run(SKAction.wait(forDuration: 0.3)) { [weak self] in
            guard let self else { return }
            self.onGameOver?(self.gameState.score)
        }
    }

    // MARK: - Ring rebuild

    private func rebuildRing() {
        ringNode.removeFromParent()
        let newRing = makeRingNode(
            gapDegrees: gameState.currentGapDegrees,
            rotationSpeed: gameState.currentRotationSpeed
        )
        newRing.position = ringNode.position
        ringNode = newRing
        addChild(ringNode)
        resetBall()
    }

    // MARK: - Ball helpers

    private func resetBall() {
        ballNode.physicsBody?.velocity = .zero
        ballNode.position = ballStartPosition
        ballWasBelowRing = true
    }

    private func flashBallRed() {
        ballNode.fillColor = redColor
    }

    // MARK: - Scene resize

    override func didChangeSize(_ oldSize: CGSize) {
        // Reposition labels and ring when safe-area / rotation changes.
        scoreLabel?.position = CGPoint(x: 0, y: size.height * 0.5 - 60)
        livesLabel?.position = CGPoint(x: 0, y: size.height * 0.5 - 120)
        ringNode?.position   = CGPoint(x: 0, y: size.height * 0.05)

        // Ball start drifts with scene height; only move it if ball is at rest.
        if ballNode?.physicsBody?.velocity == .zero || ballWasBelowRing {
            ballNode?.position = ballStartPosition
        }
    }
}
