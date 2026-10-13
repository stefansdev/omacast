.pragma library

// Pure search and catalog logic for Omacast. Everything here is data in, data
// out, so the QML side only wires sources, processes and rendering together.
//
// A result row looks like:
//   { id, kind, title, subtitle, accessory, glyph, image, keywords,
//     actions: [{ title, op, arg, arg2, key }] }
// The first action is the primary (Enter); the rest show in the action panel.

function stripJsonc(raw) {
  var text = String(raw || "")
  var out = ""
  var inString = false
  for (var i = 0; i < text.length; i++) {
    var c = text[i]
    var n = text[i + 1]
    if (inString) {
      out += c
      if (c === "\\") { out += n || ""; i++ }
      else if (c === "\"") inString = false
      continue
    }
    if (c === "\"") { inString = true; out += c; continue }
    if (c === "/" && n === "/") { while (i < text.length && text[i] !== "\n") i++; out += "\n"; continue }
    if (c === "/" && n === "*") { i += 2; while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++; i++; continue }
    out += c
  }
  // Trailing commas.
  return out.replace(/,(\s*[}\]])/g, "$1")
}

function parseConfig(raw) {
  try {
    var value = JSON.parse(stripJsonc(raw))
    return value && typeof value === "object" ? value : {}
  } catch (e) {
    return {}
  }
}

// Shallow per-key merge: user values replace defaults; missing keys fall back.
function mergeConfig(defaults, user) {
  var merged = {}
  var key
  for (key in defaults) merged[key] = defaults[key]
  for (key in user) {
    var d = defaults[key]
    var u = user[key]
    if (d && u && typeof d === "object" && typeof u === "object" && !Array.isArray(d) && !Array.isArray(u)) {
      var inner = {}
      var k
      for (k in d) inner[k] = d[k]
      for (k in u) inner[k] = u[k]
      merged[key] = inner
    } else {
      merged[key] = u
    }
  }
  return merged
}

function expandHome(path, home) {
  var p = String(path || "")
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.substring(1)
  return p
}

// ------------------------------------------------------------------ fuzzy

function isBoundary(text, index) {
  if (index <= 0) return true
  var prev = text[index - 1]
  var cur = text[index]
  if (/[\s\-_.\/:›]/.test(prev)) return true
  // camelCase boundary in the original casing
  return prev === prev.toLowerCase() && cur !== cur.toLowerCase()
}

// Returns a score >= 0 for a match (higher is better) or -1 for no match.
function fuzzyScore(query, original) {
  var q = String(query || "").toLowerCase().trim()
  var raw = String(original || "")
  var t = raw.toLowerCase()
  if (!q) return 0
  if (!t) return -1
  if (t === q) return 1000
  if (t.indexOf(q) === 0) return 900 - Math.min(t.length, 80)

  var at = t.indexOf(q)
  while (at > 0 && !isBoundary(raw, at)) at = t.indexOf(q, at + 1)
  if (at > 0) return 800 - at - Math.min(t.length, 80) * 0.2
  at = t.indexOf(q)
  if (at > 0) return 600 - at - Math.min(t.length, 80) * 0.2

  // Subsequence with bonuses for word starts and runs ("vsc" → Visual Studio Code).
  // Scattered letters only count when most of them land on word starts or
  // continue a run; otherwise long titles would match almost anything.
  var score = 0
  var ti = 0
  var run = 0
  var firstHit = -1
  var strong = 0
  var letters = 0
  for (var i = 0; i < q.length; i++) {
    var c = q[i]
    if (c === " ") continue
    letters++
    var found = t.indexOf(c, ti)
    if (found < 0) return -1
    if (firstHit < 0) firstHit = found
    var boundary = isBoundary(raw, found)
    if (found === ti && i > 0) { run++; score += 6 * run; strong++ } else run = 0
    if (boundary) { score += 18; strong += 2 }
    score -= Math.min(found - ti, 12)
    ti = found + 1
  }
  if (strong < letters) return -1
  return Math.max(1, 300 + score - firstHit - Math.min(t.length, 80) * 0.3)
}

