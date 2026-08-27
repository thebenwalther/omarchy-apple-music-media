import QtQuick
import QtQuick.Effects
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

BorderSurface {
  id: root

  property var bar: null
  property var session: null
  property string responsiveClass: "wide"
  property bool motionEnabled: true
  property string displayedArtUrl: ""
  property string previousArtUrl: ""
  property real artReveal: 1
  property real metadataReveal: 1

  readonly property bool narrow: responsiveClass === "narrow"
  readonly property bool medium: responsiveClass === "medium"
  readonly property real artworkSize: narrow ? Style.space(156) : (medium ? Style.space(138) : Style.space(176))
  readonly property color popupText: Color.popups.text
  readonly property color mutedText: Util.alpha(Color.popups.text, 0.68)
  readonly property string artUrl: session && session.hasMedia ? session.artUrl : ""
  readonly property string metadataSignature: session
    ? [session.title, session.artist, session.album].join("\u001f") : ""

  width: parent ? parent.width : Style.space(520)
  height: narrow
    ? Style.spacing.popupPadding * 2 + artworkSize + Style.spacing.panelGap + metadata.implicitHeight
    : Math.max(artworkSize, metadata.implicitHeight) + Style.spacing.popupPadding * 2
  radius: Style.cornerRadius
  color: Style.normalFillFor(popupText, session ? session.artworkAccent : Color.accent)
  borderSpec: Border.flat(Util.alpha(session ? session.artworkAccent : Color.accent, 0.36), Math.max(1, Style.spacing.hairline))
  clip: true

  function swapArtwork() {
    if (displayedArtUrl === artUrl) return
    previousArtUrl = displayedArtUrl
    displayedArtUrl = artUrl
    if (!motionEnabled || previousArtUrl === "") {
      artReveal = 1
      previousArtUrl = ""
      return
    }
    artReveal = 0
    artworkTransition.restart()
  }

  onArtUrlChanged: swapArtwork()
  onMetadataSignatureChanged: {
    if (!motionEnabled) return
    metadataReveal = 0
    metadataTransition.restart()
  }
  onMotionEnabledChanged: if (!motionEnabled) {
    artworkTransition.stop()
    metadataTransition.stop()
    artReveal = 1
    metadataReveal = 1
    previousArtUrl = ""
  }
  Component.onCompleted: swapArtwork()

  NumberAnimation {
    id: artworkTransition
    target: root
    property: "artReveal"
    from: 0
    to: 1
    duration: MediaController.motionDuration(root.motionEnabled, 220)
    easing.type: Easing.OutCubic
    onFinished: root.previousArtUrl = ""
  }
  NumberAnimation {
    id: metadataTransition
    target: root
    property: "metadataReveal"
    from: 0
    to: 1
    duration: MediaController.motionDuration(root.motionEnabled, 200)
    easing.type: Easing.OutCubic
  }

  Image {
    id: backdropSource
    anchors.fill: parent
    source: root.displayedArtUrl
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: 512
    sourceSize.height: 512
    visible: false
  }
  MultiEffect {
    anchors.fill: parent
    source: backdropSource
    visible: root.displayedArtUrl !== "" && backdropSource.status === Image.Ready
    autoPaddingEnabled: false
    blurEnabled: true
    blur: 1
    blurMax: 64
    blurMultiplier: 1.3
    saturation: 0.28
    brightness: -0.42
  }
  Rectangle { anchors.fill: parent; color: Util.alpha(Color.popups.background, root.displayedArtUrl === "" ? 0.78 : 0.62) }
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha(root.session ? root.session.artworkAccent : Color.accent, 0.2) }
      GradientStop { position: 0.62; color: "transparent" }
      GradientStop { position: 1; color: Util.alpha(Color.popups.background, 0.32) }
    }
  }

  Item {
    id: artworkFrame
    width: root.artworkSize
    height: width
    anchors.left: root.narrow ? undefined : parent.left
    anchors.leftMargin: root.narrow ? 0 : Style.spacing.popupPadding
    anchors.horizontalCenter: root.narrow ? parent.horizontalCenter : undefined
    anchors.top: root.narrow ? parent.top : undefined
    anchors.topMargin: root.narrow ? Style.spacing.popupPadding : 0
    anchors.verticalCenter: root.narrow ? undefined : parent.verticalCenter

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.spacing.sm
      radius: Style.cornerRadius + Style.spacing.sm
      color: Util.alpha(root.session ? root.session.artworkAccent : Color.accent, 0.15)
    }
    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.selectedFillFor(root.popupText, root.session ? root.session.artworkAccent : Color.accent)
      borderSpec: Border.flat(Util.alpha(root.session ? root.session.artworkAccent : Color.accent, 0.7), Math.max(1, Style.spacing.hairline))
      clip: true
      Image {
        anchors.fill: parent
        source: root.previousArtUrl
        sourceSize.width: 512
        sourceSize.height: 512
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 1 - root.artReveal
        visible: source !== "" && opacity > 0
      }
      Image {
        id: currentArtwork
        anchors.fill: parent
        source: root.displayedArtUrl
        sourceSize.width: 512
        sourceSize.height: 512
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: root.artReveal
        scale: root.motionEnabled ? 0.98 + root.artReveal * 0.02 : 1
        visible: source !== ""
      }
      Text {
        anchors.centerIn: parent
        visible: root.displayedArtUrl === "" || currentArtwork.status === Image.Error
        text: "󰝚"
        color: root.popupText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.displayLarge
      }
      Text {
        anchors.centerIn: parent
        visible: currentArtwork.status === Image.Loading
        text: root.motionEnabled ? "󰑓" : "󰄬"
        color: root.mutedText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.iconLarge
        RotationAnimation on rotation {
          from: 0; to: 360; duration: 900; loops: Animation.Infinite
          running: root.motionEnabled && currentArtwork.status === Image.Loading
        }
      }
    }
  }

  Column {
    id: metadata
    anchors.left: root.narrow ? parent.left : artworkFrame.right
    anchors.right: parent.right
    anchors.leftMargin: root.narrow ? Style.spacing.popupPadding : Style.spacing.panelGap
    anchors.rightMargin: Style.spacing.popupPadding
    anchors.top: root.narrow ? artworkFrame.bottom : undefined
    anchors.topMargin: root.narrow ? Style.spacing.panelGap : 0
    anchors.verticalCenter: root.narrow ? undefined : parent.verticalCenter
    spacing: Style.spacing.labelGap
    opacity: root.motionEnabled ? 0.35 + root.metadataReveal * 0.65 : 1
    scale: root.motionEnabled ? 0.98 + root.metadataReveal * 0.02 : 1

    Row {
      width: parent.width
      spacing: Style.spacing.md
      Rectangle {
        width: Style.spacing.lg
        height: width
        radius: width / 2
        color: root.session && root.session.playing ? root.session.artworkAccent : root.mutedText
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        width: parent.width - Style.spacing.panelGap
        text: root.session && root.session.hasPlayer
          ? (root.session.playing ? "NOW PLAYING · " : "PAUSED · ") + root.session.sourceName.toUpperCase()
          : "APPLE MUSIC"
        textFormat: Text.PlainText
        color: root.mutedText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }
    }
    Text {
      width: parent.width
      text: root.session ? root.session.title : "Apple Music"
      textFormat: Text.PlainText
      color: root.popupText
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: root.narrow ? Style.font.title : Style.font.title
      font.bold: true
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.session ? root.session.artist : "Open to start listening"
      textFormat: Text.PlainText
      color: root.popupText
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.session && root.session.hasMedia ? root.session.album : "Your library and playlists are one click away"
      textFormat: Text.PlainText
      color: root.mutedText
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      visible: text !== ""
      elide: Text.ElideRight
    }
  }
}
