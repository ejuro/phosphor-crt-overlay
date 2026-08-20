.pragma library

// Each preset is a specific machine, not a slider soup. Names evoke the
// machines they are modelled on; Phosphor is not affiliated with, endorsed by,
// or derived from any of those manufacturers.
//
// mask: "grille" | "slot" | "shadow" | "none"
// mono: null for colour tubes, or the phosphor a monochrome tube burns.
// Cabinet character: chin (bottom bezel as a multiple of the frame), badge,
// knobs (0-2 front controls), buttons (a row of small panel buttons),
// grille (speaker slots on the chin).

var USER_PREFIX = "user-"

var DEFAULTS = {
  bezelWidth: 0.035,
  // The rails that would displace the bar are capped slim so plugin drawers
  // keep opening under their icons; the chin, which displaces nothing, carries
  // the machine's furniture. evenFrame trades that away for four equal sides.
  evenFrame: false,
  chin: 1.6,
  bezelRadius: 0.060,
  glassRadius: 0.045,
  bezelColor: [0.310, 0.292, 0.262],
  bezelLight: [0.520, 0.497, 0.450],
  // Curvature is drawn at the glass — rounded corners and curved edge shading —
  // never applied to your pixels, so the layout can not move. trueWarp opts in
  // to bending the picture itself, clicks near the edges be damned.
  warp: 0.045,
  trueWarp: false,
  scanline: 0.22,
  scanPitch: 3.0,
  mask: 0.30,
  maskPitch: 3.0,
  maskType: "grille",
  slotHeight: 6.0,
  damperWires: 0,
  badge: false,
  knobs: 0,
  buttons: 0,
  grille: false,
  bloom: 0.35,
  bloomRadius: 1.7,
  vignette: 0.30,
  converge: 0.60,
  chromaBleed: 0.0,
  bright: 1.34,
  contrast: 1.0,
  saturation: 1.0,
  // Grain is a fixed per-pixel texture in the cheap static shader (it has no
  // clock); it only moves like true analog noise while the tube is "live".
  noise: 0.0,
  // Flicker above zero switches the tube to the timed shader, which needs
  // damage tracking fully off — the one tuning with a real GPU cost.
  flicker: 0.0,
  glare: 0.045,
  mono: null,
  monoWhite: 0.55,
  // Dark scanlines across a white background are far more visible than the
  // reverse, so light themes get a gentler tube.
  lightScale: 0.55
}

