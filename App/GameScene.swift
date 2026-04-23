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
    private var comboLabel: SKLabelNode!

    // MARK: - Camera

    /// Camera node for screen shake effect on ring hit.
    private var gameCamera: SKCameraNode!

    // MARK: - Second ring

    /// Optional second ring that appears at score 15+.
    private var ring2Node: SKShapeNode?

    /// Tracks whether ball was below ring2 on the previous frame.
    private var ring2WasBelowBall: Bool = false

    /// True once ball has cleanly passed ring1 on the current throw (two-ring mode).
    private var ring1Cleared: Bool = false

    // MARK: - First-run tutorial

    /// True on the very first session before the player has ever fired.
    /// Persisted in UserDefaults so the hint disappears permanently after one tap.
    private var isFirstRun: Bool = !UserDefaults.standard.bool(forKey: "hasPlayedOnce")

    // MARK: - State tracking

    /// Tracks whether the ball was below the ring on the previous frame.
    /// Used to detect the upward crossing event once per throw.
    private var ballWasBelowRing: Bool = true

    /// True while we are in the post-hit flash cooldown so we don't double-count.
    private var isInHitCooldown: Bool = false

    /// True while we are waiting for the ring to rebuild after a successful thread.
    private var isRebuildingRing: Bool = false

    // MARK: - Trail state

    /// True while the ball is actively in flight (between tap and reset).
    private var ballInFlight: Bool = false

    /// Alternates 0/1 each frame to emit trail dots every other frame.
    private var trailFrameSkip: Int = 0

    // MARK: - Combo state

    /// Number of consecutive successful threads without a ring hit.
    private var consecutiveThreads: Int = 0

    /// Score multiplier derived from the current streak (1, 2, or 3).
    private var comboMultiplier: Int = 1

    // MARK: - Milestone labels

    /// Maps score values to brief milestone text shown on screen.
    private let milestoneLabels: [Int: String] = [
        5: "SHARP",
        10: "PRECISE",
        20: "RELENTLESS",
        30: "INHUMAN"
    ]

    // MARK: - Haptics

    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Ball physics

    private var ballStartY: CGFloat { -size.height * 0.35 }
    private var ballStartPosition: CGPoint { CGPoint(x: 0, y: ballStartY) }

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        setupCamera()
        setupRing()
        setupBall()
        setupHUD()
        updateHUD()

        impactHeavy.prepare()
        impactLight.prepare()
    }

    // MARK: - Camera setup

    private func setupCamera() {
        gameCamera = SKCameraNode()
        gameCamera.position = .zero
        addChild(gameCamera)
        camera = gameCamera
    }

    // MARK: - Screen shake

    private func shakeCamera() {
        let d: CGFloat = 9
        gameCamera.run(SKAction.sequence([
            SKAction.moveBy(x: -d, y: d * 0.5, duration: 0.04),
            SKAction.moveBy(x: d * 2, y: -d, duration: 0.04),
            SKAction.moveBy(x: -d, y: d * 0.5, duration: 0.04),
            SKAction.move(to: .zero, duration: 0.04)
        ]))
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

        // Gap-end indicator dots so the player always sees where the opening is.
        for angle in [arcStart, arcEnd] {
            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = goldColor.withAlphaComponent(0.9)
            dot.strokeColor = .clear
            dot.position = CGPoint(
                x: cos(angle) * ringRadius,
                y: sin(angle) * ringRadius
            )
            node.addChild(dot)
        }

        // Speed blur streaks at high rotation speeds.
        if rotationSpeed >= 2.5 {
            for i in 0..<3 {
                let streakAngle = CGFloat(i) * (2 * .pi / 3)
                let innerR = ringRadius - 14
                let outerR = ringRadius + 14
                let streak = SKShapeNode()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: cos(streakAngle) * innerR, y: sin(streakAngle) * innerR))
                p.addLine(to: CGPoint(x: cos(streakAngle) * outerR, y: sin(streakAngle) * outerR))
                streak.path = p
                streak.strokeColor = goldColor.withAlphaComponent(0.35)
                streak.lineWidth = 2
                node.addChild(streak)
            }
        }

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
        startIdlePulse()
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

        comboLabel = SKLabelNode(fontNamed: "Georgia-Bold")
        comboLabel.fontSize = 16
        comboLabel.fontColor = goldColor
        comboLabel.verticalAlignmentMode = .top
        comboLabel.horizontalAlignmentMode = .center
        comboLabel.position = CGPoint(x: 0, y: size.height * 0.5 - 155)
        comboLabel.alpha = 0
        comboLabel.zPosition = 10
        addChild(comboLabel)

        // First-run hint: pulsing label near the ball so new players know what to do.
        if isFirstRun {
            let hint = SKLabelNode(fontNamed: "Georgia")
            hint.name = "hintLabel"
            hint.text = "TAP TO FIRE"
            hint.fontSize = 15
            hint.fontColor = UIColor.white.withAlphaComponent(0.55)
            hint.position = CGPoint(x: 0, y: ballStartY - 40)
            hint.zPosition = 15
            hint.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.2, duration: 0.8),
                SKAction.fadeAlpha(to: 0.55, duration: 0.8)
            ])))
            addChild(hint)
        }
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

        // Dismiss the first-run hint permanently on the player's very first tap.
        if isFirstRun {
            isFirstRun = false
            UserDefaults.standard.set(true, forKey: "hasPlayedOnce")
            childNode(withName: "hintLabel")?.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
        }

        // Cancel idle pulse before launching.
        ballNode.removeAction(forKey: "idlePulse")
        ballNode.setScale(1.0)

        // Reset vertical velocity so every tap gives a consistent arc.
        body.velocity = .zero
        SoundEngine.shared.playTap()
        body.applyImpulse(CGVector(dx: 0, dy: 32))
        ballWasBelowRing = ballNode.position.y < ringNode.position.y
        ballInFlight = true
        ring1Cleared = false

        // Also reset ring2 crossing state.
        if ring2Node != nil {
            ring2WasBelowBall = ballNode.position.y < (ring2Node?.position.y ?? 0)
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameState.isOver, !isRebuildingRing, !isInHitCooldown else { return }

        let ballY = ballNode.position.y
        let ringY = ringNode.position.y
        let ballIsNowBelowRing = ballY < ringY

        // Detect upward crossing (ball just passed ring1 plane going up).
        if ballWasBelowRing && !ballIsNowBelowRing {
            handleRing1Crossing()
        }

        ballWasBelowRing = ballIsNowBelowRing

        // Track ring2 crossing if it exists.
        if let r2 = ring2Node {
            let ballIsNowBelowRing2 = ballY < r2.position.y
            if ring2WasBelowBall && !ballIsNowBelowRing2 {
                handleRing2Crossing()
            }
            ring2WasBelowBall = ballIsNowBelowRing2
        }

        // Spawn trail dots while ball is moving upward in flight.
        if ballInFlight, (ballNode.physicsBody?.velocity.dy ?? 0) > 10 {
            trailFrameSkip = (trailFrameSkip + 1) % 2
            if trailFrameSkip == 0 {
                spawnTrailDot()
            }
        }

        // Reset ball when it falls well below start point.
        if ballY < ballStartY - 60 {
            resetBall()
        }
    }

    // MARK: - Ring crossing handlers

    private func handleRing1Crossing() {
        let inGap = isBallInGap(for: ringNode)

        if gameState.ringCount >= 2 && ring2Node != nil {
            // Two-ring mode: ring1 crossing only clears the first gate.
            if inGap {
                ring1Cleared = true
            } else {
                handleRingHit()
            }
        } else {
            // Single-ring mode: original behavior.
            if inGap {
                handleThreadSuccess()
            } else {
                handleRingHit()
            }
        }
    }

    private func handleRing2Crossing() {
        guard let r2 = ring2Node else { return }
        let inGap = isBallInGap(for: r2)

        if ring1Cleared && inGap {
            handleThreadSuccess()
        } else {
            handleRingHit()
        }
        ring1Cleared = false
    }

    // MARK: - Gap math

    /// Returns true if the ball's current angle relative to the given ring center
    /// falls within the rotating gap sector.
    private func isBallInGap(for ring: SKShapeNode) -> Bool {
        let ringZRot = ring.zRotation
        let gapCenterWorld = CGFloat.pi / 2 + ringZRot
        let relX = ballNode.position.x - ring.position.x
        let relY = ballNode.position.y - ring.position.y
        let angle = atan2(relY, relX)

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

        // Update combo streak before any visual work.
        consecutiveThreads += 1
        let prevMultiplier = comboMultiplier
        if consecutiveThreads >= 6 {
            comboMultiplier = 3
        } else if consecutiveThreads >= 3 {
            comboMultiplier = 2
        } else {
            comboMultiplier = 1
        }

        impactLight.impactOccurred()
        SoundEngine.shared.playSuccess()
        updateHUD()

        // Show or refresh the combo label.
        if comboMultiplier > 1 {
            comboLabel.text = "COMBO x\(comboMultiplier)"
            let hitNewTier = comboMultiplier > prevMultiplier
            if hitNewTier {
                // Scale pop when a new tier is reached.
                comboLabel.alpha = 1
                comboLabel.setScale(1.5)
                comboLabel.run(SKAction.sequence([
                    SKAction.scale(to: 1.0, duration: 0.15),
                ]))
            } else {
                comboLabel.run(SKAction.fadeIn(withDuration: 0.1))
            }
        }

        // Check for milestone text.
        if let milestoneText = milestoneLabels[gameState.score] {
            showMilestone(milestoneText)
        }

        // Brief scale pulse on score label for feedback.
        let pop = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.08),
            SKAction.scale(to: 1.0, duration: 0.12)
        ])
        scoreLabel.run(pop)

        // If this score beats the stored best, briefly turn the label gold as a preview.
        if gameState.score > HighScoreStore().bestScore {
            scoreLabel.fontColor = goldColor
        }

        // Gold burst particles from ring center.
        spawnSuccessBurst()

        // Flash ring white then back to gold before rebuilding.
        ringNode.run(SKAction.sequence([
            SKAction.run { [weak self] in self?.ringNode.strokeColor = .white },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { [weak self] in self?.ringNode.strokeColor = self?.goldColor ?? .white }
        ]))

        updateBackground()

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

        // Tear down combo on any ring hit.
        consecutiveThreads = 0
        comboMultiplier = 1
        comboLabel.run(SKAction.fadeOut(withDuration: 0.2))

        impactHeavy.impactOccurred()
        SoundEngine.shared.playHit()
        shakeCamera()
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
        SoundEngine.shared.playGameOver()
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
        newRing.position = CGPoint(x: 0, y: size.height * 0.05)
        ringNode = newRing
        addChild(ringNode)

        // Remove existing ring2 before potentially rebuilding it.
        ring2Node?.removeFromParent()
        ring2Node = nil

        // If score warrants a second ring, build it above ring1.
        if gameState.ringCount >= 2 {
            let speed2 = gameState.currentRotationSpeed * 0.7
            let period2 = (2.0 * Double.pi) / max(speed2, 0.01)
            let r2 = makeRingNode(
                gapDegrees: gameState.currentGapDegrees,
                rotationSpeed: speed2
            )
            // Override the spin to go counterclockwise.
            r2.removeAction(forKey: "spin")
            let ccwSpin = SKAction.rotate(byAngle: -.pi * 2, duration: period2)
            r2.run(SKAction.repeatForever(ccwSpin), withKey: "spin")
            r2.position = CGPoint(x: 0, y: ringNode.position.y + 90)
            ring2Node = r2
            addChild(r2)
            ring2WasBelowBall = ballNode.position.y < r2.position.y
        }

        resetBall()
    }

    // MARK: - Ball helpers

    private func resetBall() {
        ballNode.physicsBody?.velocity = .zero
        ballNode.position = ballStartPosition
        ballWasBelowRing = true
        ballInFlight = false
        ring1Cleared = false
        if let r2 = ring2Node {
            ring2WasBelowBall = ballNode.position.y < r2.position.y
        }
        // Restore score label color to white after any gold new-best flash.
        scoreLabel.fontColor = whiteColor
        startIdlePulse()
    }

    private func flashBallRed() {
        ballNode.fillColor = redColor
    }

    // MARK: - Idle pulse

    /// Gentle scale pulse to show the ball is ready to fire.
    private func startIdlePulse() {
        ballNode.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.25, duration: 0.8),
            SKAction.scale(to: 1.0,  duration: 0.8)
        ])), withKey: "idlePulse")
    }

    // MARK: - Trail particles

    private func spawnTrailDot() {
        let r = ballRadius * CGFloat.random(in: 0.25...0.55)
        let dot = SKShapeNode(circleOfRadius: r)
        dot.fillColor = UIColor.white.withAlphaComponent(CGFloat.random(in: 0.4...0.7))
        dot.strokeColor = .clear
        dot.position = ballNode.position
        dot.zPosition = ballNode.zPosition - 1
        addChild(dot)
        dot.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Success burst

    /// Emits 12 small gold particles radiating outward from the ring center.
    private func spawnSuccessBurst() {
        let center = ringNode.position
        for _ in 0..<12 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            p.fillColor = goldColor
            p.strokeColor = .clear
            p.position = center
            addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist  = CGFloat.random(in: 50...120)
            let dx = cos(angle) * dist
            let dy = sin(angle) * dist
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4),
                    SKAction.scale(to: 0.1, duration: 0.4)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Milestone text

    private func showMilestone(_ text: String) {
        let label = SKLabelNode(fontNamed: "Georgia-Bold")
        label.text = text
        label.fontSize = 20
        label.fontColor = goldColor
        label.position = CGPoint(x: 0, y: size.height * 0.5 - 160)
        label.alpha = 0
        label.zPosition = 20
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.wait(forDuration: 0.6),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.4),
                SKAction.moveBy(x: 0, y: 20, duration: 0.4)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Dynamic background

    /// Slowly darkens the background blue channel to signal increasing difficulty.
    private func updateBackground() {
        let base: CGFloat = 0.04
        let extra = CGFloat(min(gameState.score, 30)) / 30.0 * 0.025
        backgroundColor = UIColor(red: base - extra * 0.5,
                                  green: base - extra * 0.5,
                                  blue: base + extra * 0.2 - extra,
                                  alpha: 1)
    }

    // MARK: - Scene resize

    override func didChangeSize(_ oldSize: CGSize) {
        // Reposition labels and ring when safe-area / rotation changes.
        scoreLabel?.position  = CGPoint(x: 0, y: size.height * 0.5 - 60)
        livesLabel?.position  = CGPoint(x: 0, y: size.height * 0.5 - 120)
        comboLabel?.position  = CGPoint(x: 0, y: size.height * 0.5 - 155)
        ringNode?.position    = CGPoint(x: 0, y: size.height * 0.05)

        // Reposition ring2 if it exists.
        if let r2 = ring2Node, let rn = ringNode {
            r2.position = CGPoint(x: 0, y: rn.position.y + 90)
        }

        // Ball start drifts with scene height; only move it if ball is at rest.
        if ballNode?.physicsBody?.velocity == .zero || ballWasBelowRing {
            ballNode?.position = ballStartPosition
        }
    }
}
