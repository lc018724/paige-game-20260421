# Thread — Game Prototype Plan
**Created:** 2026-04-21 01:00 CDT
**Kind:** Game app
**Build target:** 2 weeks
**Platform:** iOS first, SwiftUI + SpriteKit

---

## 1. One-Line Pitch

> Tap to fire your ball through the spinning ring's gap — before it rotates shut.

---

## 2. Core Loop / Core Flow (30 words)

Ball waits at bottom. Ring hovers above with a rotating gap. Tap fires the ball upward. Thread the gap = score. Hit the ring = life lost. Gap shrinks each round.

---

## 3. Differentiation

The market is crowded with line-drawing physics puzzles and color-matching tap games. Thread's mechanic — a stationary ring with a rotating gap — is distinct from all three nearest competitors:

**Competitor 1: Color Switch** (Fortafy Games, 2015 — 125M+ downloads, still top-10 casual)
Color Switch passes a bouncing ball through holes in rotating, color-segmented wheels. The player must match ball color to the correct segment of the wheel. Threading is incidental — color memorization is the core skill. Thread has zero color-matching complexity; the only skill is timing. Our gap is a single, visually unambiguous hole. No color required. A colorblind 10-year-old can play immediately.

**Competitor 2: Smash Hit** (Mediocre AB, 2014 — 100M+ downloads, runner format)
Smash Hit has a ball-throwing mechanic where you launch balls at glass obstacles in a first-person forward runner. Related "precise throw" feel but it is an infinite runner, not a precision timing game. No ring concept, no gap concept, no stacking difficulty. Thread is a pure reaction game — no running, no direction changes, no physics to read beyond "will the gap be open when the ball gets there."

**Competitor 3: Brain It On!** (Orbital Nine Games — 4M+ downloads, puzzle format)
Physics puzzle where you draw shapes to solve level objectives. Ball interaction exists but requires drawing. Drawing on a small screen is imprecise and frustrating. Thread requires only a single tap — perfect for one-handed play while lying down, commuting, or half-watching TV.

**The gap Thread fills:** No major iOS casual game owns the "rotating gap timing" mechanic. The closest analogs are carnival carnival midway games ("shoot the water gun into the clown's mouth when the mouth opens") — universally understood, physically satisfying, endlessly replayable. Thread is that, digitized.

---

## 4. Monetization

### Free Scope
- Endless mode: unlimited plays, global leaderboard, 3 lives per run
- 1 ball skin (white dot with glow trail)
- First 10 Puzzle levels (of 50)
- Basic sound pack (3 effects)
- No banner ads in the core gameplay view (one interstitial per 5 game-overs only)

### Paid Scope — Thread+ ($1.99, one-time unlock)
- All 50 hand-crafted Puzzle levels (with designer-tuned gap timing)
- 8 additional ball skins (comet, raindrop, star, ghost, pixel, prism, fire, neon)
- Daily Challenge mode: one shared level for all players worldwide, ranked leaderboard
- Expanded sound pack: 8 SFX variants, 2 background music tracks
- Remove the interstitial ad between game-overs
- Lifetime: one purchase, synced via iCloud across devices

### Pricing rationale
$1.99 one-time is the sweet spot for casual games. It signals "this is a real game" without the friction of a subscription. Maze Machina (comparable puzzle game) uses the identical model ($1.99 unlock, free intro). Users who reach game-over 5+ times are already engaged enough to convert. No ads in core gameplay preserves the feel.

---

## 5. Tech Stack

| Layer | Choice | Reason |
|-------|--------|--------|
| UI (menus, HUD, store) | SwiftUI | Declarative, fast to iterate, native sheets |
| Game rendering | SpriteKit | First-party, zero dependencies, handles physics + particles |
| Physics | SpriteKit SKPhysicsBody | Precise collision detection for ball/ring contact |
| Persistence | UserDefaults (wrapped) | Sufficient for scores/streak/unlock flag; no DB needed |
| Purchase | StoreKit 2 | Native, async/await, handles restore, receipt-free verification |
| Leaderboard | Game Center GKLeaderboard | Free, no backend, built into iOS |
| Audio | AVAudioPlayer pool | Lightweight, no 3rd party dependency |
| Testing | XCTest (unit) + XCUITest (UI) | Standard, no extra tooling |
| Minimum iOS | iOS 17 | SwiftUI features used: @Observable macro, .sheet(item:) |

No third-party dependencies. The entire game ships as a single Swift package with zero external pods or SPM packages. This keeps the 2-week build achievable by one developer.

---

## 6. File-Level Architecture

