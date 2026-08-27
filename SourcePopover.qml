import QtQuick
import QtQuick.Controls as QQC
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

QQC.Popup {
  id: root

  property var session: null
  property var bar: null
  property color popupText: Color.popups.text
  property color mutedText: Util.alpha(Color.popups.text, 0.68)

  signal selected(string key)

  width: parent ? parent.width : Style.spacing.dropdownWidth
  implicitHeight: Math.min(sourceList.contentHeight + topPadding + bottomPadding, Style.space(280))
  padding: Style.spacing.sm
  leftPadding: Style.spacing.sm + Border.left(popoverBorder)
  rightPadding: Style.spacing.sm + Border.right(popoverBorder)
  topPadding: Style.spacing.sm + Border.top(popoverBorder)
  bottomPadding: Style.spacing.sm + Border.bottom(popoverBorder)
  focus: true
  closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutsideParent

  readonly property var popoverBorder: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

  background: BorderSurface {
    color: Color.popups.background
    borderSpec: root.popoverBorder
    radius: Style.cornerRadius
  }

  onOpened: {
    var selectedKey = session ? session.currentKey : ""
    sourceList.currentIndex = 0
    if (session && session.mediaService) {
      for (var index = 0; index < session.sourcePlayers.length; index++) {
        if (session.mediaService.playerKey(session.sourcePlayers[index]) === selectedKey) {
          sourceList.currentIndex = index
          break
        }
      }
    }
    sourceList.forceActiveFocus()
  }

  contentItem: ListView {
    id: sourceList
    clip: true
    spacing: Style.spacing.labelGap
    boundsBehavior: Flickable.StopAtBounds
    model: root.session ? root.session.sourcePlayers : []
    currentIndex: -1
    activeFocusOnTab: true
    Accessible.role: Accessible.List
    Accessible.name: "Media sources"

    Keys.onEscapePressed: { root.close(); event.accepted = true }
    Keys.onUpPressed: function(event) {
      currentIndex = Math.max(0, currentIndex - 1)
      positionViewAtIndex(currentIndex, ListView.Contain)
      event.accepted = true
    }
    Keys.onDownPressed: function(event) {
      currentIndex = Math.min(count - 1, currentIndex + 1)
      positionViewAtIndex(currentIndex, ListView.Contain)
      event.accepted = true
    }
    Keys.onReturnPressed: function(event) { activateCurrent(); event.accepted = true }
    Keys.onEnterPressed: function(event) { activateCurrent(); event.accepted = true }
    Keys.onSpacePressed: function(event) { activateCurrent(); event.accepted = true }

    function activateCurrent() {
      if (!root.session || !root.session.mediaService || currentIndex < 0 || currentIndex >= count) return
      var key = root.session.mediaService.playerKey(root.session.sourcePlayers[currentIndex])
      var result = MediaController.sourcePopoverSelection(key)
      root.selected(result.selectedKey)
      root.close()
    }

    delegate: MediaButton {
      required property var modelData
      required property int index
      readonly property string key: root.session && root.session.mediaService ? root.session.mediaService.playerKey(modelData) : ""
      width: sourceList.width
      text: MediaController.sourceDetail(modelData)
      iconText: modelData && modelData.isPlaying ? "󰏤" : "󰐊"
      foreground: root.popupText
      accent: Color.accent
      leftAlign: true
      focusable: false
      selected: key === (root.session ? root.session.currentKey : "") || index === sourceList.currentIndex
      bordered: key === (root.session ? root.session.currentKey : "")
      accessibleName: MediaController.sourceName(modelData, root.session ? root.session.applePlayerKey : "") + " — " + text
      onHovered: function(isHovered) { if (isHovered) sourceList.currentIndex = index }
      onClicked: {
        var result = MediaController.sourcePopoverSelection(key)
        root.selected(result.selectedKey)
        root.close()
      }
    }
  }
}
