function asArray(value) {
  return Array.isArray(value) ? value : []
}

function plainMetadata(value, maxLength) {
  var limit = Math.max(1, Math.min(512, Number(maxLength) || 256))
  return String(value || "")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/[<>]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit)
}

function safeArtworkCandidate(value) {
  var url = String(value || "")
  var match = url.match(/^file:\/\/(\/tmp\/\.org\.chromium\.Chromium\.[A-Za-z0-9_-]{6,64})$/)
  return match ? { url: url, path: match[1] } : { url: "", path: "" }
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function dbusInstancePid(dbusName) {
  var match = String(dbusName || "").match(/\.instance([0-9]+)$/)
  return match ? Number(match[1]) : 0
}

function appleMusicPids(rawClients) {
  var clients = rawClients
  if (typeof rawClients === "string") {
    try { clients = JSON.parse(rawClients) }
    catch (_) { return [] }
  }

  var result = []
  var seen = {}
  var list = asArray(clients)
  for (var i = 0; i < list.length; i++) {
    var client = list[i] || {}
    var haystack = String(client.class || "") + " " + String(client.initialClass || "")
    if (haystack.toLowerCase().indexOf("music.apple.com") === -1) continue
    var pid = Number(client.pid || 0)
    if (pid > 0 && !seen[pid]) {
      result.push(pid)
      seen[pid] = true
    }
  }
  return result
}

function isApplePlayer(player, pids) {
  var pid = dbusInstancePid(player && player.dbusName)
  return pid > 0 && asArray(pids).indexOf(pid) !== -1
}

function applePlayerKey(players, pids) {
  var list = asArray(players)
  for (var i = 0; i < list.length; i++) {
    if (isApplePlayer(list[i], pids)) return playerKey(list[i])
  }
  return ""
}

function findPlayer(players, key) {
  var list = asArray(players)
  for (var i = 0; i < list.length; i++) {
    if (playerKey(list[i]) === String(key || "")) return list[i]
  }
  return null
}

function choosePlayerKey(players, pids, manualKey, fallbackKey) {
  var manual = findPlayer(players, manualKey)
  if (manual && manual.isPlaying) return playerKey(manual)

  var appleKey = applePlayerKey(players, pids)
  var apple = findPlayer(players, appleKey)
  if (apple && apple.isPlaying) return appleKey

  var fallback = findPlayer(players, fallbackKey)
  if (fallback) return playerKey(fallback)
  if (apple) return appleKey
  return asArray(players).length > 0 ? playerKey(players[0]) : ""
}

function sourceName(player, appleKey) {
  if (!player) return "Media"
  if (playerKey(player) === String(appleKey || "")) return "Apple Music"
  return plainMetadata(player.identity || player.desktopEntry || "Media", 96)
}

function sourceDetail(player) {
  if (!player) return "Idle"
  var title = plainMetadata(player.trackTitle, 160)
  var artist = plainMetadata(player.trackArtist, 120)
  if (title && artist) return title + " — " + artist
  return title || artist || "Idle"
}

function capabilities(player) {
  return {
    shuffle: !!(player && player.shuffleSupported),
    loop: !!(player && player.loopSupported)
  }
}

function preferenceDefaults() {
  return {
    dynamicArtworkColor: true,
    barProgress: true,
    barDisplayMode: "full",
    motionEnabled: true,
    trackChangeOsd: false,
    rememberSessionHistory: true
  }
}

function normalizeBarDisplayMode(value) {
  var mode = String(value || "").toLowerCase()
  return mode === "compact" || mode === "title" || mode === "full" ? mode : "full"
}

function normalizePopupPage(value, opening) {
  if (opening) return "player"
  return String(value || "") === "more" ? "more" : "player"
}

function colorChannels(value) {
  var text = String(value || "").trim()
  var match = text.match(/^#([0-9a-f]{6}|[0-9a-f]{8})$/i)
  if (!match) return null
  var hex = match[1].length === 8 ? match[1].slice(2) : match[1]
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16)
  }
}

