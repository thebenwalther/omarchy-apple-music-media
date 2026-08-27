import QtQuick
import qs.Ui
import qs.Commons
import "." as Local
import "MediaController.js" as MediaController

BarWidget {
  id: root
  moduleName: "io.github.thebenwalther.apple-music"

  readonly property var session: Local.MediaSession
  readonly property var resolvedMediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  property bool popupOpen: false
  readonly property bool opened: popupOpen

  readonly property bool dynamicArtworkColor: setting("dynamicArtworkColor", true) === true
  readonly property bool barProgressEnabled: setting("barProgress", true) === true
  readonly property string barDisplayMode: MediaController.normalizeBarDisplayMode(setting("barDisplayMode", "full"))
  readonly property string effectiveBarDisplayMode: bar && bar.vertical ? "compact" : barDisplayMode
  readonly property bool motionEnabled: setting("motionEnabled", true) === true
  readonly property bool trackChangeOsd: setting("trackChangeOsd", false) === true
  readonly property bool rememberSessionHistory: setting("rememberSessionHistory", true) === true
  readonly property real stableWidth: effectiveBarDisplayMode === "compact"
    ? Style.space(52) : (effectiveBarDisplayMode === "title" ? Style.space(252) : Style.space(294))

  function preferences() {
    return {
      dynamicArtworkColor: dynamicArtworkColor,
      trackChangeOsd: trackChangeOsd,
      rememberSessionHistory: rememberSessionHistory
    }
  }

  function open() {
    if (popupOpen) return
    popupOpen = true
    session.popupOpened()
    details.resetForOpen()
  }

  function close() {
    if (!popupOpen) return
    popupOpen = false
    session.popupClosed()
  }

  function updatePreference(key, value) {
    var entry = { id: moduleName }
    for (var name in settings) if (name !== "id") entry[name] = settings[name]
    entry[key] = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  visible: true
  implicitWidth: bar && bar.vertical ? barSize : stableWidth
  implicitHeight: barSize

  Component.onCompleted: session.attach(bar, preferences(), resolvedMediaService)
  Component.onDestruction: if (popupOpen) session.popupClosed()
  onResolvedMediaServiceChanged: session.setMediaService(resolvedMediaService)
  onDynamicArtworkColorChanged: session.configure(preferences())
  onTrackChangeOsdChanged: session.configure(preferences())
  onRememberSessionHistoryChanged: session.configure(preferences())
  Connections {
    target: session
    function onOpenRequested() { root.open() }
    function onCloseRequested() { root.close() }
  }

  BorderSurface {
    id: pill
    anchors.centerIn: parent
    width: root.bar && root.bar.vertical ? Math.min(root.barSize - Style.spacing.sm, Style.space(34)) : root.stableWidth
    height: Math.min(root.barSize - Style.spacing.sm, Style.space(32))
    radius: height / 2
    color: root.popupOpen ? Style.selectedFillFor(root.bar.foreground, Color.accent)
      : pillMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent)
      : "transparent"
    borderSpec: root.popupOpen ? Border.controlSpec("selected", root.bar.foreground, Color.accent) : Border.none()
    clip: true

    Behavior on color { enabled: root.motionEnabled; ColorAnimation { duration: 160 } }

    Row {
      id: pillRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      spacing: Style.spacing.controlGap

      BorderSurface {
        width: Math.min(pill.height - Style.spacing.sm, Style.space(25))
        height: width
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.bar.foreground, Color.accent)
        borderSpec: Border.flat(Util.alpha(session.artworkAccent, 0.65), Math.max(1, Style.spacing.hairline))
        clip: true

        Image {
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 64
          sourceSize.height: 64
          source: session.artUrl
          visible: source !== ""
        }
        Text {
          anchors.centerIn: parent
          visible: session.artUrl === ""
          text: "󰝚"
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        id: metadataRow
        visible: !root.bar.vertical && root.effectiveBarDisplayMode !== "compact"
        width: Math.max(0, pillRow.width - pillRow.children[0].width - stateIcon.width - pillRow.spacing * 2)
        spacing: root.effectiveBarDisplayMode === "full" ? Style.spacing.controlGap : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: titleLabel
          width: root.effectiveBarDisplayMode === "full"
            ? Math.min(implicitWidth, Math.max(0, (parent.width - parent.spacing) * 0.62)) : parent.width
          text: session.title
          textFormat: Text.PlainText
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: Math.max(0, parent.width - titleLabel.width - parent.spacing)
          visible: root.effectiveBarDisplayMode === "full"
          text: session.artist
          textFormat: Text.PlainText
          color: Util.alpha(root.bar.barForeground, 0.68)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: stateIcon
        text: session.hasPlayer ? (session.playing ? "󰏤" : "󰐊") : "󰐕"
        color: session.playing ? root.bar.barForeground : Util.alpha(root.bar.barForeground, 0.68)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      height: Math.max(1, Style.spacing.hairline * 2)
      width: root.barProgressEnabled && session.duration > 0
        ? parent.width * Math.max(0, Math.min(1, session.position / session.duration)) : 0
      radius: height / 2
      color: session.artworkAccent
      visible: root.barProgressEnabled && session.hasMedia && session.duration > 0
      opacity: session.playing ? 0.95 : 0.55
      Behavior on width {
        enabled: root.motionEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.popupOpen ? root.close() : root.open()
      onWheel: function(wheel) {
        if (session.currentPlayer && session.currentPlayer.volumeSupported)
          session.setVolume(session.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        else if (wheel.angleDelta.y > 0) session.runAction("previous")
        else session.runAction("next")
      }
      onEntered: if (root.bar) root.bar.showTooltip(root,
        (session.hasMedia ? session.title + (session.artist ? " — " + session.artist : "") : "Apple Music · open player")
        + (session.duration > 0 ? "\n" + MediaController.formatTime(session.position) + " / " + MediaController.formatTime(session.duration) : "")
        + "\nClick: details · Scroll: " + (session.currentPlayer && session.currentPlayer.volumeSupported ? "volume" : "previous/next"))
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }

  PlayerPopup {
    id: details
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    session: root.session
    barProgressEnabled: root.barProgressEnabled
    barDisplayMode: root.barDisplayMode
    motionEnabled: root.motionEnabled
    onPreferenceRequested: function(key, value) { root.updatePreference(key, value) }
    onCloseRequested: root.close()
  }
}
