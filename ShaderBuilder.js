.pragma library

// Generates the Hyprland screen shader from a resolved preset.
//
// Uniform names are matched by string in Hyprland's
// Shader.cpp:getUniformLocations(), so they must be spelled exactly:
//   tex, fullSize (aliases screen_size/screenSize), wl_output, time.
//
// Two rules the whole design hangs on:
//
// 1. The picture is always sampled 1:1. The cabinet does not shrink it (the
//    service reserves the margins with layer-shell exclusive zones instead, so
//    the desktop is laid out inside the glass), and curvature is drawn at the
//    glass — rounded corners, curved edge shading — never applied to the
//    sample coordinates. Hyprland does not warp input, so any displaced pixel
//    is a pixel that no longer sits where it clicks.
//
// 2. The static variant never declares `time`. In
//    OpenGL.cpp:renderToOutputInternal(), `time` is fixed at 0.0 unless
//    debug:damage_tracking is 0, and merely declaring it makes Hyprland warn
//    that damage tracking must be disabled — which it says will "massively
//    increase GPU utilization". Timed variants exist for the brief power
//    transients (damage tracking restored afterwards) and for the opt-in
//    "live" mode — flicker above zero — which pays that cost knowingly for
//    as long as it is set.

function clamp(v, lo, hi) {
  v = Number(v)
  if (isNaN(v)) return lo
  return Math.max(lo, Math.min(hi, v))
}

// GLSL needs a decimal point on every float literal.
function f(v) { return Number(v).toFixed(5) }

function vec3(c) { return "vec3(" + f(c[0]) + ", " + f(c[1]) + ", " + f(c[2]) + ")" }

// Every value is clamped here so a generated shader can never fail to compile
// or produce something unusable. A shader that fails to compile puts a Hyprland
// error overlay on screen, so this is the only guard that matters.
// The rails that would displace the bar are capped at a slim lip. Omarchy's
// panel popups (Ui/KeyboardPanel.qml) place their cards and forward bar-strip
// clicks assuming the bar is glued to the screen edge; a fat reserved rail
// moves the bar and every plugin's drawer opens offset and misforwards. A
// ~6-logical-px lip stays inside the popups' own gap, so nothing misbehaves,
// and the chin — which displaces nothing — carries the cabinet's character.
var LIP = 0.010

function sanitize(p, light, bezel) {
  var dim = light ? clamp(p.lightScale, 0.0, 1.0) : 1.0
  var cabinet = (bezel !== false)
  var fw = cabinet ? clamp(p.bezelWidth, 0.0, 0.12) : 0.0
  // An even frame drops the LIP cap and the deep chin, so all four sides are
  // the same width. It costs what the cap was buying: the rails now displace
  // the bar, and plugin drawers open offset from their icons. The panel says so.
  var even = cabinet && !!p.evenFrame
  return {
    cabinet: cabinet,
    evenFrame: even,
    bezelWidth: fw,
    railWidth: cabinet ? (even ? fw : Math.min(fw, LIP)) : 0.0,
    trueWarp: !!p.trueWarp,
    // The chin carries the machine's furniture, which needs the depth. An even
    // frame has nowhere to put it, so the furniture goes with it.
    chin: (cabinet && !even) ? clamp(p.chin === undefined ? 1.6 : p.chin, 1.0, 3.0) : 1.0,
    bezelRadius: clamp(p.bezelRadius, 0.0, 0.5),
    glassRadius: clamp(p.glassRadius, 0.0, 0.5),
    bezelColor: p.bezelColor, bezelLight: p.bezelLight,
    curve: clamp(p.warp, 0.0, 0.12),
    scanline: clamp(p.scanline, 0.0, 0.8) * dim,
    scanPitch: clamp(p.scanPitch, 1.5, 12.0),
    mask: clamp(p.mask, 0.0, 1.0) * dim,
    maskPitch: clamp(p.maskPitch, 2.0, 12.0),
    maskType: p.maskType,
    slotHeight: clamp(p.slotHeight, 1.0, 24.0),
    damperWires: Math.round(clamp(p.damperWires, 0, 4)),
    badge: !!p.badge && !even,
    knobs: even ? 0 : Math.round(clamp(p.knobs || 0, 0, 2)),
    buttons: even ? 0 : Math.round(clamp(p.buttons || 0, 0, 6)),
    grille: !!p.grille && !even,
    lamp: !even,
    bloom: clamp(p.bloom, 0.0, 1.5),
    bloomRadius: clamp(p.bloomRadius, 0.0, 6.0),
    vignette: clamp(p.vignette, 0.0, 1.0),
    converge: clamp(p.converge, 0.0, 4.0),
    chromaBleed: clamp(p.chromaBleed, 0.0, 6.0),
    bright: clamp(p.bright, 0.5, 2.5),
    contrast: clamp(p.contrast === undefined ? 1.0 : p.contrast, 0.3, 2.0),
    saturation: clamp(p.saturation === undefined ? 1.0 : p.saturation, 0.0, 2.0),
    noise: clamp(p.noise === undefined ? 0.0 : p.noise, 0.0, 0.6),
    flicker: clamp(p.flicker === undefined ? 0.0 : p.flicker, 0.0, 0.5),
    glare: clamp(p.glare, 0.0, 0.4),
    mono: p.mono || null,
    monoWhite: clamp(p.monoWhite, 0.0, 1.0)
  }
}

