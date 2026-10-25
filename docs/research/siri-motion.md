# Siri motion study: evidence for the pill

What the new Siri on iPhone does with glass, light and motion, measured frame by frame, and what kotoba's pill should take from it. Written 2026-10-25 for the pill-motion work (`App/PillMorph.swift`, `App/PillBars.swift`, `App/PillView.swift`).

Read first:
- "Measured" numbers come from one screen recording of Siri on an iPhone (Siri AI, so iOS 27 by date; the build is not on screen): 1206×2622 px at 3 px per point, 60 fps while things move, 35.5 s, two questions and two answers. The recording, frames, contact sheets, plots and the scripts that made every number are in `<runbooks>/2026-10-24-kotoba-ui-redesign/siri/` (`frames/`, `scripts/`). Nothing from the recording goes in this repo.
- "Apple" facts come from Apple pages, with links. "Secondary" marks a source that is not Apple.
- The recording has the phone's sound, not the microphone, so the user's voice is not in it. The reaction to the voice is inferred from the light's own envelope while the user speaks.

## Sources

Apple:
- HIG Materials (Liquid Glass, updated 2025-09-09): https://developer.apple.com/design/human-interface-guidelines/materials
- HIG Motion (2025-09-09): https://developer.apple.com/design/human-interface-guidelines/motion
- HIG Accessibility (Reduce Motion list): https://developer.apple.com/design/human-interface-guidelines/accessibility
- HIG Color (glass tint): https://developer.apple.com/design/human-interface-guidelines/color
- HIG Siri (revised 2026-06-08 for Siri AI; intents only, no visual guidance): https://developer.apple.com/design/human-interface-guidelines/siri
- HIG Generative AI (feedback while working): https://developer.apple.com/design/human-interface-guidelines/generative-ai
- WWDC25 219 "Meet Liquid Glass": https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 323 "Build a SwiftUI app with the new design": https://developer.apple.com/videos/play/wwdc2025/323/
- WWDC25 310 "Build an AppKit app with the new design": https://developer.apple.com/videos/play/wwdc2025/310/
- WWDC26 269 "What's new in SwiftUI", 289 "Modernize your AppKit app", 322 "Compose advanced graphics effects with SwiftUI": https://developer.apple.com/videos/play/wwdc2026/269/, /289/, /322/
- Newsroom, Siri AI (2026-06 and 2026-09): https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/
- API docs: `NSGlassEffectView` https://developer.apple.com/documentation/appkit/nsglasseffectview, SwiftUI `Glass` https://developer.apple.com/documentation/swiftui/glass, "Applying Liquid Glass to custom views" https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

Secondary (gaps only):
- Livsy90/IntelligenceGlow (MIT) and jacobamobin/AppleIntelligenceGlowEffect (MIT): recreations of the iOS 18 edge glow, https://github.com/Livsy90/IntelligenceGlow, https://github.com/jacobamobin/AppleIntelligenceGlowEffect
- Apple Developer Forums thread 818901: glass in a non-key `NSPanel` draws its inactive look, https://developer.apple.com/forums/thread/818901

## What Apple says (load-bearing facts)

- Appear and disappear: "Instead of fading, Liquid Glass objects materialize in and out by gradually modulating the light bending and lensing." (WWDC25 219). SwiftUI names this `GlassEffectTransition.materialize`; AppKit has no named equivalent.
- Morph: glass "dynamically morphs between the controls in each context… a singular floating plane" (219). Larger glass "casts deeper, richer shadows, has more pronounced lensing and refraction effects, and a softer scattering of light" (219).
- Light from within: on touch "the material illuminates from within… the glow spreads throughout the element" (219). The recording shows the same idea: Siri's light lives inside the glass.
- Motion: "Aim for brevity and precision in feedback animations." "Generally avoid adding motion to UI interactions that occur frequently." "Don't make people wait for an animation to complete." (HIG Motion). The HIG gives no millisecond values.
- Reduce Motion: tighten springs to cut bounce, replace x/y/z transitions with fades, avoid animating into and out of blurs, be careful with fast and blinking motion (HIG Accessibility). Glass itself "disables any elastic properties" under Reduce Motion (219).
- Status indicators: "Non-interactive items like custom titles and status indicators should avoid the glass material." (WWDC25 310). The pill is glass by the owner's decision (`ui-redesign.md`, Pill); this is a known tension, not a new finding.
- Glass on glass: do not; use fills on top of glass (219). The pill already follows this.
- The Siri and Apple Intelligence glow has no public API (doc paths for any glow view return 404; `NSWritingToolsCoordinator.effectContainerView` is the Writing Tools text effect only). kotoba must draw its own light.
- Springs in SwiftUI: `Spring(duration:bounce:)`, bounce 0 = no overshoot. `.smooth` bounce 0, `.snappy` 0.15, `.bouncy` 0.3, each with a 0.5 s default duration.

