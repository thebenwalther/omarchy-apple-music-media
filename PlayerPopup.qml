import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Window
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

KeyboardPanel {
  id: root

  property var session: null
  property bool barProgressEnabled: true
  property string barDisplayMode: "full"
  property bool motionEnabled: true
  property string page: "player"
  property real pageProgress: page === "more" ? 1 : 0

  readonly property string responsiveClass: MediaController.responsiveClass(contentWidth)
  readonly property bool canSeek: session && session.currentPlayer && session.currentPlayer.canSeek && session.currentPlayer.positionSupported
  readonly property bool canToggle: session && session.currentPlayer
    && (session.currentPlayer.canTogglePlaying || session.currentPlayer.canPlay || session.currentPlayer.canPause)
  readonly property real activePageHeight: page === "more" ? morePage.implicitHeight : playerPage.implicitHeight

  signal preferenceRequested(string key, var value)
  signal closeRequested()

  focusTarget: keyScope
  contentWidth: fittedContentWidth(Style.space(520))
  contentHeight: fittedContentHeight(activePageHeight, Style.space(700))

  Behavior on contentHeight {
    enabled: root.motionEnabled
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }
  Behavior on pageProgress {
    enabled: root.motionEnabled
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  function resetForOpen() {
    page = "player"
    playerView.contentY = 0
    moreView.contentY = 0
    Qt.callLater(function() { playerPage.focusFirst() })
  }

  function showMore() {
    page = "more"
    moreView.contentY = 0
    Qt.callLater(function() { morePage.focusFirst() })
  }

  function showPlayer() {
    page = "player"
    Qt.callLater(function() { playerPage.focusFirst() })
  }

  function ensureFocusVisible(item) {
    if (!item || !open) return
    var view = page === "more" ? moreView : playerView
    if (!view || !view.contentItem) return
    var point = item.mapToItem(view.contentItem, 0, 0)
    if (point.y < view.contentY) view.contentY = Math.max(0, point.y - Style.spacing.popupPadding)
    else if (point.y + item.height > view.contentY + view.height)
      view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), point.y + item.height - view.height + Style.spacing.popupPadding)
  }

  onOpenChanged: {
    if (open) resetForOpen()
    else if (owner && owner.popupOpen) closeRequested()
  }

  FocusScope {
    id: keyScope
    anchors.fill: parent
    focus: true

    Connections {
      target: keyScope.Window.window
      function onActiveFocusItemChanged() {
        var window = keyScope.Window.window
        if (window) Qt.callLater(function() { root.ensureFocusVisible(window.activeFocusItem) })
      }
    }

    Keys.onEscapePressed: function(event) {
      if (root.page === "more") root.showPlayer()
      else root.closeRequested()
      event.accepted = true
    }
    Keys.onSpacePressed: function(event) {
      if (root.canToggle) root.session.runAction("playPause")
      event.accepted = true
    }
    Keys.onLeftPressed: function(event) {
      if (root.canSeek) root.session.seekBy(-10)
      event.accepted = true
    }
    Keys.onRightPressed: function(event) {
      if (root.canSeek) root.session.seekBy(10)
      event.accepted = true
    }
    Keys.onUpPressed: function(event) {
      if (root.session && root.session.currentPlayer && root.session.currentPlayer.volumeSupported)
        root.session.setVolume(root.session.volume + 0.05)
      event.accepted = true
    }
    Keys.onDownPressed: function(event) {
      if (root.session && root.session.currentPlayer && root.session.currentPlayer.volumeSupported)
        root.session.setVolume(root.session.volume - 0.05)
      event.accepted = true
    }

    Item {
      anchors.fill: parent
      clip: true

      Flickable {
        id: playerView
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: playerPage.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        opacity: 1 - root.pageProgress
        x: -root.pageProgress * width * 0.12
        visible: opacity > 0.01
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: playerView.contentHeight > playerView.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff }

        PlayerPage {
          id: playerPage
          width: playerView.width - (playerView.contentHeight > playerView.height ? Style.spacing.rowGap : 0)
          bar: root.bar
          session: root.session
          responsiveClass: root.responsiveClass
          motionEnabled: root.motionEnabled
          active: root.open && root.page === "player"
          onMoreRequested: root.showMore()
        }
      }

      Flickable {
        id: moreView
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: morePage.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        opacity: root.pageProgress
        x: (1 - root.pageProgress) * width * 0.12
        visible: opacity > 0.01
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: moreView.contentHeight > moreView.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff }

        MorePage {
          id: morePage
          width: moreView.width - (moreView.contentHeight > moreView.height ? Style.spacing.rowGap : 0)
          bar: root.bar
          session: root.session
          responsiveClass: root.responsiveClass
          active: root.open && root.page === "more"
          dynamicArtworkColor: root.owner ? root.owner.dynamicArtworkColor : true
          barProgressEnabled: root.barProgressEnabled
          barDisplayMode: root.barDisplayMode
          motionEnabled: root.motionEnabled
          trackChangeOsd: root.owner ? root.owner.trackChangeOsd : false
          rememberSessionHistory: root.owner ? root.owner.rememberSessionHistory : true
          onBackRequested: root.showPlayer()
          onPreferenceRequested: function(key, value) { root.preferenceRequested(key, value) }
        }
      }
    }
  }
}
