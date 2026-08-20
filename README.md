# Phosphor

Phosphor turns your desktop into the picture on an old cathode-ray tube. Scanlines, a phosphor mask, bloom that spills off bright text, a little convergence error toward the corners, and a moulded plastic cabinet around the glass with a power lamp in the bottom corner.

It is not a filter you put over a theme. Your theme owns colours, apps, wallpaper and styling; Phosphor owns the monitor those things appear on. The two never touch each other, so any theme combines with any tube.

## The tubes

| Tube | |
|---|---|
| **VGA '94** | shadow mask, consumer PC monitor |
| **Trinitron** | aperture grille, with the damper wires |
| **Indy 21″** | graphics workstation, fine pitch |
| **Workstation 19″** | white phosphor, grayscale |
| **5151** | P1 green, monochrome display adapter |
| **VT-220** | P3 amber, serial terminal |
| **Broadcast** | slot mask, composite bleed |

**Make them yours.** Any tube can be tuned and saved as a copy — "My VT-220" — which lives alongside the built-ins, survives restarts, and can be renamed right in the panel. Built-in tubes are never modified: *Reset to stock* drops your tweaks, and your saved copies carry a *Delete* button instead.

**Any phosphor, any plastic.** The panel's colour swatches switch the phosphor between the theme's own colours and green, amber, paper, cyan or blue — or dial in any hue with the custom slider. The luminance mapping stays the same, so your theme's contrast hierarchy survives whatever colour the tube burns. The plastic has swatches too, from 80s beige to charcoal.

The colour tubes leave your theme's colours alone — a Tokyo Night desktop through the Trinitron is still Tokyo Night, just on worse glass. The monochrome tubes reinterpret whatever is on screen by luminance, so the theme's own contrast hierarchy survives: a bright accent stays bright, a muted comment stays muted, and the palette becomes green, amber or white phosphor. Switching themes under a monochrome tube changes the structure of what you see while the phosphor stays the same.

Light themes get a gentler tube automatically. Dark scanlines across white read far harsher than light ones across black, so the mask and scanline depth scale back when the theme is light.

## Install

```sh
omarchy plugin add https://github.com/ejuro/phosphor.git --enable
```

## Use

- Left-click the monitor glyph in the bar for the panel; right-click to switch the tube on and off.
- In the panel: pick a tube, then unfold *Display*, *Tuning* or *Colour* as needed — the sections stay folded so the panel opens at a readable height. Tuning holds brightness, contrast, colour, bloom, scanlines, scan pitch, mask, vignette, convergence and grain, with live numbers beside them and the tube updating as you drag. Curvature and flicker sit behind their own switches, and their sliders only appear once switched on. Right-click a slider to put that one control back to stock.
- Tweaked a saved tube? *Keep changes* folds the tweaks in as its new stock; *Discard changes* drops them. Built-in tubes are never modified.
- From anywhere: `omarchy-shell phosphor toggle`, or `enable` / `disable` / `preset <id>` / `cabinet on|off` / `save` / `keep` / `reset` / `status`. Individual controls too: `set scanline 0.3`, `set trueWarp true`, `stock scanline`.

Worth binding `omarchy-shell phosphor toggle` to a key. A CRT is a lovely place to read and a poor place to grade a photograph, and one keypress makes that a choice rather than a commitment.

## What it costs

Short answer: nothing you can measure, and nothing at all when the screen is still.

**Idle costs nothing.** Hyprland skips a monitor entirely when nothing has changed, and it keeps doing that in every damage-tracking mode except `0`. Phosphor never leaves you in mode `0`, so a still screen renders no frames — exactly as it would without the plugin.

**Under load it is lost in the noise.** Measured on an RTX 3080 at 2560×1440/144Hz with a browser and video running, alternating on and off three times for eight seconds each:

| | GPU utilisation | Power draw |
|---|---|---|
| Phosphor off | 18.3% | 36.6 W |
| Phosphor on | 15.5% | 36.5 W |

The "on" figure is lower, which is simply what noise looks like — the point is that the effect is smaller than the variation between rounds.

**Where the cost would be.** While the tube is lit Phosphor sets `debug:damage_tracking = 1` and puts your setting back when you switch off. It has to: the shader reads neighbouring pixels for bloom and convergence and displaces coordinates for curvature, so a pixel outside a damaged rectangle can still need redrawing, and under Hyprland's default region tracking it never gets it — which smears trails behind anything that moves. Mode 1 redraws the whole monitor when anything changes, and still draws nothing when nothing changes.

Damage tracking and the shader are always changed together, in that order, as two sequential Lua statements in a single `hyprctl eval`. Hyprland reads the setting when it loads a shader, and getting the order wrong earns a persistent error banner. Two separate `eval` calls are two processes with no ordering; two keys in one Lua table have no defined order either.