// Multi-word queries must match every word somewhere in the row.
function rowScore(query, row) {
  var q = String(query || "").trim()
  if (!q) return 0
  var whole = fuzzyScore(q, row.title)
  var words = q.split(/\s+/)
  var hay = [row.title, row.subtitle || "", (row.keywords || []).join(" ")].join(" ")

  // Multi-word queries: every word must appear as a real substring.
  if (whole < 0 && words.length > 1) {
    var total = 0
    for (var i = 0; i < words.length; i++) {
      var s = fuzzyScore(words[i], hay)
      if (s < 600) return -1
      total += s
    }
    return total / words.length * 0.8
  }

  var best = whole
  var kw = row.keywords || []
  for (var k = 0; k < kw.length; k++) {
    var ks = fuzzyScore(q, kw[k])
    if (ks >= 0) best = Math.max(best, ks * 0.75)
  }
  if (row.subtitle) {
    var ss = fuzzyScore(q, row.subtitle)
    if (ss >= 500) best = Math.max(best, ss * 0.5)
  }
  return best
}

// Rank rows by score plus a usage boost from { id: { count, last } }.
function rank(rows, query, usage, limit) {
  var scored = []
  var now = Date.now()
  for (var i = 0; i < rows.length; i++) {
    var s = rowScore(query, rows[i])
    if (s < 0) continue
    var u = usage && usage[rows[i].id]
    if (u) {
      var ageDays = Math.max(0, (now - (u.last || 0)) / 86400000)
      s += Math.min(u.count || 0, 20) * 6 + Math.max(0, 40 - ageDays * 4)
    }
    s += rows[i].boost || 0
    scored.push({ row: rows[i], score: s })
  }
  scored.sort(function(a, b) {
    if (b.score !== a.score) return b.score - a.score
    return String(a.row.title).localeCompare(String(b.row.title))
  })
  var out = []
  var max = limit || scored.length
  for (var j = 0; j < scored.length && j < max; j++) out.push(scored[j].row)
  return out
}

function recentRows(rows, usage, limit) {
  var withUse = []
  for (var i = 0; i < rows.length; i++) {
    var u = usage && usage[rows[i].id]
    if (u) withUse.push({ row: rows[i], last: u.last || 0 })
  }
  withUse.sort(function(a, b) { return b.last - a.last })
  var out = []
  for (var j = 0; j < withUse.length && j < limit; j++) out.push(withUse[j].row)
  return out
}

// ------------------------------------------------------------- calculator

// Only hand a query to qalc when it plausibly is math or a conversion, so app
// names with numbers in them ("firefox 2") don't produce nonsense answers.
function isCalcQuery(q) {
  var s = String(q || "").trim()
  if (s.length < 2) return false
  if (s[0] === "=") return s.length > 1
  if (!/\d/.test(s)) return false
  if (/^\d+$/.test(s)) return false
  if (/[+\-*\/^×÷%()!]/.test(s)) return true
  if (/\b(to|in|as)\b/i.test(s)) return true
  if (/\b(sqrt|sin|cos|tan|log|ln|abs|round|floor|ceil)\b/i.test(s)) return true
  if (/^0x[0-9a-f]+$/i.test(s) || /^0b[01]+$/i.test(s)) return true
  return false
}

// qalc expression: "12% of 340" → "12% * 340"; "5 km to mi" → "5 km to -mi"
// (the minus disables mixed units, so the answer is one decimal number).
function calcExpression(q) {
  var s = String(q || "").trim()
  if (s[0] === "=") s = s.substring(1).trim()
  s = s.replace(/(\d)\s*%\s+of\s+/gi, "$1% * ")
  s = s.replace(/\s(to|in|as)\s+(?![+\-])([A-Za-z€$£¥])/i, " $1 -$2")
  return s
}