function channelLuminance(value) {
  var channel = Number(value || 0) / 255
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function relativeLuminance(value) {
  var rgb = colorChannels(value)
  if (!rgb) return -1
  return 0.2126 * channelLuminance(rgb.r) + 0.7152 * channelLuminance(rgb.g) + 0.0722 * channelLuminance(rgb.b)
}

function contrastRatio(a, b) {
  var left = relativeLuminance(a)
  var right = relativeLuminance(b)
  if (left < 0 || right < 0) return 0
  return (Math.max(left, right) + 0.05) / (Math.min(left, right) + 0.05)
}

function colorSaturation(value) {
  var rgb = colorChannels(value)
  if (!rgb) return 0
  var max = Math.max(rgb.r, rgb.g, rgb.b)
  var min = Math.min(rgb.r, rgb.g, rgb.b)
  return max === 0 ? 0 : (max - min) / max
}

function colorHex(value) {
  var rgb = colorChannels(value)
  if (!rgb) return ""
  function channel(value) {
    var text = Math.max(0, Math.min(255, Math.round(value))).toString(16)
    return text.length < 2 ? "0" + text : text
  }
  return "#" + channel(rgb.r) + channel(rgb.g) + channel(rgb.b)
}

function blendColors(primary, secondary, primaryWeight) {
  var left = colorChannels(primary)
  var right = colorChannels(secondary)
  if (!left || !right) return colorHex(primary) || colorHex(secondary)
  var weight = Math.max(0, Math.min(1, Number(primaryWeight)))
  if (!isFinite(weight)) weight = 0.8
  return colorHex("#" + [
    Math.round(left.r * weight + right.r * (1 - weight)),
    Math.round(left.g * weight + right.g * (1 - weight)),
    Math.round(left.b * weight + right.b * (1 - weight))
  ].map(function(channel) {
    var text = channel.toString(16)
    return text.length < 2 ? "0" + text : text
  }).join(""))
}

function bestArtworkAccent(colors, fallback, background) {
  var list = asArray(colors)
  var best = ""
  var bestScore = -1
  for (var i = 0; i < list.length; i++) {
    var candidate = String(list[i] || "")
    var contrast = contrastRatio(candidate, background)
    if (contrast < 3) continue
    var score = colorSaturation(candidate) * 2 + Math.min(contrast, 7) / 7
    if (score > bestScore) {
      best = candidate
      bestScore = score
    }
  }
  return best || String(fallback || "")
}

function artworkAccentUpdate(currentArtUrl, paletteArtUrl, colors, fallback, background) {
  var current = String(currentArtUrl || "")
  var fallbackColor = colorHex(fallback) || String(fallback || "#ffffff")
  if (!current) return { apply: true, color: fallbackColor }
  if (current !== String(paletteArtUrl || "") || asArray(colors).length === 0)
    return { apply: false, color: "" }
  var candidate = bestArtworkAccent(colors, "", background)
  if (!candidate) return { apply: true, color: fallbackColor }
  var blended = blendColors(candidate, fallbackColor, 0.8)
  if (!blended || contrastRatio(blended, background) < 3)
    return { apply: true, color: fallbackColor }
  return { apply: true, color: blended }
}

function responsiveClass(width) {
  var value = Number(width || 0)
  if (value < 360) return "narrow"
  if (value < 460) return "medium"
  return "wide"
}

function layoutMode(width) {
  return responsiveClass(width)
}

function responsiveGeometry(width) {
  var mode = responsiveClass(width)
  if (mode === "wide")
    return { mode: mode, targetWidth: 520, artworkSize: 176, stackedHero: false, preferenceColumns: 2, stackedActions: false }
  if (mode === "medium")
    return { mode: mode, targetWidth: 420, artworkSize: 142, stackedHero: false, preferenceColumns: 1, stackedActions: false }
  return { mode: mode, targetWidth: 340, artworkSize: 156, stackedHero: true, preferenceColumns: 1, stackedActions: true }
}

function motionDuration(enabled, duration) {
  return enabled ? Math.max(0, Number(duration || 0)) : 0
}

function sourcePopoverSelection(key) {
  return { selectedKey: String(key || ""), open: false }
}

function idlePresentation(hasPlayer) {
  return hasPlayer
    ? { title: "", prompt: "", icon: "󰐊", controlsVisible: true }
    : { title: "Apple Music", prompt: "Open to start listening", icon: "󰝚", controlsVisible: false }
}

function createSessionState() {
  return { manualPlayerKey: "", history: [], sleepMode: "", paletteArtUrl: "", popupConsumers: 0 }
}

function reduceSessionState(state, action) {
  var next = Object.assign({}, state || createSessionState())
  var event = action || {}
  if (event.type === "source") next.manualPlayerKey = String(event.key || "")
  else if (event.type === "history") next.history = asArray(event.history).slice()
  else if (event.type === "timer") next.sleepMode = String(event.mode || "")
  else if (event.type === "palette") next.paletteArtUrl = String(event.artUrl || "")
  else if (event.type === "popup") next.popupConsumers = Math.max(0, Number(next.popupConsumers || 0) + (event.open ? 1 : -1))
  return next
}

function copyText(value) {
  var title = plainMetadata(value && (value.title || value.trackTitle), 160)
  var artist = plainMetadata(value && (value.artist || value.trackArtist), 120)
  var album = plainMetadata(value && (value.album || value.trackAlbum), 160)
  var first = title && artist ? title + " — " + artist : title || artist
  if (!first) return album
  return first + (album ? "\n" + album : "")
}

function historyEntry(player, timestamp) {
  if (!player || !(player.trackTitle || player.trackArtist)) return null
  return {
    signature: trackSignature(player),
    title: plainMetadata(player.trackTitle, 160),
    artist: plainMetadata(player.trackArtist, 120),
    album: plainMetadata(player.trackAlbum, 160),
    source: plainMetadata(player.identity || player.desktopEntry || "Media", 96),
    timestamp: Number(timestamp || Date.now())
  }
}

function addHistory(history, player, limit, timestamp) {
  var nextEntry = historyEntry(player, timestamp)
  var list = asArray(history).slice()
  if (!nextEntry) return list
  if (list.length > 0 && list[0].signature === nextEntry.signature) return list
  list = list.filter(function(entry) { return entry && entry.signature !== nextEntry.signature })
  list.unshift(nextEntry)
  return list.slice(0, Math.max(1, Number(limit) || 10))
}

function relativeTime(timestamp, nowMs) {
  var elapsed = Math.max(0, Number(nowMs || Date.now()) - Number(timestamp || 0))
  var minutes = Math.floor(elapsed / 60000)
  if (minutes < 1) return "now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

function clampSleepMinutes(value) {
  var minutes = Math.round(Number(value || 0) / 5) * 5
  return Math.max(5, Math.min(180, minutes || 5))
}

function fadeProgress(startMs, endMs, nowMs) {
  var start = Number(startMs || 0)
  var end = Number(endMs || 0)
  if (end <= start) return Number(nowMs || 0) >= end ? 1 : 0
  return Math.max(0, Math.min(1, (Number(nowMs || 0) - start) / (end - start)))
}

function fadeVolume(originalVolume, progress) {
  return Math.max(0, Math.min(1, Number(originalVolume || 0) * (1 - Math.max(0, Math.min(1, Number(progress || 0))))))
}

function timerPhase(mode, deadlineMs, player, originalSignature, nowMs, fadeSeconds) {
  if (!mode || !player) return { phase: "idle", progress: 0 }
  var fadeMs = Math.max(0, Number(fadeSeconds || 5)) * 1000
  if (mode === "deadline") {
    var deadline = Number(deadlineMs || 0)
    if (Number(nowMs || 0) >= deadline) return { phase: "finish", progress: 1 }
    var start = deadline - fadeMs
    if (Number(nowMs || 0) >= start) return { phase: "fade", progress: fadeProgress(start, deadline, nowMs) }
    return { phase: "wait", progress: 0 }
  }

  if (mode === "track") {
    if (trackSignature(player) !== String(originalSignature || "")) return { phase: "finish", progress: 1 }
    var duration = Number(player.length || 0)
    var position = Number(player.position || 0)
    if (duration <= 0) return { phase: "wait", progress: 0 }
    var remaining = duration - position
    if (remaining <= 0.25) return { phase: "finish", progress: 1 }
    if (remaining <= fadeMs / 1000) return { phase: "fade", progress: Math.max(0, Math.min(1, 1 - remaining / (fadeMs / 1000))) }
  }
  return { phase: "wait", progress: 0 }
}

function trackSignature(player) {
  if (!player) return ""
  return [
    plainMetadata(player.trackTitle, 160),
    plainMetadata(player.trackArtist, 120),
    plainMetadata(player.trackAlbum, 160)
  ].join("\u001f")
}

function artworkSignature(player) {
  return String(player && player.trackArtUrl || "")
}

function formatTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var remainder = total % 60
  if (hours > 0) return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (remainder < 10 ? "0" : "") + remainder
  return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}

function timerDeadline(minutes, nowMs) {
  return Number(nowMs || Date.now()) + Math.max(0, Number(minutes) || 0) * 60000
}

function timerRemaining(deadlineMs, nowMs) {
  var remaining = Math.max(0, Math.ceil((Number(deadlineMs) - Number(nowMs || Date.now())) / 1000))
  return formatTime(remaining)
}

function endOfTrackReached(player, originalSignature, thresholdSeconds) {
  if (!player) return true
  if (trackSignature(player) !== String(originalSignature || "")) return true
  var duration = Number(player.length || 0)
  var position = Number(player.position || 0)
  if (duration <= 0) return false
  return position >= Math.max(0, duration - Math.max(0.5, Number(thresholdSeconds) || 1.5))
}

if (typeof module !== "undefined") {
  module.exports = {
    plainMetadata: plainMetadata,
    safeArtworkCandidate: safeArtworkCandidate,
    playerKey: playerKey,
    dbusInstancePid: dbusInstancePid,
    appleMusicPids: appleMusicPids,
    isApplePlayer: isApplePlayer,
    applePlayerKey: applePlayerKey,
    findPlayer: findPlayer,
    choosePlayerKey: choosePlayerKey,
    sourceName: sourceName,
    sourceDetail: sourceDetail,
    capabilities: capabilities,
    preferenceDefaults: preferenceDefaults,
    normalizeBarDisplayMode: normalizeBarDisplayMode,
    normalizePopupPage: normalizePopupPage,
    colorChannels: colorChannels,
    relativeLuminance: relativeLuminance,
    contrastRatio: contrastRatio,
    colorSaturation: colorSaturation,
    colorHex: colorHex,
    blendColors: blendColors,
    bestArtworkAccent: bestArtworkAccent,
    artworkAccentUpdate: artworkAccentUpdate,
    responsiveClass: responsiveClass,
    layoutMode: layoutMode,
    responsiveGeometry: responsiveGeometry,
    motionDuration: motionDuration,
    sourcePopoverSelection: sourcePopoverSelection,
    idlePresentation: idlePresentation,
    createSessionState: createSessionState,
    reduceSessionState: reduceSessionState,
    copyText: copyText,
    historyEntry: historyEntry,
    addHistory: addHistory,
    relativeTime: relativeTime,
    clampSleepMinutes: clampSleepMinutes,
    fadeProgress: fadeProgress,
    fadeVolume: fadeVolume,
    timerPhase: timerPhase,
    trackSignature: trackSignature,
    artworkSignature: artworkSignature,
    formatTime: formatTime,
    timerDeadline: timerDeadline,
    timerRemaining: timerRemaining,
    endOfTrackReached: endOfTrackReached
  }
}