## The recording, state by state

Sizes are in points (px ÷ 3). The top edge of every shape stays on the Dynamic Island: Siri grows down and to both sides from it and goes back into it. The island in the recording is 172×35 pt (it carries the screen-recording activity).

| Time (s) | State | Shape (pt) | What moves |
|---|---|---|---|
| 0.0–1.6 | Home screen | island | nothing |
| 1.60–1.68 | Trigger | island | the island's own content (the recording dot) fades out in 83 ms first |
| 1.70–2.00 | Listening opens | island → lens about 163 wide × 150 tall | glass grows; light appears at +100 ms |
| 2.0–6.55 | Listening | lens | light ribbon and lens size follow the voice |
| 6.55–6.93 | End of speech | lens → capsule about 253×55 | light collapses to a dot, the dot moves, becomes the spinner |
| 6.9–8.2 | Thinking | capsule | spinner turns |
| 8.20–8.60 | Answer | capsule → card 374 wide (14 pt side margins) × about 240 | card grows with a small overshoot; text sharpens in |
| 8.4–11.3 | Siri speaks | card | nothing in the card moves |
| 11.3–21.5 | Waiting | card | nothing in the card moves |
| 21.5–25.2 | Follow-up listening | card | light along the card's bottom inner edge, follows the voice |
| 25.18–25.6 | End of speech | card → thinking capsule | card shrinks, content blurs out, spinner appears |
| 27.67–27.9 | "Searching" | capsule → 374×75 capsule | grows with overshoot; grey label fades in |
| 29.5–29.9 | Answer | → card | as at 8.2 |
| 33.52–33.90 | Dismiss | card → island | shrinks into the island; status bar comes back |

The rest of the screen does not react: the mean brightness of the lower screen is the same in every frame (108.0 on a 0–255 scale). No dim, no blur, and no screen-edge glow. The full-screen edge glow of iOS 18 is not in this Siri.

### 1. Glass and light

- Listening shape: a near-round lens, about 163×150 pt, hanging from the island. Its interior is black (it continues the black island), and its rim is strongly refractive: the app icons under the lower edge show magnified and bent inside the rim, with a thin bright line on the very edge.
- The light: a horizontal ribbon in the lower half of the lens, about 70–85% of the lens width. A white core with spectral fringes, like light through a prism. Measured colours of the coloured pixels (brightest pixels only): warm side peach #E2A684, amber #E8C389, pale yellow #EBE388; cool side cyan #8FE6ED, sky #88C5EC, cornflower #7DA1DF. Almost no green, pink or purple. The white core is 14% of the bright pixels.
- Card follow-up light: on the card the light sits on the bottom inner edge, curving up at the corners. White core (27% of bright pixels) with periwinkle #7695D1 and lavender #B2A9F2, and a warm peach #EFBB9D centre on loud moments.
- The answer card is a dark glass: black at the top, more see-through towards the bottom, so the icons behind show blurred, and its bottom edge refracts them.

### 2. Reaction to the voice (listening, 2.0–6.55 s)

