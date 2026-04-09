# Pointer Movement Anti-Bot Research Notes

This note captures a focused round of public research on pointer-movement bot detection and translates the findings into high-level guidance for `macos-cua`.

The goal here is not to claim a bypass strategy. The goal is to understand what public sources suggest modern detectors look for, why naive “humanized cursor” techniques still fail, and what that implies for a future unified movement engine inside `macos-cua`.

## Scope

This document is intentionally limited to movement signals:

- pointer trajectories
- timing and event density
- target acquisition behavior
- movement-related behavioral biometrics

It does not cover:

- browser fingerprinting
- network-layer replay or request shaping
- DOM semantics
- non-movement fraud signals

## Research Queries

The following `grok-search` queries were used during this research pass:

```text
bot detection mouse movement behavioral biometrics
mouse dynamics bot detection pointer trajectory website fraud
human mouse movement bot detection overshoot jitter acceleration
DataDome mouse movement bot detection behavioral biometrics
Arkose Labs mouse movement behavioral biometrics bot detection
WindMouse human mouse movement algorithm overshoot jitter
minimum jerk mouse movement human computer interaction bot detection
Fitts law mouse movement bot detection human trajectory
SigmaDrift mouse movement human like trajectory bot detection
```

## Central Conclusion

The strongest common theme across public research and vendor material is that modern movement detection is based on **movement-model consistency**, not just whether the cursor path contains visible randomness.

Simple heuristics such as “add a little jitter” or “use a curved path” are not enough. What appears to matter is whether the full trajectory, timing, correction pattern, and click acquisition behavior are statistically consistent with real human pointing behavior.

Movement is also only one signal among many. Public materials from anti-bot vendors consistently frame pointer dynamics as a valuable passive signal, not a complete decision system on its own.

## What Public Detection Logic Appears To Look For

### Geometry

Detectors appear to examine whether the path itself looks too idealized or too efficient.

Observable signals likely include:

- path efficiency: straight-line distance vs actual path length
- curvature and curvature change
- angle distribution and direction changes
- whether trajectories are too straight, too perfectly smooth, or too geometrically repeatable
- whether endpoints are acquired with unrealistic precision

Human movement is usually less efficient than a scripted trajectory. Even when people are moving directly to a target, their paths typically contain mild curvature and small directional corrections.

### Kinematics

Public discussions and academic summaries strongly emphasize velocity, acceleration, and jerk.

Observable signals likely include:

- speed variation across the full trajectory
- acceleration and deceleration patterns
- jerk and higher-order smoothness features
- whether the pointer slows down naturally near the target
- whether the trajectory exhibits a roughly bell-shaped velocity profile

The main anti-bot point is that constant-speed paths, instantaneous jumps, and simplistic easing curves are easy to separate from human motion. Human pointing tends to show a ballistic phase followed by controlled deceleration.

### Correction And Target Acquisition

Human acquisition of a target is often not a single perfect landing.

Observable signals likely include:

- slight overshoot
- one or more corrective sub-movements
- short settle behavior near the endpoint
- small endpoint adjustments before click

The key point is not that humans always overshoot. It is that human targeting often contains imperfect correction. A system that always lands perfectly with no late adjustments can look artificial, but a system that always overshoots in the same way can also look artificial.

### Timing And Sampling

Detectors do not only inspect geometry. They also appear to look at the time structure of the event stream.

Observable signals likely include:

- movement duration
- inter-event timing
- event density
- whether sampling intervals are too uniform
- whether timing scales sensibly with target distance and difficulty

Public material on Fitts’ Law and motor-control-inspired modeling suggests that movement time should correlate with task difficulty. Farther and smaller targets usually take longer to acquire. A fixed-duration cursor policy across all movements is a weak fit for human behavior.

### Cross-Session Consistency

Vendor descriptions and research discussion both imply that per-trajectory realism is not enough if the same synthetic pattern repeats across sessions.

Observable signals likely include:

- repeated path templates
- repeated timing templates
- stable noise amplitudes that do not scale with movement context
- the same endpoint behavior regardless of target size or distance

This matters because many “humanized cursor” implementations still generate statistically narrow families of motion, even when any single example looks plausible by eye.

## Why Naive Cursor Humanization Still Fails

Several common implementation styles appear weak against movement-based detection.

### Straight Line With Easing

This is better than teleportation, but still looks too idealized.

Typical problems:

- path has near-zero curvature
- acceleration profile is too simple
- no realistic correction phase
- timing often becomes fixed and template-like

### Bézier Path Plus Light Noise

This improves path shape but often remains too designed.

Typical problems:

- curves look decorative rather than motor-driven
- noise is often independent per point instead of behaviorally structured
- endpoint acquisition is still too perfect
- repeated runs can share obvious path-family characteristics

### Unstructured Random Jitter

Adding arbitrary jitter can make trajectories look worse, not better.

Typical problems:

- high-frequency wobble appears throughout the movement
- no convergence near target
- noise amplitude is disconnected from distance and task difficulty
- movement looks “randomized” rather than human

### Fixed Timing Profiles

Even plausible geometry can look artificial if time behavior is rigid.

Typical problems:

- identical movement duration across different distances
- evenly spaced events
- fixed delay before click
- identical double-click interval every time

## Public Algorithm Families And Their Limits

### Straight Or Eased Interpolation

This is the weakest baseline.

Pros:

- simple to implement
- predictable and stable

Cons:

- too direct
- too smooth in the wrong way
- poor correction behavior

### Bézier Plus Noise

This is visually nicer than a straight line, but not necessarily more human in a statistical sense.

Pros:

- easy to shape
- better visual curvature

Cons:

- can still be overly geometric
- often fails to produce realistic target acquisition
- easy to overfit into a recognizable template family

### WindMouse

WindMouse is a well-known physics-inspired heuristic using a target pull and random “wind”.

Pros:

- better than straight lines
- naturally creates curved paths
- can produce overshoot and corrections

Cons:

- often produces jagged velocity profiles
- can become too jittery if not tightly tuned
- still reads as a heuristic generator rather than a motor-control model

The main takeaway is that WindMouse is useful as a historical reference and can outperform naive methods, but it is not obviously the right default target for a modern movement engine.

### Minimum-Jerk Plus Bounded Noise

This appears to be a stronger engineering direction for realistic motion.

Pros:

- aligns better with human motor-control literature
- naturally supports bell-shaped velocity
- easier to keep smooth without becoming rigid

Cons:

- pure minimum-jerk can become too idealized
- still needs a separate model for correction, endpoint settle, and controlled noise

This approach looks like a better foundation than WindMouse if the goal is a unified movement engine rather than a quick heuristic patch.

### Sigma-Lognormal / SigmaDrift-Style Models

These models attempt to synthesize motion from stronger biomechanical assumptions, often including ballistic and corrective sub-movements explicitly.

Pros:

- closest to the research framing of real pointing behavior
- supports more realistic sub-movement structure
- better theoretical match for endpoint correction

Cons:

- highest implementation complexity
- more parameters and more tuning burden
- likely too heavy for an initial `macos-cua` movement refactor

This family is best treated as a longer-term reference model rather than the first implementation target.

## Reverse-Engineered Requirements For `macos-cua`

If `macos-cua` wants movement behavior that is less mechanically obvious, the movement layer should satisfy a few high-level requirements.

### One Unified Movement Engine

All pointer-moving commands should use the same internal movement model:

- `move`
- `click`
- `double-click`
- future `drag`

This matters because mixing smooth explicit moves with implicit click-time teleports creates inconsistent behavior.

### No Straight-Line Or Fixed-Easing Default

The default movement path should not be a plain line and should not rely on one reusable easing curve for every situation.

The movement policy should include:

- mild curvature
- realistic acceleration and deceleration
- context-sensitive duration

### Bounded Jitter And Rare Overshoot

Noise should be constrained and purposeful.

Implications:

- jitter should not look like full-path wobble
- endpoint adjustments should converge
- overshoot should be low-probability and low-amplitude
- settle behavior should happen near the target, not across the whole path

### Difficulty-Scaled Duration

Movement duration should scale with the effective difficulty of the target.

At a high level:

- longer distances should often take longer
- smaller targets should often take longer
- large easy targets should not receive the same acquisition profile as small precise targets

The document does not prescribe a specific formula, but Fitts’-style scaling is the right conceptual direction.

### Context Consistency

Movement should not be modeled as an isolated line segment only.

It should stay consistent with:

- click timing
- double-click interval
- target acquisition behavior
- future drag behavior

The point is not to simulate every human detail. The point is to avoid internal contradictions between movement-producing commands.

## Practical Recommendations For `macos-cua`

For a future movement refactor, the most practical direction appears to be:

1. unify all pointer-moving commands behind one internal motion engine
2. use a minimum-jerk-like base profile instead of a line or simple Bézier default
3. add bounded lateral drift rather than independent per-point noise
4. support low-probability, low-amplitude overshoot and endpoint settle
5. scale movement duration with movement difficulty
6. keep the public CLI simple and keep the richer movement policy internal

A reasonable future shape would be to keep user-facing commands compact while introducing internal motion profiles such as:

- `precise`
- `natural`
- `fast`

That would let `macos-cua` improve movement consistency without exploding the CLI surface.

## Limits And Non-Goals

This note should not be read as a bypass recipe.

Important limits:

- movement is only one signal among many
- real anti-bot systems combine movement with fingerprinting, session context, timing, network signals, and challenge behavior
- a visually plausible path can still be statistically repetitive
- “more random” is not equivalent to “more human”

The goal for `macos-cua` should be modest and engineering-focused:

- avoid obviously mechanical movement
- avoid inconsistent movement behavior across commands
- make future motion design grounded in public motor-control and anti-bot research

## Sources Consulted

This synthesis was based on public search results and summaries gathered with the following queries:

- `bot detection mouse movement behavioral biometrics`
- `mouse dynamics bot detection pointer trajectory website fraud`
- `human mouse movement bot detection overshoot jitter acceleration`
- `DataDome mouse movement bot detection behavioral biometrics`
- `Arkose Labs mouse movement behavioral biometrics bot detection`
- `WindMouse human mouse movement algorithm overshoot jitter`
- `minimum jerk mouse movement human computer interaction bot detection`
- `Fitts law mouse movement bot detection human trajectory`
- `SigmaDrift mouse movement human like trajectory bot detection`

Named public systems, models, and concepts referenced in the synthesis:

- DataDome
- Arkose Labs
- WindMouse
- minimum-jerk motor model
- Fitts’ Law
- SigmaDrift / sigma-lognormal-style movement modeling