function maskFunction(p) {
  if (p.maskType === "none" || p.mask <= 0.0)
    return "vec3 phosphorMask(vec2 fc) { return vec3(1.0); }"

  var body = ""
  if (p.maskType === "grille") {
    // Continuous vertical RGB stripes: no vertical structure at all.
    body = "  float ph = fract(fc.x / MASK_PITCH);\n"
  } else if (p.maskType === "slot") {
    // Alternating rows of the triad are offset by half a pitch.
    body = "  float row = floor(fc.y / SLOT_HEIGHT);\n" +
           "  float ph = fract(fc.x / MASK_PITCH + 0.5 * mod(row, 2.0));\n"
  } else {
    // Shadow mask: triads staggered every row, so the dots sit on a lattice.
    body = "  float row = floor(fc.y / SLOT_HEIGHT);\n" +
           "  float ph = fract(fc.x / MASK_PITCH + 0.3333 * mod(row, 3.0));\n"
  }

  var out = "vec3 phosphorMask(vec2 fc) {\n" + body +
            "  vec3 m = 0.5 + 0.5 * cos(6.28318 * (ph - vec3(0.0, 1.0 / 3.0, 2.0 / 3.0)));\n"

  if (p.maskType !== "grille") {
    // Dot masks also darken between rows, grilles do not.
    out += "  float vgap = 0.5 + 0.5 * cos(6.28318 * fc.y / SLOT_HEIGHT);\n" +
           "  m *= 0.72 + 0.28 * vgap;\n"
  }
  return out + "  return mix(vec3(1.0), m * 1.6, MASK);\n}"
}

function monoFunction(p) {
  if (!p.mono) return ""
  // Map by relative luminance so the theme's own contrast hierarchy survives:
  // a bright accent stays bright, a muted comment stays muted. Real phosphor
  // desaturates toward white as beam current rises, so the ramp whitens at the
  // top end rather than clipping to saturated colour.
  return "\nvec3 monoMap(vec3 c) {\n" +
         "  float y = clamp(luma(c), 0.0, 1.0);\n" +
         "  vec3 lit = MONO * y;\n" +
         "  return mix(lit, vec3(1.0), pow(y, 2.4) * MONO_WHITE);\n" +
         "}\n"
}

