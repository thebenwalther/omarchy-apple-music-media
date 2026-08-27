import QtQuick
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

Column {
  id: root

  property var bar: null
  property var session: null
  property string responsiveClass: "wide"
  property bool active: false
  property bool dynamicArtworkColor: true
  property bool barProgressEnabled: true
  property string barDisplayMode: "full"
  property bool motionEnabled: true
  property bool trackChangeOsd: false
  property bool rememberSessionHistory: true
  property int customSleepMinutes: 45
  property double historyNowMs: Date.now()

  readonly property bool wide: responsiveClass === "wide"
  readonly property color popupText: Color.popups.text
  readonly property color mutedText: Util.alpha(Color.popups.text, 0.68)
  readonly property real preferenceCardWidth: wide
    ? Math.max(1, (width - Style.spacing.rowGap) / 2) : width

  signal backRequested()
  signal preferenceRequested(string key, var value)

  function focusFirst() { backButton.forceActiveFocus() }

  spacing: Style.spacing.panelGap

  Timer {
    interval: 60000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.historyNowMs = Date.now()
  }

  Row {
    width: parent.width
    spacing: Style.spacing.rowGap
    MediaButton { id: backButton; text: "Back"; iconText: "󰁍"; foreground: root.popupText; accent: Color.accent; focusable: true; accessibleName: "Back to player"; onClicked: root.backRequested() }
    Column {
      width: parent.width - backButton.implicitWidth - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      Text { width: parent.width; text: "PLAYER OPTIONS"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
      Text { width: parent.width; text: "Playback tools and appearance"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
    }
  }

  MediaButton {
    width: parent.width
    text: "Audio Output"
    iconText: "󰕾"
    foreground: root.popupText
    accent: Color.accent
    bordered: true
    focusable: true
    leftAlign: true
    tooltipText: "Open Omarchy's native output picker"
    onClicked: root.session.openAudioPanel()
  }

  PanelSeparator { width: parent.width; foreground: root.popupText }
  Text { text: "SLEEP TIMER"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }

  Flow {
    width: parent.width
    spacing: Style.spacing.rowGap
    visible: root.session.hasPlayer
    MediaButton { text: "15m"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.session.sleepMode === "deadline" && root.session.sleepPresetMinutes === 15; bordered: selected; onClicked: root.session.startSleepMinutes(15) }
    MediaButton { text: "30m"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.session.sleepMode === "deadline" && root.session.sleepPresetMinutes === 30; bordered: selected; onClicked: root.session.startSleepMinutes(30) }
    MediaButton { text: "60m"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.session.sleepMode === "deadline" && root.session.sleepPresetMinutes === 60; bordered: selected; onClicked: root.session.startSleepMinutes(60) }
    MediaButton { text: "End of track"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.session.sleepMode === "track"; bordered: selected; onClicked: root.session.startSleepAtTrackEnd() }
    MediaButton { text: "Off"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.session.sleepMode !== ""; opacity: enabled ? 1 : 0.35; onClicked: root.session.cancelSleepTimer() }
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.rowGap
    visible: root.session.hasPlayer
    Text { text: "Custom"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; height: minusSleep.height; verticalAlignment: Text.AlignVCenter }
    MediaButton { id: minusSleep; iconText: "󰅖"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.customSleepMinutes > 5; tooltipText: "Subtract five minutes"; accessibleName: tooltipText; onClicked: root.customSleepMinutes = MediaController.clampSleepMinutes(root.customSleepMinutes - 5) }
    Text { text: root.customSleepMinutes + "m"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; height: minusSleep.height; verticalAlignment: Text.AlignVCenter }
    MediaButton { iconText: "󰐕"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.customSleepMinutes < 180; tooltipText: "Add five minutes"; accessibleName: tooltipText; onClicked: root.customSleepMinutes = MediaController.clampSleepMinutes(root.customSleepMinutes + 5) }
    MediaButton { text: "Start custom timer"; foreground: root.popupText; accent: Color.accent; bordered: true; focusable: true; onClicked: root.session.startSleepMinutes(root.customSleepMinutes) }
  }

  BorderSurface {
    width: parent.width
    implicitHeight: timerStatus.implicitHeight + Style.spacing.rowPaddingX * 2
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.popupText, Color.accent)
    borderSpec: Border.controlSpec(root.session.sleepMode !== "" ? "selected" : "normal", root.popupText, Color.accent)
    Text {
      id: timerStatus
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      text: root.session.sleepMode === "" ? "No timer · audio fades for five seconds before pausing" : root.session.sleepLabel
      color: root.session.sleepMode === "" ? root.mutedText : root.popupText
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }

  PanelSeparator { width: parent.width; foreground: root.popupText }
  Text { text: "APPEARANCE & FEEDBACK"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }

  MediaDropdown {
    width: parent.width
    label: "Bar display"
    value: MediaController.normalizeBarDisplayMode(root.barDisplayMode)
    options: [
      { value: "full", label: "Full · artwork, title, artist" },
      { value: "title", label: "Title · artwork and title" },
      { value: "compact", label: "Compact · artwork and state" }
    ]
    foreground: root.popupText
    accent: Color.accent
    onChanged: function(value) { root.preferenceRequested("barDisplayMode", value) }
  }

  Grid {
    width: parent.width
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.rowGap
    rowSpacing: Style.spacing.rowGap
    MediaToggle { width: root.preferenceCardWidth; label: "Artwork colors"; description: "Tint graphical accents from the album cover."; checked: root.dynamicArtworkColor; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("dynamicArtworkColor", !root.dynamicArtworkColor) }
    MediaToggle { width: root.preferenceCardWidth; label: "Bar progress"; description: "Show the playback rail under the bar pill."; checked: root.barProgressEnabled; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("barProgress", !root.barProgressEnabled) }
    MediaToggle { width: root.preferenceCardWidth; label: "Motion"; description: "Animate artwork, pages, height, and progress."; checked: root.motionEnabled; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("motionEnabled", !root.motionEnabled) }
    MediaToggle { width: root.preferenceCardWidth; label: "Track-change OSD"; description: "Show title and artist when tracks change."; checked: root.trackChangeOsd; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("trackChangeOsd", !root.trackChangeOsd) }
    MediaToggle { width: root.preferenceCardWidth; label: "Session history"; description: "Remember ten tracks until shell restart."; checked: root.rememberSessionHistory; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("rememberSessionHistory", !root.rememberSessionHistory) }
  }

  PanelSeparator { width: parent.width; foreground: root.popupText }
  Row {
    width: parent.width
    Text { width: parent.width - clearHistoryButton.implicitWidth - parent.spacing; text: "RECENT THIS SESSION"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
    MediaButton { id: clearHistoryButton; text: "Clear"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.session.recentHistory.length > 0; opacity: enabled ? 1 : 0.35; onClicked: root.session.clearHistory() }
  }
  Text { visible: root.session.recentHistory.length === 0; text: root.rememberSessionHistory ? "Tracks you play will appear here." : "Session history is turned off."; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
  Repeater {
    model: root.session.recentHistory.slice(0, 5)
    MediaButton {
      required property var modelData
      width: root.width
      text: MediaController.copyText(modelData).replace("\n", " · ") + "  ·  " + MediaController.relativeTime(modelData.timestamp, root.historyNowMs)
      iconText: "󰆏"
      foreground: root.mutedText
      accent: Color.accent
      leftAlign: true
      focusable: true
      enabled: root.session.copyAvailable
      tooltipText: "Copy track details"
      onClicked: root.session.copyMetadata(modelData)
    }
  }
}
