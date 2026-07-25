# Handoff: DEAL BUSTER app top banner (animated)

## Overview
A looping animated promo banner for the top of a mobile app home screen. It occupies roughly the
top 40% of the phone viewport, starting at the very top of the screen (the gradient runs behind the
status bar) and ending with a rounded bottom edge. The loop tells two beats:

1. **Hero beat** — "INTRODUCING / DEAL BUSTER" headline in a green outlined box, a gift illustration
   on the left, a "Check it out" CTA pill. A glowing line then sweeps once around the outline box and
   once around the CTA. The whole composition shrinks to a point and disappears.
2. **Calendar beat** — a tent-fold calendar flies in from far away, six green check marks drop in one
   at a time, two green "popper" curls whip outward from either side, with the caption
   "New deals updated daily" and the same CTA. It shrinks away and the loop restarts.

Total loop length: **13.0s**, autoplay, infinite.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype showing the intended
look, timing, and behavior. They are **not production code to copy directly**. The task is to recreate
this banner in the target codebase's own environment (React Native / Swift / Kotlin / Flutter / React
web) using its established animation and styling primitives. If no environment exists yet, pick the
most appropriate one for the app and implement there.

Practical note for native apps: this is a timed, non-interactive animation apart from the CTA tap.
Reanimated (RN), Core Animation/SwiftUI `withAnimation` keyframes (iOS), or Compose `Animatable`
(Android) are all sufficient — no video asset is required, though exporting the HTML prototype to
video/Lottie is a legitimate shortcut if hand-animating is too costly.

## Fidelity
**High-fidelity (hifi).** Colors, typography, spacing, and timing are final. Recreate pixel-for-pixel,
scaled from the reference canvas.

## Reference canvas & scaling
All numbers below are in px on a **1080 × 880** design canvas (the banner only — not the whole phone).
Scale uniformly: `factor = deviceWidth / 1080`. At a 1080-wide device the banner is 880 tall
(≈40% of a 2340-tall screen). The canvas top edge = the top of the screen; the status bar sits over
the gradient (use light status-bar content).

## Screens / Views

### 1. Hero state (scenes: Intro, Glow line, Collapse)
**Purpose:** announce the DEAL BUSTER campaign and drive a tap on "Check it out".

**Layout** — absolute positioning on the 1080×880 canvas:

| Element | Position (x, y) | Size | Notes |
|---|---|---|---|
| Backdrop | 0, 0 | 1080 × 880 | bottom corners radius 52 |
| Hanging panel | 300, 96 | 520 × 470 | trapezoid, `clip-path: polygon(4% 0, 96% 0, 88% 100%, 12% 100%)`, fill `linear-gradient(180deg, rgba(255,255,255,.075), rgba(255,255,255,.01))`, group opacity .9 |
| Hanger strings | 372, 104 / 742, 104 | 2 × 200 | rgba(255,255,255,.16), rotated -7° / +7° |
| Hooks (2) | 352, 78 / 718, 78 | 52 × 52 | 9px ring, color rgba(20,6,45,.9), `border-top-color: transparent`, rotate 35° |
| "INTRODUCING" | 322, 196 (centered in 664 wide) | — | Poppins 600, 34px, letter-spacing .3em, #F2ECFF |
| Outline box | 322, 268 | 664 × 288 | 5px solid #B6F24C, radius 20, glow `0 0 26px #B6F24C33` |
| "DEAL" | centered in box, top 314 | — | Montserrat 900 **italic**, 132px, line-height .94, letter-spacing -.015em, #B6F24C, shadow `0 6px 0 rgba(0,0,0,.35), 0 0 34px #B6F24C55` |
| "BUSTER" | directly under DEAL, margin-top 12 | — | Montserrat 900 **italic**, 92px, letter-spacing .02em, #FFFFFF, shadow `0 5px 0 rgba(0,0,0,.32)` |
| Gift illustration | 74, 286 | 300 × 300 | `assets/gift.svg`, shadow `0 18px 26px rgba(0,0,0,.45)` |
| CTA pill | 366, 622 | 372 × 104 | radius 999, `linear-gradient(180deg,#B6F24C,#8FCF20)`, label Poppins 600 44px #17200A, shadow `0 12px 30px rgba(0,0,0,.35), 0 0 0 6px #B6F24C1f` |

No arrow glyph in the CTA and **no slider dots** — deliberate.