// The cabinet plastic, drawn where dGlass > 0. Front-panel furniture lives on
// the chin: badge, control knobs, a row of panel buttons, speaker slots, and
// the power lamp — which is what makes one cabinet read as a different machine
// from another rather than a recoloured frame.
function cabinetBlock(p, transient) {
  var s = ""
  s += "  if (dGlass > 0.0) {\n"
  s += "    float lit   = clamp(0.5 - ca.y * 0.55 - ca.x * 0.18, 0.0, 1.0);\n"
  s += "    vec3  frame = mix(BEZEL_COLOR, BEZEL_LIGHT, lit * lit);\n\n"
  s += "    // A bright lip along the top-left of the opening and a shadow along\n"
  s += "    // the bottom-right is what makes moulded plastic read as three-dimensional.\n"
  s += "    vec2  n      = normalize(ca - vec2(0.0, CY) + 1e-6);\n"
  s += "    float lip    = smoothstep(0.024, 0.0, dGlass);\n"
  s += "    float facing = clamp(-n.y * 0.7 - n.x * 0.3, -1.0, 1.0);\n"
  s += "    frame += lip * facing * vec3(0.26, 0.25, 0.22);\n"
  s += "    frame -= lip * 0.10 * vec3(0.10);\n\n"
  s += "    float grain = fract(sin(dot(floor(ca * 420.0), vec2(12.9898, 78.233))) * 43758.5453);\n"
  s += "    frame *= 0.965 + 0.07 * grain;\n\n"
  s += "    // The chin: the front panel below the glass.\n"
  s += "    float chinTop = 1.0 - FB;\n"
  s += "    float chinMid = 1.0 - FB * 0.5;\n"
  s += "    float inChin  = step(chinTop, ca.y);\n\n"

  if (p.badge) {
    s += "    // Maker's badge, centre of the chin: a raised plate with a dark inlay.\n"
    s += "    float bplate = sdRoundBox(ca - vec2(0.0, chinMid), vec2(0.085, FB * 0.16), 0.012);\n"
    s += "    frame = mix(frame, BEZEL_LIGHT * 1.08, inChin * smoothstep(aa, 0.0, bplate));\n"
    s += "    float binlay = sdRoundBox(ca - vec2(0.0, chinMid), vec2(0.068, FB * 0.07), 0.008);\n"
    s += "    frame = mix(frame, BEZEL_COLOR * 0.55, inChin * smoothstep(aa, 0.0, binlay));\n\n"
  }
  if (p.knobs > 0) {
    s += "    // Front control knobs — brightness and contrast, where they belong.\n"
    s += "    for (int k = 0; k < " + p.knobs + "; k++) {\n"
    s += "      vec2  kpos = vec2(hx - 0.085 - float(k) * 0.085, chinMid);\n"
    s += "      float kd   = length(ca - kpos);\n"
    s += "      float kr   = FB * 0.20;\n"
    s += "      frame = mix(frame, BEZEL_COLOR * 0.62, inChin * smoothstep(aa, 0.0, kd - kr));\n"
    s += "      frame = mix(frame, BEZEL_LIGHT * 0.95, inChin * smoothstep(aa, 0.0, kd - kr * 0.55));\n"
    s += "      // Indicator notch\n"
    s += "      float nd = length(ca - kpos - vec2(0.0, -kr * 0.62));\n"
    s += "      frame = mix(frame, BEZEL_COLOR * 0.45, inChin * smoothstep(aa, 0.0, nd - kr * 0.14));\n"
    s += "    }\n\n"
  }
  if (p.buttons > 0) {
    s += "    // A row of small panel buttons, right of centre.\n"
    s += "    for (int b = 0; b < " + p.buttons + "; b++) {\n"
    s += "      vec2  bpos = vec2(hx - 0.12 - float(b) * 0.038, chinMid);\n"
    s += "      float bd = sdRoundBox(ca - bpos, vec2(0.011, FB * 0.10), 0.006);\n"
    s += "      frame = mix(frame, BEZEL_COLOR * 0.70, inChin * smoothstep(aa, 0.0, bd));\n"
    s += "      frame = mix(frame, BEZEL_LIGHT * 0.90, inChin * smoothstep(aa, 0.0, bd + 0.004));\n"
    s += "    }\n\n"
  }
  if (p.grille) {
    s += "    // Speaker slots on the left of the chin.\n"
    s += "    float gx = ca.x + hx - 0.20;\n"
    s += "    float inG = step(0.0, gx) * step(gx, 0.30) * inChin\n"
    s += "              * step(chinTop + FB * 0.18, ca.y) * step(ca.y, 1.0 - FB * 0.18);\n"
    s += "    float slots = 0.5 + 0.5 * cos(gx * 180.0);\n"
    s += "    frame *= 1.0 - 0.34 * inG * smoothstep(0.35, 0.75, slots);\n\n"
  }
  if (p.lamp) {
    s += "    // Power lamp, bottom right.\n"
    s += "    vec2  led  = ca - vec2(hx - 0.035, chinMid);\n"
    s += "    float lamp = smoothstep(0.010, 0.0, length(led));\n"
    s += "    frame += lamp * vec3(0.35, 0.95, 0.45);\n"
    s += "    frame += vec3(0.10, 0.28, 0.13) * smoothstep(0.030, 0.0, length(led));\n\n"
  }
  s += "    frame *= 1.0 - smoothstep(-0.026, 0.0, dOuter) * 0.80;\n"
  s += "    frame *= 1.0 - smoothstep(0.0, aa, dOuter);\n"
  s += "    fragColor = vec4(frame" + (transient ? " * env" : "") + ", 1.0);\n"
  s += "    return;\n"
  s += "  }\n\n"
  return s
}

