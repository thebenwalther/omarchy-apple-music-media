import QtQuick
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

Item {
  id: root
  property QtObject bar: null
  property real value: 0
  property real maximum: 0
  property bool seekable: false
  property bool motionEnabled: true
  property color accent: Color.accent
  property color foreground: Color.popups.text
  property real liveValue: value
  property real hoverValue: value
  property bool dragging: false
  signal moved(real value)
  signal released(real value)

  implicitHeight: Math.max(Style.space(25), knob.width + Style.space(8))
  activeFocusOnTab: seekable
  Accessible.name: "Seek position"
  Accessible.role: Accessible.Slider
  readonly property real progress: maximum > 0 ? Math.max(0, Math.min(1, liveValue / maximum)) : 0

  onValueChanged: if (!dragging) liveValue = value
  Keys.onLeftPressed: function(event) {
    if (!seekable) return
    liveValue = Math.max(0, liveValue - 10)
    root.released(liveValue)
    event.accepted = true
  }
  Keys.onRightPressed: function(event) {
    if (!seekable) return
    liveValue = Math.min(maximum, liveValue + 10)
    root.released(liveValue)
    event.accepted = true
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
    radius: height / 2
    color: Util.alpha(root.foreground, 0.22)
  }
  Rectangle {
    anchors.left: track.left
    anchors.verticalCenter: track.verticalCenter
    width: track.width * root.progress
    height: track.height
    radius: track.radius
    color: root.accent
    Behavior on width {
      enabled: root.motionEnabled && !root.dragging
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
  }
  BorderSurface {
    id: knob
    width: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
    height: width
    radius: width / 2
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
    color: root.foreground
    borderSpec: Border.flat(root.bar ? root.bar.background : Color.popups.background, Math.max(1, Style.space(2)))
    scale: timelineMouse.containsMouse || root.dragging || root.activeFocus ? 1.14 : 1
    Behavior on x {
      enabled: root.motionEnabled && !root.dragging
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
      enabled: root.motionEnabled
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }
  MouseArea {
    id: timelineMouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.seekable && root.maximum > 0
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    function valueFromX(x) {
      return Math.max(0, Math.min(root.maximum, (Math.max(0, Math.min(width, x)) / Math.max(1, width)) * root.maximum))
    }
    onPositionChanged: function(mouse) {
      root.hoverValue = valueFromX(mouse.x)
      if (root.dragging) {
        root.liveValue = root.hoverValue
        root.moved(root.liveValue)
      }
    }
    onPressed: function(mouse) {
      root.forceActiveFocus()
      root.dragging = true
      root.liveValue = valueFromX(mouse.x)
      root.hoverValue = root.liveValue
      root.moved(root.liveValue)
    }
    onReleased: function(mouse) {
      root.dragging = false
      root.released(root.liveValue)
    }
  }
  PanelToolTip {
    visible: timelineMouse.containsMouse && root.seekable && root.maximum > 0
    text: MediaController.formatTime(root.hoverValue) + " / " + MediaController.formatTime(root.maximum)
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  }
}