### 2. Calendar state (scenes: Calendar, Reset)
**Purpose:** reinforce "new deals every day".

| Element | Position | Size | Notes |
|---|---|---|---|
| Calendar group | centered, top 178 | 552 × 340 | 3D: parent `perspective: 1500px`; inner group `rotateX(11deg) rotateZ(-3.5deg)`, `transform-style: preserve-3d`; drop-shadow `0 26px 30px rgba(0,0,0,.45)` applied on the **parent of** the perspective node (a filter on the same node flattens 3D) |
| Left flap | left of face | 128 × 340 | `rotateY(52deg)`, origin right center, fill #CBB292; 54px top band #5E9A2C |
| Front face | — | 424 × 340 | `rotateY(-11deg)`, origin left center, fill `linear-gradient(180deg,#F2E2C9,#E2CDAC)`; 54px top band `linear-gradient(180deg,#7CBE3A,#63A128)` |
| Spiral rings (2) | x 86 from each side, top -22 | 34 × 34 | 8px ring #1D3A16, `border-bottom-color: transparent`, rotate ∓18° |
| Tick grid | face, top 78 | 3 cols × 88px, gap 20 | 6 cells, 2 rows |
| Tick box | — | 88 × 74 | radius 10, `linear-gradient(180deg,#7CC03C,#5E9A2C)`, 3px border rgba(255,255,255,.9), shadow `0 4px 10px rgba(0,0,0,.25)` |
| Check mark | inside tick | 54 × 42 | polyline `6,22 → 20,34 → 47,7`, stroke #FFF 8px, round caps, stroke-dash draw-on |
| Poppers (2) | 118, 268 and 772, 268 (right one `scaleX(-1)`) | 190 × 190 | path `M14 168 C 52 66, 150 44, 146 96 C 143 138, 78 122, 112 62`, stroke #B6F24C 8px round; plus a short tick `M4 128 L 44 118` |
| Caption | full width, top 578 | — | Poppins 500, 46px, #EFE9FF, "New deals updated daily" |
| CTA pill | 366, 662 | 372 × 100 | same styling as hero CTA |

## Interactions & Behavior

Only one interaction: **tap the CTA pill → navigate to the deals/subscription screen.** Whole banner
tappable is also acceptable. The animation is decorative and should not block input.

### Timeline (13.0s, loops)
| # | Scene | Duration | Choreography (p = 0→1 within the scene) |
|---|---|---|---|
| 1 | Intro | 3.2s | panel+hooks fade/slide down (p .0–.30); gift slides in from x-230 with rotate -22°→0 and scale .8→1 (p .10–.56, back-out); INTRODUCING fades + rises 16px (p .20–.42); outline box fades + scale .94→1 (p .24–.50); DEAL drops from y-54, scale .86→1 (p .32–.64, back-out); BUSTER rises from y+48, scale .86→1 (p .42–.74, back-out); CTA scale .7→1 (p .60–.92, back-out) |
| 2 | Glow line | 2.8s | hero held still. Glow head travels the outline box 0→360° (p .04–.50), fading in p .04–.12 and out p .44–.52. Then the same sweep around the CTA pill 0→360° (p .50–.96), fading in p .50–.58, out p .90–.99 |
| 3 | Collapse | 0.9s | whole hero `scale(1 → .04)` ease-in-cubic, origin 50% 46%; opacity 1→0 over p .5–1 |
| 4 | Calendar | 5.2s | calendar scale .06→1 + back-out (p 0–.17); caption fades/rises (p .15–.26); CTA pops (p .20–.35); ticks land one at a time — tick *i* animates over `p ∈ [.5 + i·.055, .5 + i·.055 + .14]`: drop from y-46 with scale .55→1 back-out, then the check stroke draws (last 75% of its own window); poppers draw outward p .86–.99 (stroke-dashoffset from **negative** length so the line grows away from the calendar), short tick appears at 60% of that |
| 5 | Reset | 0.9s | calendar group `scale(1 → .04)`, opacity out over p .5–1 → loops back to Intro |

### Ambient (continuous, never resets at scene cuts)
Five 4-point stars twinkle. Positions/sizes (x, y, size, base opacity, phase):
`(62,196,30,.85,0) (128,620,22,.60,.34) (992,160,34,.90,.62) (946,700,18,.50,.18) (520,112,14,.40,.80)`
Each star: `w = (sin((t·1.15 + phase)·2π) + 1) / 2`, `k = .22 + w·.78`; then
`opacity = base·k`, `transform: scale(.62 + k·.5) rotate(w·24 − 12deg)`,
`drop-shadow(0 0 (4 + k·12)px rgba(255,255,255,.35·k))`.
Star shape: `clip-path: polygon(50% 0,57% 43%,100% 50%,57% 57%,50% 100%,43% 57%,0 50%,43% 43%)` on white.