Plot: `frames/listen_streak.png`.
- Brightness of the ribbon (pixels over 180 of 255): rest about 10,000, peaks 20,000–24,300, so about 2.4× from rest to peak.
- Attack is fast: rest to peak in 4 frames (about 67 ms), for example at 3.07–3.13 s and 3.73–3.80 s.
- Release is slow: peak to about 40% in 230–300 ms, back to rest in about 400 ms.
- The main motion is slow: the strongest frequencies are 0.2–1.3 Hz. Frame-to-frame change is small; there is no jitter at the rate of syllables.
- The lens itself breathes with the voice: its bottom edge moves between 451 and 518 px (a range of about 22 pt on a 150 pt shape, ±7%), in step with the ribbon, with the same fast attack and slow release.
- The ribbon also changes shape: thin line at rest; a thick lens-shaped bloom, an S-curve or two crossing ribbons when loud. It never scrolls and never shows the past.
- Card follow-up light: rises in about 300 ms, then spreads from the centre outward, from about 250 pt to the card's full 360 pt within about 0.8 s, then varies about ±20% with the voice.

### 3. Shape changes: timing and easing

Each change was tracked by the moving edge at 60 fps and fitted with a SwiftUI spring (`Spring(duration:bounce:)`, starting at rest). Plot: `frames/easing_fits.png`. "90%" is the time until the edge covered 90% of its travel.

| Change | Travel | 90% at | Overshoot | Best fit |
|---|---|---|---|---|
| Island → listening lens (grow) | +161 pt down, +110 pt wide | 100–167 ms | 0.4–2.4% | faster than any spring from rest: a fast start, then an ease-out tail; settled at about 300 ms |
| Lens → thinking capsule (shrink) | −87 pt | 183 ms | 0% | the same fast-start ease-out; settled at about 420 ms |
| Thinking → answer card (grow) | +172 pt down, +137 pt wide | 167–200 ms | 2.9–3.2% | duration 0.36–0.40 s, bounce 0.22–0.30 |
| "Searching" → answer card (grow) | +137 pt | 233 ms | 3.3% | duration 0.53 s, bounce 0.28 (noisier) |
| Thinking → "Searching" (small grow) | +18 pt, +65 pt wide | 117–133 ms | 2.8–3.8% | very fast, small overshoot |
| Card → thinking capsule (shrink) | −171 pt | 250 ms | 0% | duration 0.31 s, bounce −0.12 (no overshoot) |
| Card → island (dismiss) | −197 pt | 200 ms | 0.2% | duration 0.33 s, bounce 0.10; the last 10 pt into the island take another 170 ms |

The pattern:
- A shape that grows to show a result (card, "Searching") overshoots by about 3%: a spring with bounce about 0.2–0.3 and a duration about 0.36–0.40 s.
- A shape that shrinks never overshoots: duration about 0.31–0.33 s, bounce 0.
- The first appearance and the switch to thinking start faster than a spring from rest: a fast-start ease-out where the glass's soft, blurred edge reaches out in the first 2 frames, then becomes a sharp rim (the "materialize" Apple describes).
- Every change reaches 90% in 117–250 ms. Nothing makes the user wait.

### 4. Content in and out

- Listening light enters 100 ms after the glass starts to grow, as a faint thin line, and is at full brightness at about 270 ms.
- At the end of speech the ribbon collapses sideways into one bright point within 50 ms (3 frames). The point moves to where the spinner will be over about 200 ms and then opens into the spinner in about 100 ms. The light that listened becomes the light that thinks.
- Answer text enters 17 ms after the card starts to grow, blurred and faint, and is sharp at about 100 ms. The second part of the answer (a weather panel) fades and sharpens from +130 ms to +330 ms. The spinner fades out within about 70 ms of the card starting.
- When the card shrinks, its content scales down with it and blurs out in about 100 ms; the content is not clipped in place.
- The "Searching" label (grey, about 55% white) fades in over about 70 ms, starting about 20 ms after the capsule starts to grow.
- After the dismiss, the status bar icons fade back in over about 120 ms, once the shape is nearly home.

### 5. Thinking indicator

- 7 dots on a ring about 30 pt across, at the leading end of the capsule. Dot sizes vary around the ring (3 large and elongated, 4 small), each with a soft halo.
- The ring turns clockwise at a constant speed: 366°/s, one turn in 0.98 s.
- It runs only while Siri works; the answer replaces it.

### 6. At rest

- While the answer card waits (11.3–21.5 s), nothing in Siri moves. The recorder wrote frames in that time only for the home screen's own icon motion under the card, and for the card's bottom edge that refracts it.

