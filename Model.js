// Pure helpers for Panel.qml; no QML types in here.

function parse(text, fallback) {
  try {
    var data = JSON.parse(String(text || ""))
    return data && typeof data === "object" ? data : fallback
  } catch (e) {
    return fallback
  }
}

function compactCount(n) {
  n = Number(n) || 0
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, "") + " M"
  if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1).replace(/\.0$/, "") + "k"
  return String(n)
}

var releaseLabels = { 1: "", 2: "Beta", 3: "Alpha" }

function releaseLabel(type) {
  return releaseLabels[type] || ""
}

// modId -> update entry, for quick lookup from list rows.
function updateMap(updates) {
  var map = {}
  for (var i = 0; i < (updates || []).length; i++) map[String(updates[i].modId)] = updates[i]
  return map
}

function shortDate(iso) {
  var s = String(iso || "")
  return s.length >= 10 ? s.slice(8, 10) + "." + s.slice(5, 7) + "." + s.slice(0, 4) : ""
}

// The last path segment keeps long wine paths readable in the hero.
function shortPath(path) {
  var s = String(path || "")
  var i = s.indexOf("/drive_c/")
  return i >= 0 ? "…" + s.slice(i) : s.replace(/^\/home\/[^/]+/, "~")
}