**The power transitions cost only while they run.** Switching on feels like powering a terminal: the desktop cuts to black in about 30ms, holds properly dark for a quarter second while the tube warms, then the picture rises out of the black over another third of a second — slow at first, the way a phosphor comes up to brightness, with scanlines, glow and glass already lit as it appears. Deliberately not the television line-and-dot. Switching off is its asymmetric opposite: the phosphor dies over about 110ms, the screen holds dark for a beat, and the shader is cleared while it is still black so the plain desktop returns in one step, with no second fade. Roughly 600ms on, 270ms off.

Transitions are the one thing that needs `debug:damage_tracking = 0`, which loses the idle skip entirely — so Phosphor drops into it only for the transition's own duration and restores your setting the moment it ends. The clock starts when Hyprland *loads* the shader, not when you press the key, so the swap back is timed from the apply: writing the file and the `hyprctl` round trip cost 100-200ms, and timing it from the keypress cut the fade off while the screen was still black, which read as a blink. Coming back, the shader is cleared at damage mode 1 for one whole-monitor redraw before your setting goes back, so nothing the tube drew is left smeared in a region nothing happens to touch. The panel's *Power fade* switch turns both off if you would rather changes be instant.

**Flicker is the priced exception.** Every other slider — brightness, contrast, colour, scanlines, scan pitch, mask, bloom, vignette, convergence, grain, glass curve — changes a shader that still costs nothing at idle. Flicker above zero needs a clock, and Hyprland only feeds a shader `time` with damage tracking fully off, so a flickering tube redraws every frame for as long as flicker is set. Grain comes alive along with it. The panel says so next to the slider; at zero the tube goes back to the free static shader.

## The cabinet

A screen shader cannot add screen, so the plastic has to come from somewhere — but it does not come out of your picture. When the cabinet is on, Phosphor reserves the bezel margins with layer-shell exclusive zones (invisible, click-through), and Hyprland lays the whole desktop out inside the glass: the bar, every window, all of it. The shader paints the plastic over margins that only ever contain wallpaper. Nothing is scaled, nothing is shifted, and everything on screen sits exactly where it responds to a click.

Each cabinet carries its machine's furniture on the chin: a maker's badge, brightness and contrast knobs, a row of panel buttons, speaker slots, and the power lamp. The Trinitron gets its damper wires; the Broadcast set gets a proper deep chin and a grille.

The side and top rails are deliberately slim. Omarchy's plugin drawers place themselves assuming the bar hugs the screen edge, so a fat reserved rail on the bar's edges would open every drawer offset from its icon. A ~6px lip stays inside the drawers' own tolerances — so the frame still closes visually, the chin carries the character, and every plugin's drawer keeps working.

The frame is deliberately lopsided: a ~6px lip on the top and sides, a deep chin along the bottom. That is not a style choice but the constraint above — the chin displaces nothing, so it can carry the character, while a fat rail on the bar's edges would break every plugin's drawer. *Even frame* in the panel trades that away for four equal sides: the rails widen, the chin loses the depth its badge, knobs and lamp need (so they go with it), and plugin drawers open slightly offset from their icons. The panel says so next to the switch.

Turning the cabinet off releases the margins and the desktop flows back to full size. It is a display-mode choice, not a preset value, so it survives switching tubes.

## Curvature, two ways

Hyprland does not warp input, so real barrel distortion always puts the picture somewhere slightly other than where clicks land. Phosphor gives you both sides of that trade:

- **Glass curve** (default) shapes the glass — corners round off, the edges fall away into shadow — while the picture is sampled exactly 1:1. Most of what the eye reads as a curved tube, with a layout that cannot move.
- **Bend the picture** switches on real curvature, eyes open: the picture itself bulges, and clicks near the edges land slightly off from where things appear. It is normalised so the corners stay on the corners and nothing is pushed off screen, and the *Glass curve* slider sets its strength. If you want the full fishbowl, this is it — the panel says plainly what it costs.

## What it cannot do

A Hyprland screen shader only ever receives the current frame. There is no feedback buffer, so real phosphor persistence — afterglow, trails behind a dragged window, the ghost of a scrolled terminal — is impossible. Everything here is spatial. Anyone promising you afterglow on this platform is drawing it, not simulating it.

The static shader also has no clock, so the *Grain* slider is a fixed per-pixel texture — glass and phosphor grain — rather than moving noise. It only animates while the tube is live (flicker above zero), because a clock is exactly the thing that costs the idle skip.

## Themes

Switching your Omarchy theme runs `hyprctl reload`, and a reload drops every runtime setting, the screen shader included. Phosphor listens for Hyprland's `configreloaded` event and puts the tube back, so theme switching leaves it exactly where it was. Nothing is written into your Hyprland config or your theme directories.

## State

Which tube, which tweaks, and whether the screen is on live in `${XDG_STATE_HOME:-~/.local/state}/phosphor/state.json`, alongside the generated shader. Removing the plugin does not delete them.

## If something goes wrong

The shader is applied at runtime, so a reboot or `hyprctl reload` clears it. To switch it off by hand from a TTY or another session:

```sh
hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })'
hyprctl eval 'hl.config({ debug = { damage_tracking = 2 } })'
```

## Remove

```sh
omarchy plugin remove io.github.ejuro.phosphor
```