// mode: "static" | "on" | "off" | "live"
// "on"/"off" are the brief power transients; "live" is the static picture plus
// time-driven grain and flicker, for tubes tuned with flicker above zero.
// Every mode that declares `time` must be applied with damage tracking 0.
function build(params, opts) {
  opts = opts || {}
  var p = sanitize(params, !!opts.light, opts.bezel)
  var mode = opts.mode || "static"
  var transient = (mode === "on" || mode === "off")
  var live = (mode === "live")
  var timed = transient || live
  var monitorId = (opts.monitorId === undefined || opts.monitorId === null) ? -1 : opts.monitorId

  var s = ""
  s += "#version 300 es\n"
  s += "precision highp float;\n\n"
  s += "// Generated by Phosphor. Edits here are overwritten on the next change.\n"
  s += "in vec2 v_texcoord;\n"
  s += "uniform sampler2D tex;\n"
  s += "uniform vec2 fullSize;\n"
  if (monitorId >= 0) s += "uniform int wl_output;\n"
  if (timed) s += "uniform float time;\n"
  s += "\nlayout(location = 0) out vec4 fragColor;\n\n"

  var ft = p.railWidth
  var fb = p.bezelWidth * p.chin
  s += "const float F            = " + f(p.railWidth) + ";\n"
  s += "const float FB           = " + f(fb) + ";\n"
  s += "const float CY           = " + f((ft - fb) / 2) + ";\n"
  s += "const float HY           = " + f(1 - (ft + fb) / 2) + ";\n"
  s += "const float BEZEL_RADIUS = " + f(p.bezelRadius) + ";\n"
  s += "const float GLASS_RADIUS = " + f(p.glassRadius + p.curve * 1.3) + ";\n"
  s += "const float CURVE        = " + f(p.curve) + ";\n"
  s += "const float SCANLINE     = " + f(p.scanline) + ";\n"
  s += "const float SCAN_PITCH   = " + f(p.scanPitch) + ";\n"
  s += "const float MASK         = " + f(p.mask) + ";\n"
  s += "const float MASK_PITCH   = " + f(p.maskPitch) + ";\n"
  s += "const float SLOT_HEIGHT  = " + f(p.slotHeight) + ";\n"
  s += "const float BLOOM        = " + f(p.bloom) + ";\n"
  s += "const float BLOOM_RADIUS = " + f(p.bloomRadius) + ";\n"
  s += "const float VIGNETTE     = " + f(p.vignette) + ";\n"
  s += "const float CONVERGE     = " + f(p.converge) + ";\n"
  s += "const float CHROMA_BLEED = " + f(p.chromaBleed) + ";\n"
  s += "const float BRIGHT       = " + f(p.bright) + ";\n"
  if (p.contrast !== 1.0)   s += "const float CONTRAST     = " + f(p.contrast) + ";\n"
  if (p.saturation !== 1.0) s += "const float SAT          = " + f(p.saturation) + ";\n"
  if (p.noise > 0.0)        s += "const float NOISE        = " + f(p.noise) + ";\n"
  if (live && p.flicker > 0.0) s += "const float FLICKER      = " + f(p.flicker) + ";\n"
  s += "const float GLARE        = " + f(p.glare) + ";\n"
  s += "const vec3  BEZEL_COLOR  = " + vec3(p.bezelColor) + ";\n"
  s += "const vec3  BEZEL_LIGHT  = " + vec3(p.bezelLight) + ";\n"
  if (p.trueWarp) s += "const float BEND         = " + f(p.curve * 1.2) + ";\n"
  if (p.mono) {
    s += "const vec3  MONO         = " + vec3(p.mono) + ";\n"
    s += "const float MONO_WHITE   = " + f(p.monoWhite) + ";\n"
  }
  s += "\n"

  s += "float sdRoundBox(vec2 q, vec2 b, float r) {\n" +
       "  vec2 d = abs(q) - b + r;\n" +
       "  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;\n" +
       "}\n\n"
  s += "float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }\n\n"
  s += maskFunction(p) + "\n"
  s += monoFunction(p) + "\n"

  s += "void main() {\n"
  if (monitorId >= 0) {
    s += "  // Phosphor is limited to one output; every other screen passes through.\n"
    s += "  if (wl_output != " + Math.round(monitorId) + ") {\n" +
         "    fragColor = texture(tex, v_texcoord);\n    return;\n  }\n\n"
  }
  if (mode === "on") {
    s += "  // Power-on, the terminal way: the desktop cuts to black almost at\n"
    s += "  // once, holds properly dark while the tube warms, then the picture\n"
    s += "  // rises out of the black — slow at first, the way a phosphor comes up\n"
    s += "  // to brightness. Deliberately not the TV line-and-dot.\n"
    s += "  if (time < 0.22) {\n"
    s += "    float raw = 1.0 - smoothstep(0.0, 0.04, time);\n"
    s += "    fragColor = vec4(texture(tex, v_texcoord).rgb * raw, 1.0);\n"
    s += "    return;\n"
    s += "  }\n"
    s += "  float env = smoothstep(0.22, 0.62, time);\n"
    s += "  env *= env;\n\n"
  } else if (mode === "off") {
    s += "  // Power-off: the phosphor loses its energy fast and the screen goes\n"
    s += "  // dark; the service clears the shader while it is black, so the plain\n"
    s += "  // desktop returns in one step with no second fade. Squaring this\n"
    s += "  // collapsed it inside 40ms, which read as a snap rather than a decay:\n"
    s += "  // the curve wants to be visible, just brief.\n"
    s += "  float env = pow(1.0 - smoothstep(0.0, 0.15, time), 1.3);\n\n"
  }
  s += "  vec2 res    = max(fullSize, vec2(1.0));\n"
  s += "  vec2 texel  = 1.0 / res;\n"
  s += "  float aspect = res.x / res.y;\n\n"
  s += "  vec2 c  = v_texcoord * 2.0 - 1.0;\n"
  s += "  vec2 ca = vec2(c.x * aspect, c.y);\n"
  s += "  float hx = aspect - F;\n"
  s += "  float aa = 2.0 / res.y;\n\n"
  s += "  float dGlass = sdRoundBox(ca - vec2(0.0, CY), vec2(hx, HY), GLASS_RADIUS);\n"
  s += "  float dOuter = sdRoundBox(ca, vec2(aspect, 1.0), BEZEL_RADIUS);\n\n"
  s += "  // Position inside the glass, -1..1 on both axes. The desktop itself is\n"
  s += "  // laid out inside this rectangle (the service reserves the margins), so\n"
  s += "  // the picture is sampled exactly where it already is: 1:1, no inset.\n"
  s += "  vec2 gn = (ca - vec2(0.0, CY)) / vec2(hx, HY);\n\n"

  if (p.cabinet) s += cabinetBlock(p, transient)

  if (p.trueWarp && p.curve > 0.0) {
    s += "  // True curvature, chosen with eyes open: the picture itself bends,\n"
    s += "  // so input near the edges lands slightly off the drawn position.\n"
    s += "  vec2 gs = gn * (1.0 + BEND * dot(gn, gn)) / (1.0 + 2.0 * BEND);\n"
    s += "  vec2 caS = gs * vec2(hx, HY) + vec2(0.0, CY);\n"
    s += "  vec2 uv  = vec2(caS.x / aspect, caS.y) * 0.5 + 0.5;\n"
    s += "  vec2 gEff = gs;\n\n"
  } else {
    s += "  vec2 uv = v_texcoord;\n"
    s += "  vec2 gEff = gn;\n\n"
  }

  s += "  // ---- picture ----------------------------------------------------\n"
  s += "  vec3 col;\n"
  s += "  {\n"
  s += "    // Convergence error: the guns misregister further from centre.\n"
  s += "    vec2 dir = gEff * CONVERGE;\n"
  s += "    col.r = texture(tex, uv + dir * texel).r;\n"
  s += "    col.g = texture(tex, uv).g;\n"
  s += "    col.b = texture(tex, uv - dir * texel).b;\n"
  if (p.chromaBleed > 0.0) {
    s += "\n    // Composite chroma smears sideways while luma stays put.\n"
    s += "    vec3 left = texture(tex, uv - vec2(CHROMA_BLEED * texel.x, 0.0)).rgb;\n"
    s += "    float y0 = luma(col);\n"
    s += "    col = mix(col, vec3(y0) + (left - vec3(luma(left))), 0.45);\n"
  }
  if (p.bloom > 0.0) {
    s += "\n    // Bloom: bright phosphor spills into its neighbours.\n"
    s += "    vec2 br = BLOOM_RADIUS * texel;\n"
    s += "    vec3 blur = texture(tex, uv + vec2( br.x, 0.0)).rgb\n"
    s += "              + texture(tex, uv + vec2(-br.x, 0.0)).rgb\n"
    s += "              + texture(tex, uv + vec2(0.0,  br.y)).rgb\n"
    s += "              + texture(tex, uv + vec2(0.0, -br.y)).rgb;\n"
    s += "    blur *= 0.25;\n"
    s += "    col += blur * luma(blur) * BLOOM;\n"
  }
  if (p.saturation !== 1.0 || p.contrast !== 1.0) {
    s += "\n    // Front-panel picture controls. Saturation before the mono map is a\n"
    s += "    // no-op on monochrome tubes (the map reads luminance, which mixing\n"
    s += "    // toward grey preserves), so the same slider is safe on any tube.\n"
    if (p.saturation !== 1.0) s += "    col = mix(vec3(luma(col)), col, SAT);\n"
    if (p.contrast !== 1.0)   s += "    col = max((col - 0.5) * CONTRAST + 0.5, 0.0);\n"
  }
  if (p.mono) s += "\n    col = monoMap(col);\n"
  s += "  }\n\n"

  s += "  col *= phosphorMask(gl_FragCoord.xy);\n"
  s += "  col *= 1.0 - SCANLINE * (0.5 + 0.5 * cos(6.28318 * gl_FragCoord.y / SCAN_PITCH));\n"
  if (p.damperWires > 0) {
    s += "\n  // Damper wires: the tensioned filaments that steady an aperture\n"
    s += "  // grille cast faint shadows across the picture. Nobody ever includes them.\n"
    s += "  float wireN = " + f(p.damperWires + 1) + ";\n"
    s += "  float wy = fract((gEff.y * 0.5 + 0.5) * wireN);\n"
    s += "  float wire = smoothstep(0.012, 0.0, min(wy, 1.0 - wy) / wireN);\n"
    s += "  col *= 1.0 - 0.16 * wire;\n"
  }
  s += "\n  col *= BRIGHT;\n"
  s += "  col *= clamp(1.0 - VIGNETTE * dot(gEff, gEff), 0.0, 1.0);\n"
  s += "\n  // Curvature is an illusion painted at the glass: the edges of the tube\n"
  s += "  // fall away into shadow, the corners round off, the picture never moves.\n"
  s += "  float edge = max(abs(gn.x), abs(gn.y));\n"
  s += "  col *= 1.0 - CURVE * 4.5 * smoothstep(0.86, 1.0, edge);\n"
  if (p.cabinet) s += "  col *= smoothstep(0.0, 0.016, -dGlass);\n"
  if (p.noise > 0.0) {
    s += "\n  // Grain. Without `time` this is a fixed per-pixel texture — glass and\n"
    s += "  // phosphor grain — because the static shader is never fed a clock. In\n"
    s += "  // the timed variants the seed moves and it becomes analog noise.\n"
    if (timed) s += "  float gr = fract(sin(dot(gl_FragCoord.xy + vec2(mod(time, 61.0) * 97.0), vec2(12.9898, 78.233))) * 43758.5453);\n"
    else       s += "  float gr = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);\n"
    s += "  col *= 1.0 - NOISE * (gr - 0.5);\n"
  }
  if (live && p.flicker > 0.0) {
    s += "\n  // Flicker: a small random brightness dip per frame, like a tube whose\n"
    s += "  // regulation is going. Whole-screen uniform, so it costs nothing extra.\n"
    s += "  float fl = fract(sin(floor(time * 72.0) * 7.13) * 43758.5453);\n"
    s += "  col *= 1.0 - FLICKER * (0.2 + 0.8 * fl) * 0.30;\n"
  }
  s += "  col += GLARE * smoothstep(1.2, -0.4, ca.x + ca.y * 1.6);\n"
  if (transient) s += "  col *= env;\n"
  s += "\n  fragColor = vec4(col, 1.0);\n"
  s += "}\n"
  return s
}
