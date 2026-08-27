import QtQuick
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

Column {
  id: root

  property var bar: null
  property var session: null
  property string responsiveClass: "wide"
  property bool motionEnabled: true
  property bool active: true

  readonly property bool narrow: responsiveClass === "narrow"
  readonly property bool stackedActions: narrow
  readonly property color popupText: Color.popups.text
  readonly property color mutedText: Util.alpha(Color.popups.text, 0.68)
  readonly property var player: session ? session.currentPlayer : null
  readonly property bool hasPlayer: session ? session.hasPlayer : false
  readonly property bool hasMedia: session ? session.hasMedia : false
  readonly property bool canSeek: player !== null ? player.canSeek && player.positionSupported : false
  readonly property bool canToggle: player !== null ? player.canTogglePlaying || player.canPlay || player.canPause : false
  readonly property var modeCapabilities: MediaController.capabilities(player)

  signal moreRequested()

  function focusFirst() { openButton.forceActiveFocus() }

  spacing: Style.spacing.panelGap

  ArtworkHero {
    width: parent.width
    bar: root.bar
    session: root.session
    responsiveClass: root.responsiveClass
    motionEnabled: root.motionEnabled
  }

  Column {
    width: parent.width
    spacing: Style.spacing.xs
    visible: root.hasPlayer && root.session.duration > 0
    MediaTimeline {
      width: parent.width
      bar: root.bar
      value: root.session.position
      maximum: root.session.duration
      seekable: root.canSeek
      motionEnabled: root.motionEnabled
      accent: root.session.artworkAccent
      foreground: root.popupText
      onMoved: function(value) { root.session.seekTo(value) }
      onReleased: function(value) { root.session.seekTo(value) }
    }
    Item {
      width: parent.width
      height: elapsed.implicitHeight
      Text { id: elapsed; anchors.left: parent.left; text: MediaController.formatTime(root.session.position); color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Text { anchors.right: parent.right; text: "−" + MediaController.formatTime(Math.max(0, root.session.duration - root.session.position)); color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.spacing.rowGap
    visible: root.hasPlayer
    MediaButton { iconText: "󰒮"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.player && root.player.canGoPrevious; opacity: enabled ? 1 : 0.35; tooltipText: "Previous"; accessibleName: "Previous"; onClicked: root.session.runAction("previous") }
    MediaButton { text: "−10"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.canSeek; opacity: enabled ? 1 : 0.35; tooltipText: "Back 10 seconds"; accessibleName: "Back 10 seconds"; onClicked: root.session.seekBy(-10) }
    MediaButton { iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"; foreground: root.popupText; accent: Color.accent; background: Util.alpha(root.session.artworkAccent, 0.2); bordered: true; focusable: true; horizontalPadding: Style.spacing.panelPadding; verticalPadding: Style.spacing.controlPaddingY + Style.spacing.sm; iconSize: Style.font.iconLarge; enabled: root.canToggle; opacity: enabled ? 1 : 0.35; tooltipText: root.player && root.player.isPlaying ? "Pause" : "Play"; accessibleName: tooltipText; onClicked: root.session.runAction("playPause") }
    MediaButton { text: "+10"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.canSeek; opacity: enabled ? 1 : 0.35; tooltipText: "Forward 10 seconds"; accessibleName: "Forward 10 seconds"; onClicked: root.session.seekBy(10) }
    MediaButton { iconText: "󰒭"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.player && root.player.canGoNext; opacity: enabled ? 1 : 0.35; tooltipText: "Next"; accessibleName: "Next"; onClicked: root.session.runAction("next") }
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.rowGap
    visible: root.modeCapabilities.shuffle || root.modeCapabilities.loop
    MediaButton { text: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle"; iconText: "󰒟"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.player && root.player.shuffleSupported && root.player.shuffle; visible: root.modeCapabilities.shuffle; onClicked: if (root.player) root.player.shuffle = !root.player.shuffle }
    MediaButton { text: root.player && root.player.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat"; iconText: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.player && root.player.loopSupported && root.player.loopState !== MprisLoopState.None; visible: root.modeCapabilities.loop; onClicked: root.session.cycleLoop() }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    visible: root.player !== null ? root.player.volumeSupported : false
    MediaButton { iconText: root.session.volume <= 0.01 ? "󰝟" : (root.session.volume < 0.5 ? "󰕿" : "󰕾"); foreground: root.popupText; accent: Color.accent; focusable: true; tooltipText: root.session.volume <= 0.01 ? "Unmute" : "Mute"; accessibleName: tooltipText; onClicked: root.session.toggleMute() }
    MediaSlider { width: parent.width - Style.space(86); bar: root.bar; value: root.session.volume; minimum: 0; maximum: 1; step: 0.05; motionEnabled: root.motionEnabled; fillColor: root.session.artworkAccent; knobColor: root.popupText; trackColor: Util.alpha(root.popupText, 0.22); accessibleName: "Volume"; accessibleValueText: Math.round(root.session.volume * 100) + "%"; onMoved: function(value) { root.session.setVolume(value) }; onReleased: function(value) { root.session.setVolume(value) }; onRightClicked: root.session.toggleMute() }
    Text { width: Style.space(42); text: Math.round(root.session.volume * 100) + "%"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
  }

  Flow {
    id: utilityRow
    width: parent.width
    spacing: Style.spacing.rowGap
    MediaButton {
      id: sourceChip
      visible: root.hasPlayer && root.session.sourcePlayers.length > 1
      text: root.session.sourceName
      iconText: "󰓃"
      foreground: root.popupText
      accent: Color.accent
      selected: sourceMenu.opened
      focusable: true
      accessibleName: "Choose media source"
      onClicked: sourceMenu.opened ? sourceMenu.close() : sourceMenu.open()
    }
    MediaButton { visible: root.session.sleepMode !== ""; text: root.session.sleepLabel; iconText: "󰔛"; foreground: root.popupText; accent: Color.accent; selected: true; focusable: true; onClicked: root.moreRequested() }
    MediaButton { text: "More"; iconText: "󰅂"; foreground: root.popupText; accent: Color.accent; focusable: true; accessibleName: "More player options"; onClicked: root.moreRequested() }
  }

  Grid {
    width: parent.width
    columns: root.stackedActions || !root.hasMedia ? 1 : 2
    columnSpacing: Style.spacing.rowGap
    rowSpacing: Style.spacing.rowGap
    MediaButton {
      id: openButton
      width: parent.columns === 1 ? parent.width : Math.max(1, (parent.width - parent.columnSpacing) * 0.68)
      text: root.hasPlayer ? "Open Apple Music" : "Open Apple Music"
      iconText: "󰎆"
      foreground: root.popupText
      accent: Color.accent
      background: Util.alpha(root.session.artworkAccent, 0.14)
      bordered: true
      focusable: true
      accessibleName: root.hasPlayer ? "Open or focus Apple Music" : "Open Apple Music to start listening"
      onClicked: root.session.openAppleMusic()
    }
    MediaButton {
      width: parent.columns === 1 ? parent.width : Math.max(1, (parent.width - parent.columnSpacing) * 0.32)
      visible: root.hasMedia
      text: "Copy"
      iconText: "󰆏"
      foreground: root.popupText
      accent: Color.accent
      bordered: true
      focusable: true
      enabled: root.session.copyAvailable
      opacity: enabled ? 1 : 0.35
      tooltipText: root.session.copyAvailable ? "Copy now playing" : "wl-copy is unavailable"
      onClicked: root.session.copyMetadata(root.player)
    }
  }

  SourcePopover {
    id: sourceMenu
    parent: root
    x: 0
    y: utilityRow.y + utilityRow.height + Style.spacing.labelGap
    width: root.width
    session: root.session
    bar: root.bar
    onSelected: function(key) { root.session.selectSource(key) }
  }
}
