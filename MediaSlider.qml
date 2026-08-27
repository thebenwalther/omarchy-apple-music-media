import QtQuick
import qs.Ui
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property bool motionEnabled: true
  property color trackColor: Util.alpha(Color.popups.text, 0.22)
  property color fillColor: Color.accent
  property color knobColor: Color.popups.text
  property string accessibleName: "Slider"
  property string accessibleValueText: Math.round(liveValue * 100) + "%"
  property bool dragging: false
  property real liveValue: value

  signal moved(real value)
  signal released(real value)
  signal rightClicked()

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)
  activeFocusOnTab: enabled

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  readonly property bool hot: sliderMouse.containsMouse || dragging || activeFocus

  Accessible.role: Accessible.Slider
  Accessible.name: accessibleName
  Accessible.description: accessibleValueText
  Accessible.focusable: enabled
  Accessible.focused: activeFocus
  Accessible.ignored: !visible
  Accessible.onIncreaseAction: stepBy(1)
  Accessible.onDecreaseAction: stepBy(-1)

  onValueChanged: if (!dragging) liveValue = value

  function normalized(value) {
    var bounded = Math.max(minimum, Math.min(maximum, Number(value || 0)))
    if (integer) bounded = Math.round(bounded)
    return bounded
  }

  function stepBy(direction) {
    var next = normalized(liveValue + Number(direction || 0) * step)
    liveValue = next
    moved(next)
    released(next)
  }

  Keys.onLeftPressed: function(event) { stepBy(-1); event.accepted = true }
  Keys.onDownPressed: function(event) { stepBy(-1); event.accepted = true }
  Keys.onRightPressed: function(event) { stepBy(1); event.accepted = true }
  Keys.onUpPressed: function(event) { stepBy(1); event.accepted = true }
  Keys.onSpacePressed: function(event) { rightClicked(); event.accepted = true }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Home) {
      liveValue = minimum
      moved(liveValue)
      released(liveValue)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      liveValue = maximum
      moved(liveValue)
      released(liveValue)
      event.accepted = true
    }
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    anchors.left: track.left
    anchors.verticalCenter: track.verticalCenter
    width: track.width * root.progress
    height: track.height
    radius: track.radius
    color: root.fillColor
    Behavior on width {
      enabled: root.motionEnabled && !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  BorderSurface {
    id: knob
    width: root.knobSize
    height: width
    radius: width / 2
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
    color: root.knobColor
    borderSpec: root.activeFocus
      ? Border.controlSpec("focus", Color.popups.text, Color.accent)
      : Border.flat(root.bar ? root.bar.background : Color.popups.background, Math.max(1, Style.spacing.hairline))
    scale: root.hot ? 1.15 : 1
    Behavior on x {
      enabled: root.motionEnabled && !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
      enabled: root.motionEnabled
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: sliderMouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    function valueFromX(x) {
      return root.normalized(root.minimum + (Math.max(0, Math.min(track.width, x)) / Math.max(1, track.width)) * root.range)
    }

    onPressed: function(mouse) {
      root.forceActiveFocus()
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      root.liveValue = valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      root.liveValue = valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
    }
    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.rightClicked() }
    onWheel: function(wheel) { root.stepBy(wheel.angleDelta.y > 0 ? 1 : -1) }
  }
}