var PRESETS = [
  {
    id: "vga94",
    name: "VGA '94",
    subtitle: "shadow mask, consumer PC monitor",
    params: {
      maskType: "shadow", mask: 0.34, maskPitch: 3.0, slotHeight: 3.0,
      scanline: 0.20, warp: 0.050, converge: 0.75, bloom: 0.32,
      bezelWidth: 0.036, chin: 1.9, badge: true, buttons: 4,
      bezelColor: [0.505, 0.470, 0.395], bezelLight: [0.660, 0.622, 0.530]
    }
  },
  {
    id: "trinitron",
    name: "Trinitron",
    subtitle: "aperture grille with damper wires",
    params: {
      maskType: "grille", mask: 0.32, maskPitch: 3.0, damperWires: 2,
      scanline: 0.18, warp: 0.020, converge: 0.35, bloom: 0.38, vignette: 0.24,
      bezelWidth: 0.028, chin: 1.5, badge: true, buttons: 5,
      bezelColor: [0.180, 0.176, 0.170], bezelLight: [0.330, 0.324, 0.312]
    }
  },
  {
    id: "indy21",
    name: "Indy 21″",
    subtitle: "graphics workstation, fine pitch",
    params: {
      maskType: "grille", mask: 0.22, maskPitch: 3.0,
      scanline: 0.13, warp: 0.012, converge: 0.20, bloom: 0.28, vignette: 0.20,
      bright: 1.22, bezelWidth: 0.028, chin: 1.4, badge: true,
      bezelColor: [0.225, 0.232, 0.258], bezelLight: [0.360, 0.372, 0.410]
    }
  },
  {
    id: "workstation19",
    name: "Workstation 19″",
    subtitle: "white phosphor, grayscale",
    params: {
      maskType: "none", mask: 0.0, scanline: 0.16, warp: 0.025, converge: 0.0,
      bloom: 0.30, vignette: 0.22, bright: 1.10, chin: 1.5,
      mono: [0.93, 0.95, 1.00], monoWhite: 0.35,
      bezelWidth: 0.032, badge: true,
      bezelColor: [0.560, 0.552, 0.520], bezelLight: [0.700, 0.690, 0.655]
    }
  },
  {
    id: "5151",
    name: "5151",
    subtitle: "P1 green, monochrome display adapter",
    params: {
      maskType: "none", mask: 0.0, scanline: 0.26, scanPitch: 3.0,
      warp: 0.060, converge: 0.0, bloom: 0.55, bloomRadius: 2.2, vignette: 0.34,
      bright: 1.05, noise: 0.06, mono: [0.35, 1.00, 0.42], monoWhite: 0.55,
      bezelWidth: 0.040, chin: 2.2, knobs: 2,
      bezelColor: [0.520, 0.487, 0.405], bezelLight: [0.675, 0.640, 0.545]
    }
  },
  {
    id: "vt220",
    name: "VT-220",
    subtitle: "P3 amber, serial terminal",
    params: {
      maskType: "none", mask: 0.0, scanline: 0.28, scanPitch: 3.0,
      warp: 0.065, converge: 0.0, bloom: 0.58, bloomRadius: 2.3, vignette: 0.42,
      bright: 1.05, noise: 0.06, mono: [1.00, 0.68, 0.16], monoWhite: 0.50,
      bezelWidth: 0.042, chin: 1.8, knobs: 1,
      bezelColor: [0.545, 0.512, 0.432], bezelLight: [0.700, 0.668, 0.575]
    }
  },
  {
    id: "broadcast",
    name: "Broadcast",
    subtitle: "slot mask, composite bleed",
    params: {
      maskType: "slot", mask: 0.38, maskPitch: 3.0, slotHeight: 6.0,
      scanline: 0.30, warp: 0.095, converge: 1.10, chromaBleed: 1.9,
      bloom: 0.45, vignette: 0.40, bright: 1.40, noise: 0.09,
      bezelWidth: 0.050, chin: 2.4, knobs: 2, grille: true,
      bezelRadius: 0.085, glassRadius: 0.075,
      bezelColor: [0.240, 0.228, 0.212], bezelLight: [0.400, 0.384, 0.358]
    }
  }
]

function isUserId(id) { return String(id || "").indexOf(USER_PREFIX) === 0 }

function byId(id, userPresets) {
  var i
  if (userPresets) {
    for (i = 0; i < userPresets.length; i++)
      if (userPresets[i].id === id) return userPresets[i]
  }
  for (i = 0; i < PRESETS.length; i++)
    if (PRESETS[i].id === id) return PRESETS[i]
  return PRESETS[0]
}

// A preset's declared params layered onto the defaults, then any user overrides.
function resolve(id, overrides, userPresets) {
  var preset = byId(id, userPresets)
  var out = {}
  var k
  for (k in DEFAULTS) out[k] = DEFAULTS[k]
  for (k in preset.params) out[k] = preset.params[k]
  if (overrides) for (k in overrides) if (overrides[k] !== undefined) out[k] = overrides[k]
  return out
}

// A unique display name for a saved copy: "My VT-220", then "My VT-220 2"...
function copyName(baseName, userPresets) {
  var want = "My " + baseName
  var taken = {}
  if (userPresets) for (var i = 0; i < userPresets.length; i++) taken[userPresets[i].name] = true
  if (!taken[want]) return want
  for (var n = 2; n < 100; n++) if (!taken[want + " " + n]) return want + " " + n
  return want + " " + Date.now()
}
