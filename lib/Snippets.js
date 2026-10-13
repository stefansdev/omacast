.pragma library

// Snippet placeholder expansion, Raycast style.
//
//   {clipboard}                      latest clipboard text
//   {date} {time} {datetime} {day}   now, with optional format/offset:
//   {date format="yyyy-MM-dd" offset="+1d"}   offsets: +2h -30m +1d +1w +1M +1y
//   {uuid} {user}
//   {cursor}                         where the caret ends up after pasting
//   {argument name="Recipient" default="team"}   asked for before pasting
//   {snippet name="sig"}             another snippet, by keyword or name
//
// Tinycast's shorter forms also work: {argument:Name}, {snippet:sig}.

function attrs(body) {
  var out = {}
  var re = /(\w+)\s*=\s*"([^"]*)"/g
  var m
  while ((m = re.exec(body)) !== null) out[m[1]] = m[2]
  return out
}

function pad(n, w) {
  var s = String(n)
  while (s.length < (w || 2)) s = "0" + s
  return s
}

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]
var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

// Unicode-style patterns, the subset people actually use.
function formatDate(d, format) {
  return String(format).replace(/yyyy|yy|MMMM|MMM|MM|M|dd|d|EEEE|EEE|HH|H|hh|h|mm|ss|a/g, function(t) {
    switch (t) {
    case "yyyy": return String(d.getFullYear())
    case "yy": return pad(d.getFullYear() % 100)
    case "MMMM": return MONTHS[d.getMonth()]
    case "MMM": return MONTHS[d.getMonth()].substring(0, 3)
    case "MM": return pad(d.getMonth() + 1)
    case "M": return String(d.getMonth() + 1)
    case "dd": return pad(d.getDate())
    case "d": return String(d.getDate())
    case "EEEE": return DAYS[d.getDay()]
    case "EEE": return DAYS[d.getDay()].substring(0, 3)
    case "HH": return pad(d.getHours())
    case "H": return String(d.getHours())
    case "hh": return pad(d.getHours() % 12 || 12)
    case "h": return String(d.getHours() % 12 || 12)
    case "mm": return pad(d.getMinutes())
    case "ss": return pad(d.getSeconds())
    case "a": return d.getHours() < 12 ? "AM" : "PM"
    }
    return t
  })
}

function applyOffset(d, offset) {
  var out = new Date(d.getTime())
  var re = /([+-]\d+)\s*([mhdwMy])/g
  var m
  while ((m = re.exec(String(offset || ""))) !== null) {
    var n = parseInt(m[1], 10)
    switch (m[2]) {
    case "m": out.setMinutes(out.getMinutes() + n); break
    case "h": out.setHours(out.getHours() + n); break
    case "d": out.setDate(out.getDate() + n); break
    case "w": out.setDate(out.getDate() + n * 7); break
    case "M": out.setMonth(out.getMonth() + n); break
    case "y": out.setFullYear(out.getFullYear() + n); break
    }
  }
  return out
}

function uuid() {
  var h = "0123456789abcdef"
  var s = ""
  for (var i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) { s += "-"; continue }
    if (i === 14) { s += "4"; continue }
    var r = Math.floor(Math.random() * 16)
    s += h[i === 19 ? (r & 3) | 8 : r]
  }
  return s
}

// Normalise the short forms so one parser handles both.
function normalise(text) {
  return String(text || "")
    .replace(/\{argument:([^}]+)\}/g, function(_, n) { return '{argument name="' + n.trim() + '"}' })
    .replace(/\{snippet:([^}]+)\}/g, function(_, n) { return '{snippet name="' + n.trim() + '"}' })
}