function acceptCalcResult(query, result) {
  var r = String(result || "").trim()
  if (!r) return false
  if (/error|warning|unrecognized|rem\(|undefined/i.test(r)) return false
  var q = String(query || "").trim().replace(/^=/, "").trim()
  if (r.replace(/\s/g, "") === q.replace(/\s/g, "")) return false
  return r.length < 200
}

// --------------------------------------------------------- quicklinks etc.

function fillTemplate(template, query) {
  var encoded = encodeURIComponent(String(query || ""))
  var now = new Date()
  var pad = function(n) { return n < 10 ? "0" + n : "" + n }
  var date = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
  return String(template || "")
    .replace(/\{query\}/g, encoded)
    .replace(/\{argument\}/g, encoded)
    .replace(/\{date\}/g, date)
}

// "gh quickshell" → { keyword: "gh", rest: "quickshell" }
function splitKeyword(q) {
  var s = String(q || "").replace(/^\s+/, "")
  var m = s.match(/^(\S+)\s+([\s\S]+)$/)
  if (!m) return { keyword: s.trim(), rest: "" }
  return { keyword: m[1], rest: m[2].trim() }
}

function slug(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").substring(0, 60) || "note"
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// ---------------------------------------------------------------- catalogs

// [id, title, glyph, keywords]
var WINDOW_LAYOUTS = [
  ["left-half", "Left Half", "󰯋", "snap side split"],
  ["right-half", "Right Half", "󰯊", "snap side split"],
  ["top-half", "Top Half", "󰯈", "snap"],
  ["bottom-half", "Bottom Half", "󰯉", "snap"],
  ["top-left", "Top Left Quarter", "󰍹", "corner"],
  ["top-right", "Top Right Quarter", "󰍹", "corner"],
  ["bottom-left", "Bottom Left Quarter", "󰍹", "corner"],
  ["bottom-right", "Bottom Right Quarter", "󰍹", "corner"],
  ["first-third", "First Third", "󰕰", "left"],
  ["center-third", "Center Third", "󰕰", "middle"],
  ["last-third", "Last Third", "󰕰", "right"],
  ["first-two-thirds", "First Two Thirds", "󰕰", "left"],
  ["last-two-thirds", "Last Two Thirds", "󰕰", "right"],
  ["maximize", "Maximize", "󰊓", "fill full big"],
  ["almost-maximize", "Almost Maximize", "󰊓", "large"],
  ["reasonable-size", "Reasonable Size", "󰊔", "medium"],
  ["center-half", "Center Half", "󰘖", "middle"],
  ["center", "Center", "󰘖", "middle"],
  ["fullscreen", "Toggle Fullscreen", "󰊓", "fullscreen"],
  ["float", "Toggle Floating", "󰖲", "float tile"],
  ["tile", "Restore Tiling", "󰕴", "tile unfloat"],
  ["pin", "Pin Window", "󰐃", "always on top sticky"],
  ["next-display", "Move to Next Display", "󰍺", "monitor screen"],
  ["close", "Close Window", "󰅖", "kill"],
  ["quit-app", "Quit Application", "󰗼", "kill all windows"]
]

function windowLayoutRows() {
  var rows = []
  for (var i = 0; i < WINDOW_LAYOUTS.length; i++) {
    var w = WINDOW_LAYOUTS[i]
    rows.push({
      id: "window." + w[0],
      kind: "window-action",
      title: w[1],
      subtitle: "Window",
      accessory: "Window",
      glyph: w[2],
      keywords: ["window", w[3]],
      actions: [{ title: w[1], op: "window", arg: w[0] }]
    })
  }
  for (var n = 1; n <= 9; n++) {
    rows.push({
      id: "window.workspace-" + n,
      kind: "window-action",
      title: "Move Window to Workspace " + n,
      subtitle: "Window",
      accessory: "Window",
      glyph: "󰍹",
      keywords: ["window", "workspace " + n, "send"],
      actions: [{ title: "Move to Workspace " + n, op: "window", arg: "workspace", arg2: String(n) }]
    })
  }
  return rows
}

// [id, title, glyph, command, keywords, confirm]
var SYSTEM_ACTIONS = [
  ["lock", "Lock Screen", "", "omarchy system lock", "lock", false],
  ["sleep", "Sleep", "󰒲", "systemctl suspend", "suspend", false],
  ["restart", "Restart", "󰜉", "omarchy system reboot", "reboot", true],
  ["shutdown", "Shut Down", "󰐥", "omarchy system shutdown", "power off", true],
  ["logout", "Log Out", "󰍃", "omarchy system logout", "sign out exit", true],
  ["mute", "Toggle Mute", "󰝟", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "sound audio volume", false],
  ["mic", "Toggle Microphone", "󰍭", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", "mute input", false],
  ["nightlight", "Toggle Nightlight", "󰖔", "omarchy toggle nightlight", "night blue light", false],
  ["idle", "Toggle Idle Lock", "󰒳", "omarchy toggle idle", "caffeine awake", false],
  ["trash", "Empty Trash", "󰩺", "gio trash --empty", "delete bin", true],
  ["screenshot", "Take Screenshot", "󰹑", "omarchy capture screenshot", "capture region", false],
  ["bluetooth", "Toggle Bluetooth", "󰂯", "omarchy bluetooth power toggle", "devices wireless", false]
]

function systemRows() {
  var rows = []
  for (var i = 0; i < SYSTEM_ACTIONS.length; i++) {
    var s = SYSTEM_ACTIONS[i]
    rows.push({
      id: "system." + s[0],
      kind: "system",
      title: s[1],
      subtitle: "System",
      accessory: "System",
      glyph: s[2],
      keywords: ["system", s[4]],
      actions: [{ title: s[1], op: s[5] ? "confirm-exec" : "exec", arg: s[3] }]
    })
  }
  return rows
}
