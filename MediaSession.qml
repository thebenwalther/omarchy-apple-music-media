pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

Item {
  id: session
  visible: false
  width: 0
  height: 0

  property var shell: null
  property var commandRunner: null
  property var mediaService: null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var currentPlayer: mediaService ? mediaService.activePlayer : null
  readonly property string currentKey: mediaService && currentPlayer ? mediaService.playerKey(currentPlayer) : ""
  readonly property string applePlayerKey: MediaController.applePlayerKey(sourcePlayers, applePids)
  readonly property bool paletteSourceSupported: artUrl !== ""

  property var applePids: []
  property string manualPlayerKey: ""
  property real lastAudibleVolume: 0.7
  property int popupConsumers: 0

  property bool dynamicArtworkColor: true
  property bool trackChangeOsd: false
  property bool rememberSessionHistory: true
  property color artworkAccent: Color.accent
  property string paletteArtUrl: ""
  property var recentHistory: []
  property string observedTrackSignature: ""
  property bool copyAvailable: false
  property string artUrl: ""
  property string pendingArtUrl: ""
  property string pendingArtPath: ""
  property string probingArtUrl: ""
  property string probingArtPath: ""
  readonly property string securityHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("SecurityHelper.py")).replace(/^file:\/\//, ""))

  property string sleepMode: ""
  property int sleepPresetMinutes: 0
  property double sleepDeadlineMs: 0
  property string sleepPlayerKey: ""
  property string sleepTrackSignature: ""
  property double sleepNowMs: Date.now()
  property bool sleepFadeActive: false
  property real sleepFadeOriginalVolume: 1

  readonly property bool hasPlayer: currentPlayer !== null
  readonly property bool hasMedia: currentPlayer !== null && !!(currentPlayer.trackTitle || currentPlayer.trackArtist)
  readonly property string title: hasMedia ? MediaController.plainMetadata(currentPlayer.trackTitle, 160) : "Apple Music"
  readonly property string artist: hasMedia ? MediaController.plainMetadata(currentPlayer.trackArtist, 120) : "Open to start listening"
  readonly property string album: hasMedia ? MediaController.plainMetadata(currentPlayer.trackAlbum, 160) : ""
  readonly property string requestedArtUrl: hasMedia ? String(currentPlayer.trackArtUrl || "") : ""
  readonly property bool playing: currentPlayer !== null ? currentPlayer.isPlaying : false
  readonly property real position: currentPlayer !== null && currentPlayer.positionSupported ? Number(currentPlayer.position || 0) : 0
  readonly property real duration: currentPlayer !== null && currentPlayer.lengthSupported ? Number(currentPlayer.length || 0) : 0
  readonly property real volume: currentPlayer !== null && currentPlayer.volumeSupported ? Number(currentPlayer.volume ?? 1) : 1
  readonly property string sourceName: MediaController.sourceName(currentPlayer, applePlayerKey)
  readonly property color themeAccent: Color.accent
  readonly property color themePopupBackground: Color.popups.background
  readonly property string sleepLabel: sleepMode === "deadline"
    ? (sleepFadeActive ? "Fading out" : "Sleep in " + MediaController.timerRemaining(sleepDeadlineMs, sleepNowMs))
    : (sleepMode === "track" ? (sleepFadeActive ? "Fading at track end" : "Sleep at end of track") : "")

  signal openRequested()
  signal closeRequested()

  function attach(widgetBar, preferences, resolvedService) {
    if (widgetBar) {
      commandRunner = widgetBar
      if (widgetBar.shell) {
        shell = widgetBar.shell
      }
    }
    setMediaService(resolvedService || (shell ? shell.firstPartyServiceFor("omarchy.media") : null))
    configure(preferences)
    requestAppleProbe()
    requestArtworkProbe()
    if (!copyProbe.running && !copyAvailable) copyProbe.running = true
    historyCapture.restart()
  }

  function setMediaService(service) {
    if (mediaService === service) return
    mediaService = service || null
    Qt.callLater(session.applySourcePreference)
    historyCapture.restart()
  }

  function configure(preferences) {
    var value = preferences || {}
    dynamicArtworkColor = value.dynamicArtworkColor !== false
    trackChangeOsd = value.trackChangeOsd === true
    rememberSessionHistory = value.rememberSessionHistory !== false
    if (!rememberSessionHistory) recentHistory = []
    refreshArtworkAccent()
  }

  function popupOpened() { popupConsumers += 1; requestAppleProbe() }
  function popupClosed() { popupConsumers = Math.max(0, popupConsumers - 1) }

  function playerForKey(key) {
    return mediaService && key ? mediaService.playerForKey(key) : null
  }

  function requestAppleProbe() {
    if (!windowProbe.running) windowProbe.running = true
  }

  function applySourcePreference() {
    if (!mediaService) return
    var fallbackKey = currentPlayer ? mediaService.playerKey(currentPlayer) : ""
    var desired = MediaController.choosePlayerKey(sourcePlayers, applePids, manualPlayerKey, fallbackKey)
    var manual = playerForKey(manualPlayerKey)
    if (!manual || !manual.isPlaying) manualPlayerKey = ""
    if (desired && desired !== fallbackKey) mediaService.selectPlayer(desired)
  }

  function selectSource(key) {
    if (!mediaService || !key) return
    manualPlayerKey = key
    mediaService.selectPlayer(key)
  }

  function showOsd(icon, message, duration) {
    if (!shell || typeof shell.summon !== "function") return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: icon || "media",
      message: message || "",
      duration: duration || 1800
    }))
  }

  function captureCurrentTrack() {
    if (!currentPlayer || !hasMedia) return
    var signature = MediaController.trackSignature(currentPlayer)
    if (!signature || signature === observedTrackSignature) return
    var hadPrevious = observedTrackSignature !== ""
    observedTrackSignature = signature
    if (rememberSessionHistory)
      recentHistory = MediaController.addHistory(recentHistory, currentPlayer, 10, Date.now())
    if (hadPrevious && trackChangeOsd)
      showOsd("media", MediaController.copyText(currentPlayer).split("\n")[0], 1800)
  }

  function clearHistory() { recentHistory = [] }

  function copyMetadata(value) {
    if (!copyAvailable || copyProcess.running) return
    var text = MediaController.copyText(value)
    if (!text) return
    copyProcess.command = ["wl-copy", text]
    copyProcess.running = true
    showOsd("󰆏", "Copied now playing", 1200)
  }

  function runAction(action, targetKey) {
    if (mediaService) mediaService.runAction(action, false, targetKey || currentKey)
  }

  function seekBy(delta) {
    if (!currentPlayer || !currentPlayer.canSeek || !currentPlayer.positionSupported) return
    var maximum = duration > 0 ? duration : Number.MAX_VALUE
    currentPlayer.position = Math.max(0, Math.min(maximum, position + Number(delta || 0)))
  }

  function seekTo(value) {
    if (!currentPlayer || !currentPlayer.canSeek || !currentPlayer.positionSupported) return
    currentPlayer.position = Math.max(0, Math.min(duration, Number(value || 0)))
  }

  function setVolume(value) {
    if (!currentPlayer || !currentPlayer.volumeSupported) return
    if (sleepFadeActive) cancelSleepTimer()
    var level = Math.max(0, Math.min(1, Number(value || 0)))
    currentPlayer.volume = level
    if (level > 0.01) lastAudibleVolume = level
  }

  function toggleMute() {
    if (!currentPlayer || !currentPlayer.volumeSupported) return
    if (volume > 0.01) {
      lastAudibleVolume = volume
      setVolume(0)
    } else setVolume(Math.max(0.05, lastAudibleVolume))
  }

  function cycleLoop() {
    if (!currentPlayer || !currentPlayer.loopSupported) return
    if (currentPlayer.loopState === MprisLoopState.None) currentPlayer.loopState = MprisLoopState.Playlist
    else if (currentPlayer.loopState === MprisLoopState.Playlist) currentPlayer.loopState = MprisLoopState.Track
    else currentPlayer.loopState = MprisLoopState.None
  }

  function startSleepMinutes(minutes) {
    if (!currentPlayer) return
    cancelSleepTimer()
    sleepMode = "deadline"
    sleepPresetMinutes = MediaController.clampSleepMinutes(minutes)
    sleepNowMs = Date.now()
    sleepDeadlineMs = MediaController.timerDeadline(sleepPresetMinutes, sleepNowMs)
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function startSleepAtTrackEnd() {
    if (!currentPlayer) return
    cancelSleepTimer()
    sleepMode = "track"
    sleepPresetMinutes = -1
    sleepNowMs = Date.now()
    sleepDeadlineMs = 0
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function clearSleepTimer(restoreVolume) {
    var target = playerForKey(sleepPlayerKey)
    if (restoreVolume && sleepFadeActive && target && target.volumeSupported)
      target.volume = sleepFadeOriginalVolume
    sleepMode = ""
    sleepPresetMinutes = 0
    sleepDeadlineMs = 0
    sleepPlayerKey = ""
    sleepTrackSignature = ""
    sleepFadeActive = false
    sleepFadeOriginalVolume = 1
  }

  function cancelSleepTimer() { clearSleepTimer(true) }

  function checkSleepTimer() {
    if (!sleepMode) return
    sleepNowMs = Date.now()
    var target = playerForKey(sleepPlayerKey)
    if (!target) { cancelSleepTimer(); return }
    var state = MediaController.timerPhase(sleepMode, sleepDeadlineMs, target, sleepTrackSignature, sleepNowMs, 5)
    if (state.phase === "wait" || state.phase === "idle") return
    if (state.phase === "fade") {
      if (!target.volumeSupported) return
      if (!sleepFadeActive) {
        sleepFadeActive = true
        sleepFadeOriginalVolume = Math.max(0, Math.min(1, Number(target.volume || 0)))
      }
      target.volume = MediaController.fadeVolume(sleepFadeOriginalVolume, state.progress)
      return
    }
    if (state.phase !== "finish") return
    if (target.isPlaying) runAction("pause", sleepPlayerKey)
    if (sleepFadeActive && target.volumeSupported) target.volume = sleepFadeOriginalVolume
    showOsd("media-pause", "Sleep timer finished", 1800)
    clearSleepTimer(false)
  }

  function openAppleMusic() {
    if (commandRunner)
      commandRunner.run("omarchy launch or focus webapp \"music[.]apple[.]com__-Default\" \"https://music.apple.com/\"")
  }

  function openAudioPanel() {
    if (!shell || typeof shell.summon !== "function" || !shell.summon("omarchy.audio", "{}"))
      showOsd("audio-volume-high", "Audio panel unavailable", 1600)
  }

  function refreshArtworkAccent() {
    if (!dynamicArtworkColor) { artworkAccent = themeAccent; return }
    var update = MediaController.artworkAccentUpdate(artUrl, paletteArtUrl, artPalette.colors, themeAccent, themePopupBackground)
    if (update.apply) artworkAccent = update.color
  }

  function requestArtworkProbe() {
    var candidate = MediaController.safeArtworkCandidate(requestedArtUrl)
    pendingArtUrl = candidate.url
    pendingArtPath = candidate.path
    artUrl = ""
    if (pendingArtPath !== "" && !artworkProbe.running) startArtworkProbe()
  }

  function startArtworkProbe() {
    if (pendingArtPath === "" || artworkProbe.running) return
    probingArtUrl = pendingArtUrl
    probingArtPath = pendingArtPath
    artworkProbe.command = ["/usr/bin/python3", securityHelperPath, "artwork", probingArtPath]
    artworkProbe.running = true
  }

  onSourcePlayersChanged: { requestAppleProbe(); Qt.callLater(applySourcePreference) }
  onApplePidsChanged: Qt.callLater(applySourcePreference)
  onCurrentPlayerChanged: historyCapture.restart()
  onRequestedArtUrlChanged: requestArtworkProbe()
  onArtUrlChanged: {
    paletteArtUrl = ""
    if (!paletteSourceSupported || !dynamicArtworkColor) artworkAccent = themeAccent
  }
  onDynamicArtworkColorChanged: refreshArtworkAccent()
  onThemeAccentChanged: refreshArtworkAccent()
  onThemePopupBackgroundChanged: refreshArtworkAccent()
  onRememberSessionHistoryChanged: if (!rememberSessionHistory) recentHistory = []

  ColorQuantizer {
    id: artPalette
    source: session.dynamicArtworkColor && String(session.artUrl || "").indexOf("data:") !== 0 ? session.artUrl : ""
    depth: 4
    rescaleSize: 64
    onColorsChanged: {
      session.paletteArtUrl = session.artUrl
      session.refreshArtworkAccent()
    }
  }

  Connections {
    target: session.currentPlayer
    function onTrackChanged() { historyCapture.restart() }
    function onPostTrackChanged() { historyCapture.restart() }
    function onMetadataChanged() { historyCapture.restart() }
  }

  Timer { id: historyCapture; interval: 350; repeat: false; onTriggered: session.captureCurrentTrack() }

  Process {
    id: artworkProbe
    stdout: StdioCollector { id: artworkProbeOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var privateUrl = String(artworkProbeOutput.text || "").trim()
      if (exitCode === 0 && session.probingArtUrl === session.pendingArtUrl
          && /^file:\/\/\/.+\/omarchy-apple-music-media-[0-9]+\/art-[A-Za-z0-9_-]+\.img$/.test(privateUrl))
        session.artUrl = privateUrl
      if (session.probingArtUrl !== session.pendingArtUrl && session.pendingArtPath !== "")
        Qt.callLater(session.startArtworkProbe)
    }
  }

  Process {
    id: windowProbe
    command: ["/usr/bin/python3", session.securityHelperPath, "clients"]
    stdout: StdioCollector { id: windowProbeOutput; waitForEnd: true }
    onExited: function(exitCode) {
      session.applePids = exitCode === 0 ? MediaController.appleMusicPids(windowProbeOutput.text || "[]") : []
      Qt.callLater(session.applySourcePreference)
    }
  }

  Process {
    id: copyProbe
    command: ["which", "wl-copy"]
    onExited: function(exitCode) { session.copyAvailable = exitCode === 0 }
  }
  Process { id: copyProcess }

  Timer {
    interval: 1000
    repeat: true
    running: session.popupConsumers > 0 || session.sleepMode !== "" || session.playing
    onTriggered: {
      var timerPlayer = session.playerForKey(session.sleepPlayerKey) || session.currentPlayer
      if (timerPlayer && timerPlayer.positionSupported) timerPlayer.positionChanged()
      session.checkSleepTimer()
    }
  }
  Timer { interval: 250; repeat: true; running: session.sleepFadeActive; onTriggered: session.checkSleepTimer() }

  IpcHandler {
    target: "thebenwalther-apple-music"
    function open(): string { session.openRequested(); return "ok" }
    function close(): string { session.closeRequested(); return "ok" }
  }
}