## kotoba's pill now, and what to change

Current pill (read 2026-10-25 on `ui-polish`): one `CapsuleGlass` (`NSGlassEffectView`) that morphs between looks with one spring, `GlassSpring` duration 0.4 s, bounce 0.15 (`App/PillMorph.swift:131-148`); new items fade in after 0.08 s for 0.2 s, leaving items fade out in 0.12 s (`App/PillMorph.swift:121-124`); 9 brand-coloured bars, one additive 0.2 s ease-in-out tween per level event at 10 events a second (`App/PillBars.swift:26`, `:145-167`); the processing sweep is a 0.6 s pulse that reverses, 0.09 s between bars, ×2.6 length, opacity 0.6–1 (`App/PillBars.swift:195-227`); Reduce Motion uses `Spring(duration: 0.25, bounce: 0)` (`App/PillMorph.swift:48`). The capsule is 36.5 pt thick (`App/PillGeometry.swift:26`), the idle bar 40×8 pt.

### Appear (hidden → recording)

- Siri: grows out of its home shape. 90% in 100–167 ms, settled at about 300 ms, no overshoot. The edge starts soft and becomes sharp. The light enters at +100 ms.
- kotoba: the look is set while the panel is hidden, so `morph` places the glass at once (`App/PillMorph.swift:25-33`), and the panel then orders front (`App/IndicatorPanel.swift:180-184`). The pill pops in at full size.
- Do: order the panel front with the glass at a seed shape on the anchor (the idle bar, 40×8 pt, or 8×8 pt), glass `alphaValue` 0. In the next turn set the recording look: glass alpha 0 → 1 over 0.12 s ease-out, size with `Spring(duration: 0.3, bounce: 0)`. Bars enter at +0.08 s over 0.15 s (the current fade values fit). When the idle bar is already showing ("Always"), the same no-bounce spring from the bar.
- Reduce Motion: no growth; the glass and content fade in over 0.15 s.

### Recording (level)

- Siri: one light inside the glass; fast attack (about 67 ms), slow release (about 250–400 ms), motion at 0.2–1.3 Hz, 2.4× from rest to loud; the shape breathes ±7% with the voice.
- kotoba: the same 0.2 s tween up and down, so a loud syllable rises as slowly as it falls, and the bars drop to rest at once between words.
- Do: make the envelope asymmetric in `PillBars.level`'s `didSet`.
  - Up: show the new level at once, with a 0.08 s ease-out tween.
  - Down: `shown = max(new, shown × 0.7)` per 100 ms event (about a 280 ms time constant), with the 0.2 s tween.
  - The weights' drift stays as it is: it is already slow and has no history.
- Glass breathing (a variant to try, not a default): scale the glass by at most 1.03 with the same envelope through the layer's transform, never through its frame. A frame change runs glass layout at about 1 ms a frame (`App/PillMorph.swift:127-130`). Report its CPU cost during a recording. If the glass's refraction draws wrong under a transform, drop the variant.
- Colour: keep the brand colour (owner, 2026-10-25). The Siri feel comes from light, not from hue. To try: a soft halo on the bars at loud levels only (layer shadow in the bar colour, radius 2–3 pt, opacity 0 → 0.5 with the envelope, `shadowPath` set so it costs no offscreen pass).

### Stop → processing

- Siri: the shape shrinks with no overshoot (90% in 183 ms). The light condenses to one point in 50 ms, and that point becomes the thinking indicator about 380 ms after the end of speech.
- kotoba: the bars settle to dots in 0.25 s, and the wave starts 0.25 s later (`App/PillBars.swift:124-127`, `:203`). The continuity is already there.
- Do: settle in 0.15 s ease-out and start the wave as the settle ends; the shrink (hands-free loses its buttons) takes the shrink spring below.

### Processing (sweep)

- Siri: one direction at a constant speed, one cycle in 0.98 s, size varies along the ring, the dots never go out, each dot has a soft halo.
- kotoba: a pulse that reverses, 1.2 s a cycle.
- Do: a cycle of 1.0 s. Stagger 1.0 / 9 ≈ 0.11 s, so the wave moves at an even pace. Keep the 0.5–0.6 minimum opacity. Size ×1 → ×2.2. It runs only while text is on its way (as now). Reduce Motion: opacity only (as now).