```
Thread/
├── ThreadApp.swift                     # @main App entry; sets up AppState as environment object
├── AppState.swift                      # @Observable: highScore, totalGames, unlockPurchased, selectedSkin
│
├── Game/
│   ├── GameScene.swift                 # SKScene subclass; owns ring, ball, HUD labels; drives game loop
│   ├── RingNode.swift                  # SKShapeNode subclass; draws ring with gap cutout; rotates via SKAction
│   ├── BallNode.swift                  # SKSpriteNode subclass; applies skin texture + particle trail emitter
│   ├── DifficultyManager.swift         # Pure value type; maps score -> gapAngleDegrees + rotationSpeed
│   └── CollisionCategories.swift       # UInt32 bitmask constants: ballCategory, ringEdgeCategory, gapCategory
│
├── Views/
│   ├── GameView.swift                  # SpriteView(scene:) wrapper; routes UITapGestureRecognizer to GameScene
│   ├── HomeView.swift                  # Title + Play button + Best score + "Thread+" button + skin picker
│   ├── HUDView.swift                   # SwiftUI overlay on GameView: score, lives (dot indicators), level badge
│   ├── ResultView.swift                # Shown on game-over: final score, personal best, Replay + Share buttons
│   ├── StoreView.swift                 # Sheet: feature list, price, Buy button, Restore Purchases button
│   └── SkinPickerView.swift            # Horizontal scroll of 9 ball options; locked ones show padlock badge
│
├── Store/
│   ├── StoreKitManager.swift           # @Observable; fetchProducts(), purchase(), restore(); sets AppState.unlockPurchased
│   └── Products.storekit               # Local StoreKit config for Simulator testing (productId: com.thread.plus)
│
├── Persistence/
│   ├── HighScoreStore.swift            # Thin UserDefaults wrapper: bestScore, totalRuns, currentStreak, lastPlayedDate
│   └── GameCenterManager.swift         # GKLocalPlayer auth + submitScore(to:) on game-over; silent fail if not authed
│
├── Audio/
│   ├── SoundManager.swift              # Singleton; preloads AVAudioPlayer pool; play(sound:) with overlap support
│   └── Sounds/
│       ├── thread.wav                  # Short satisfying "whoosh-ding" for successful threading
│       ├── miss.wav                    # Dull "thud" for hitting ring edge
│       ├── perfect.wav                 # Musical "sparkle" for hitting the exact center of the gap
│       └── levelup.wav                 # Ascending 3-note chime for difficulty increase event
│
├── Tests/
│   ├── ThreadTests/
│   │   └── ThreadTests.swift           # 10 unit tests (see section 7)
│   └── ThreadUITests/
│       └── ThreadUITests.swift         # 10 UI tests (see section 7)
│
└── Assets.xcassets/
    ├── AppIcon.imageset/               # Ring-with-gap icon at all required sizes
    ├── BallSkins/                      # 9 skin images: white_dot, comet, raindrop, star, ghost, pixel, prism, fire, neon
    └── Colors/                         # ringColor, backgroundGradientTop, backgroundGradientBottom, accentGold
```

**Key architecture decision:** SpriteKit runs the game loop; SwiftUI handles all menu/overlay/sheet UI. The GameScene publishes game state changes (score, lives, level) via a Combine publisher that the HUDView subscribes to. This keeps SpriteKit and SwiftUI decoupled — SwiftUI never touches SKNode, SpriteKit never touches a SwiftUI view.

The gap in the ring is implemented as a transparent wedge in the ring's SKShapeNode path, not as a physics hole. The ball's physics body has a contact test bitmask against only the solid ring edge. Passing through the transparent wedge fires no contact — which is detected by comparing the ball's Y position (cleared the ring) with no collision event having fired.

---

## 7. Testing Plan

### Unit Tests (ThreadTests.swift)

1. **testGapShrinksByFivePercentPerScoreMilestone**
   Assert DifficultyManager returns a gapAngleDegrees value 5% smaller at score=10 vs score=0, and at score=20 vs score=10.

2. **testRotationSpeedIncreasesAtCorrectThresholds**
   Assert rotationSpeed is 1.0 rad/s at score=0, 1.3 at score=5, 1.6 at score=10, and caps at 4.0 rad/s at score≥30.

3. **testGapNeverSmallerThanMinimum**
   Assert DifficultyManager.gapAngleDegrees never returns a value below 15 degrees regardless of score input (including score=9999).

4. **testHighScoreUpdatesOnBeat**
   Assert HighScoreStore.update(score:) sets bestScore when score > previous bestScore, and does NOT update when score < bestScore.

5. **testHighScoreDoesNotRegressOnLowerScore**
   Assert bestScore remains 47 after update(score: 12) when bestScore was already 47.

6. **testStreakIncrementsOnConsecutiveDay**
   Mock lastPlayedDate as yesterday; assert update() increments streak by 1.