### The glow line (both sweeps)
A rotating conic gradient masked to the element's border ring:
```css
padding: 7px;               /* ring thickness; 6px on the CTA */
border-radius: 24px;        /* 999px on the CTA */
background: conic-gradient(from <angle>deg,
  rgba(255,255,255,0) 0deg 232deg,
  #DFFF8A00 240deg, #DFFF8A 340deg, #ffffff 358deg, rgba(255,255,255,0) 360deg);
mask: linear-gradient(#000,#000) content-box, linear-gradient(#000,#000);
mask-composite: exclude;    /* -webkit-mask-composite: xor */
filter: drop-shadow(0 0 12px #DFFF8A) drop-shadow(0 0 34px #DFFF8A) drop-shadow(0 0 60px #DFFF8Aaa);
```
The ring is inset -4px on each side of the target element (box: 656+8 × 288+8 at 318,264).
On native, an equivalent is a sweep-gradient shader or a masked rotating layer; a simpler acceptable
fallback is an animated bright dot travelling the rounded-rect path with an additive blur trail.

### Easing (only three curves are used anywhere)
- `enter` = easeOutCubic
- `draw` = easeInOutCubic
- `pop` = easeOutBack (c1 = 1.70158)

### Scene-boundary rule
Every scene's first and last frame is the *settled* composition — entrances and exits finish strictly
inside the scene. If you re-time anything, preserve this or the cuts will pop.

## State Management
- `t` — elapsed loop time in seconds (0…13), driven by a display-link / rAF; `t % 13` for looping.
- Derived: current scene index + local progress `p`. No data fetching, no user state.
- Optional `enabled` flag to pause the loop when the banner is off-screen or reduce-motion is on.
  With reduce-motion, render the **settled hero frame** (end of scene 1) statically.

## Design Tokens
Colors
- accent green `#B6F24C`, deep green `#8FCF20`, glow `#DFFF8A`
- tick green `#7CC03C` → `#5E9A2C`; calendar band `#7CBE3A` → `#63A128`; ring ink `#1D3A16`
- calendar paper `#F2E2C9` → `#E2CDAC`; left flap `#CBB292`
- backdrop (default "violet"): top `#4A1B96`, mid `#2E0F63`, bottom `#170733`, halo `rgba(150,90,255,.42)`
  - alt "indigo": `#33257F / #211550 / #0F0A2A`, halo `rgba(120,110,255,.38)`
  - alt "plum": `#5A1360 / #3A0B44 / #1C0522`, halo `rgba(210,80,220,.34)`
- text `#FFFFFF`, `#F2ECFF`, `#EFE9FF`; CTA label `#17200A`
- Backdrop = `linear-gradient(177deg, top 0%, mid 44%, bottom 100%)`, plus a 1300×980 radial halo at
  (52%, 38%) opacity .5, plus a bottom vignette `radial-gradient(120% 80% at 50% 108%, rgba(0,0,0,.34), transparent 60%)`.

Typography — Montserrat (900 italic) for the headline, Poppins (500/600) for everything else.
Sizes on the 1080 canvas: 132 / 92 / 46 / 44 / 34.

Radii: 10, 20, 52 (banner bottom), 999. Spacing scale used: 12, 20, 54, 78.

## Assets
- `assets/gift.svg` — gift-box illustration, user-supplied, included in this bundle. Ship as-is
  (vector). Reference footprint 300×300.
- Fonts: Montserrat + Poppins (Google Fonts). Use the bundled equivalents in the app.
- The calendar, ticks, poppers, stars and glow are all drawn in code — no raster assets needed.

## Files
- `Deal Buster Banner.dc.html` — the runnable prototype (open in a browser; loops automatically).
- `banner-scenes.jsx` — all of the composition and timing logic; the authoritative source for
  numbers, easing and choreography.
- `animations-v2.jsx` — the prototype's generic timeline/scene engine (harness only; **do not port**).
- `tweaks-panel.jsx` — prototype-only control panel (harness only; **do not port**).
- `assets/gift.svg` — the illustration.