// The argument names a snippet asks for, in order, with defaults.
function argumentsOf(text, snippets, depth) {
  var seen = {}
  var out = []
  var body = resolveNested(normalise(text), snippets || [], depth || 0)
  var re = /\{argument\s+([^}|]*)(?:\|[^}]*)?\}/g
  var m
  while ((m = re.exec(body)) !== null) {
    var a = attrs(m[1])
    if (!a.name || seen[a.name]) continue
    seen[a.name] = true
    var options = a.options ? a.options.split(",").map(function(o) { return o.trim() }).filter(function(o) { return o.length > 0 }) : []
    out.push({ name: a.name, value: a["default"] || (options[0] || ""), options: options })
  }
  return out
}

function findSnippet(snippets, name) {
  for (var i = 0; i < snippets.length; i++) {
    var s = snippets[i]
    if (s.keyword === name || s.name === name) return s
  }
  return null
}

function resolveNested(text, snippets, depth) {
  if (depth > 5) return text
  return text.replace(/\{snippet\s+([^}]*)\}/g, function(all, body) {
    var target = findSnippet(snippets, attrs(body).name || "")
    return target ? resolveNested(normalise(target.text), snippets, depth + 1) : ""
  })
}

// Returns { text, cursorBack } where cursorBack is how many characters the
// caret must move left after pasting to land on {cursor}.
function expand(text, options) {
  var opts = options || {}
  var values = opts.arguments || {}
  var now = opts.now ? new Date(opts.now) : new Date()
  var body = resolveNested(normalise(text), opts.snippets || [], 0)
  // Arguments sharing a name share one value; the first default wins.
  var shared = {}
  var declared = argumentsOf(body, [], 0)
  for (var d = 0; d < declared.length; d++) shared[declared[d].name] = declared[d].value

  body = body.replace(/\{(clipboard|date|time|datetime|day|weekday|uuid|user|argument)((?:\s+[^}|]*)?)((?:\s*\|\s*[\w-]+)*)\s*\}/g, function(all, kind, rest, pipes) {
    var a = attrs(rest || "")
    var when = a.offset ? applyOffset(now, a.offset) : now
    var value = all
    switch (kind) {
    case "clipboard": value = String(opts.clipboard || ""); break
    case "date": value = formatDate(when, a.format || "yyyy-MM-dd"); break
    case "time": value = formatDate(when, a.format || "HH:mm"); break
    case "datetime": value = formatDate(when, a.format || "yyyy-MM-dd HH:mm"); break
    case "day":
    case "weekday": value = formatDate(when, a.format || "EEEE"); break
    case "uuid": value = uuid(); break
    case "user": value = String(opts.user || ""); break
    case "argument":
      var v = values[a.name]
      var first = a.options ? a.options.split(",")[0].trim() : ""
      value = v !== undefined && v !== "" ? String(v) : String(a["default"] || first || shared[a.name] || "")
      break
    }
    return applyModifiers(value, pipes)
  })

  var marker = body.indexOf("{cursor}")
  var cursorBack = 0
  if (marker >= 0) {
    body = body.replace(/\{cursor\}/g, function(m, offset) { return offset === marker ? "\u0000" : "" })
    var at = body.indexOf("\u0000")
    body = body.replace("\u0000", "")
    cursorBack = body.length - at
  }
  return { text: body, cursorBack: cursorBack }
}

// Raycast pipe modifiers: {clipboard | trim | uppercase}
function applyModifiers(value, pipes) {
  var out = String(value)
  var names = String(pipes || "").split("|").map(function(p) { return p.trim().toLowerCase() }).filter(function(p) { return p.length > 0 })
  for (var i = 0; i < names.length; i++) {
    switch (names[i]) {
    case "uppercase": out = out.toUpperCase(); break
    case "lowercase": out = out.toLowerCase(); break
    case "trim": out = out.trim(); break
    case "percent-encode": out = encodeURIComponent(out); break
    case "json-stringify": out = JSON.stringify(out); break
    case "raw": break
    }
  }
  return out
}

// Short single-line preview for lists.
function preview(text) {
  return String(text || "").replace(/\s+/g, " ").trim().substring(0, 90)
}