7. **testStreakResetsAfterGap**
   Mock lastPlayedDate as 3 days ago; assert update() resets streak to 1.

8. **testUnlockFlagPersistsAcrossStoreManagerInit**
   Set unlockPurchased = true in UserDefaults; init a new StoreKitManager; assert it reads unlockPurchased = true from persistence.

9. **testSecondRingThresholdFiresAtScore15**
   Assert DifficultyManager.ringCount returns 1 for score 0-14 and 2 for score 15+.

10. **testCollisionCategoryBitmasksAreUnique**
    Assert ballCategory, ringEdgeCategory, and gapCategory are all distinct UInt32 values with no overlapping bits.

### UI Tests (ThreadUITests.swift)

1. **testLaunchShowsHomeScreen**
   App launches; assert staticText("Thread") and button("Play") exist and are hittable.

2. **testTapPlayTransitionsToGame**
   Tap Play; assert SpriteView is visible and HUD elements (score label, life dots) appear within 2 seconds.

3. **testThreeMissesTriggerResultView**
   Start game; programmatically trigger 3 miss events via accessibility notifications; assert ResultView ("Game Over" text) appears.

4. **testResultViewShowsNonzeroScore**
   Play until result; assert score label in ResultView shows a numeric value (regex [0-9]+).

5. **testReplayButtonResetsGame**
   Reach ResultView; tap Replay; assert HUD reappears with score=0 and 3 life dots filled.

6. **testHomeUnlockButtonOpensStoreSheet**
   From HomeView, tap "Thread+ $1.99"; assert StoreView sheet is presented (looks for "Unlock Thread+").

7. **testRestorePurchasesButtonExists**
   Open StoreView sheet; assert button("Restore Purchases") is hittable.

8. **testLockedSkinShowsPadlock**
   Before any purchase, open SkinPickerView; assert at least one skin cell contains an accessibility element labeled "locked".

9. **testUnlockedSkinIsSelectableAfterMockPurchase**
   Inject mock purchased state into AppState; open SkinPickerView; assert all 9 skin cells are hittable with no lock label.

10. **testGameCenterAuthPromptOnFirstLaunch**
    Delete app data; launch fresh; begin first game; assert GKAuthenticationViewController is presented (or its accessibility label appears) within 5 seconds.

---

## 8. Day 1 MVP Scope (what the 2:00 AM build actually ships)

The goal of Day 1 is a playable loop — nothing more.

**In scope:**
- `GameScene.swift`: ring renders, gap rotates at a constant speed, ball fires upward on tap, detects pass vs. hit
- `RingNode.swift`: single ring, single gap (30 degrees wide), constant clockwise rotation
- `BallNode.swift`: white circle, no trail, no skin system
- `DifficultyManager.swift`: hardcoded tier table (score 0-4 = large gap, 5-9 = medium, 10+ = small + faster)
- 3 lives, score increments on pass, resets on game-over
- `HomeView.swift`: title + Play button only, shows last score
- `ResultView.swift`: shows score, tap to play again
- `HighScoreStore.swift`: UserDefaults save/load of best score
- `SoundManager.swift`: thread.wav + miss.wav playing on events (no music)
- Compiles on real device, no crashes, no memory leaks

**Explicitly out of scope for Day 1:**
- StoreKit, Thread+ unlock, paid skins
- Puzzle levels (50 designed levels)
- Daily Challenge
- Game Center leaderboard
- Additional ball skins (SkinPicker wired in but disabled)
- perfect.wav, levelup.wav
- Second ring (multi-ring levels)
- Particle trail on ball
- Background music
- HUDView (score/lives shown as SpriteKit SKLabelNodes directly in scene)

**Definition of done for Day 1:** A fresh install on iPhone can play 10 consecutive games without a crash, the score displays correctly, and game-over correctly reduces lives. That is the bar.

---

## Notes for Build Week

- **SpriteKit gap detection approach:** Do not use a physics body for the gap itself. Instead, on each frame update, check if the ball has crossed the ring's Y plane without a collision event having fired in that frame. If ball.position.y > ring.position.y + ring.radius and no contact was reported: thread successful. This avoids complex curved physics body shapes.

- **Sound latency:** Pre-load both WAV files at app start into AVAudioPlayer. Do not init on first play event — SpriteKit's `didBeginContact` fires mid-frame and any `init` call there adds perceptible lag.

- **Ring shape:** Draw as CGPath: full circle minus a wedge arc for the gap. The wedge angle is `gapAngleDegrees` from DifficultyManager. Rotate the entire SKShapeNode node, not its path — node rotation is GPU-side and has zero CPU cost.

- **Day 1 build order:** GameScene → RingNode → BallNode → collision detection → HomeView → ResultView → HighScoreStore → sounds. Do not touch StoreKit until the game loop is stable.