### Processing → done check

- Siri: the result shape grows with about 3% overshoot (bounce 0.2–0.3, 0.36–0.40 s); the old indicator fades out in about 70 ms; the result sharpens in within about 100 ms.
- kotoba: the capsule shrinks to a circle, and the check draws on (`App/PillView.swift:311-317`).
- Do: the glass shrinks with the shrink spring (no overshoot: shrinking shapes never overshoot in Siri). The dots fade out in 0.07 s. The check starts its draw-on at +0.05 s. If the done needs a "bloom", put the bounce on the check symbol (scale 0.85 → 1, bounce 0.25), not on the glass.

### Words: messages, errors, Undo, "Added ‘word’"

- Siri: a growing shape overshoots about 3% and reaches 90% in 117–233 ms. A new label fades in over about 70 ms from about +20 ms. Content that leaves scales and blurs out in about 100 ms.
- kotoba: one spring (0.4 s, bounce 0.15) for growth and shrink alike.
- Do: two springs, chosen by the change of the capsule's long side:
  - Grow: `Spring(duration: 0.38, bounce: 0.2)`.
  - Shrink: `Spring(duration: 0.32, bounce: 0)`.
  - When a change takes over mid-flight, keep the current velocity hand-over (`GlassSpring.velocity`).
- Words fade in at +0.04 s over 0.15 s. An optional 4 pt blur → 0 comes with it, but never under Reduce Motion (HIG: avoid animating into and out of blurs). The leaving fade stays at 0.12 s.

### Hide (done, message timeout, Esc, cancel)

- Siri: shrinks back into its home shape (90% in 200 ms, the last bit by about 380 ms), no overshoot, content blurs out first, then the rest of the screen restores.
- kotoba: `orderOut` at once (`App/IndicatorPanel.swift:234-241`); the pill vanishes.
- Do: morph to the seed shape on the anchor (the idle bar) with the shrink spring. Fade the glass alpha 1 → 0 over the last 0.12 s. `orderOut` in the animation's completion. A new show during the hide takes over from where the glass is. With "Always", the idle bar is already the home shape: shrink to it, no fade.
- Reduce Motion: fade out over 0.15 s, no shrink.

### Idle

- Siri: nothing moves at rest. kotoba already does no work at idle (`App/PillView.swift:5-9`). Keep it. Every motion above is a transient animation that ends, and the processing loop ends with processing.

## What not to copy

- The black glass. It continues the hardware island; on a Mac the pill uses regular adaptive glass (HIG Materials).
- The rainbow prism ribbon and the periwinkle/lavender edge light as kotoba's look: they are Siri's identity, and the owner chose the brand colour. Copy the behaviour (light inside the glass, fast attack and slow release, condense to a point, materialize) and not the palette.
- The size of Siri's shapes. Siri takes 160–375 pt and a card; the pill stays a small capsule that does not cover the user's work.
- A screen dim, a blur behind or a screen-edge glow. Siri does none of them in this build, and a dictation pill must not take the screen.
- Interactive glass bounce (`effectIsInteractive`, macOS 27). Apple keeps it for controls, and the pill's buttons are fills, not glass.
- A lookalike of Siri. Apple has no public glow API, and a copy can read as Apple's own UI (secondary: a VP0 blog warns about Siri overlay clones).

## Unresolved questions

1. Does `alphaValue` on an `NSGlassEffectView` fade the glass cleanly (lensing and shadow together), or does it flash a frosted frame? Apple names `materialize` in SwiftUI only. pill-motion must check it on screen; a snapshot cannot show glass (AGENTS.md, `make snapshots`).
2. Should the pill breathe with the voice (the ±3% transform variant)? This is the owner's taste call after a trial, with its measured CPU cost.
3. Does the owner want a soft halo on the bars (light quality), or plain bars?
4. Is the 4 pt blur on entering words worth its cost on a glass panel? This is not measured.
5. The voice is not in the recording, so the attack and release are taken from the light's envelope, not checked against the speech itself. A second recording with the mic on would confirm them.
