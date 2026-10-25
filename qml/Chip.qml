import QtQuick
import QtQuick.Controls.Basic

// A toggle: routing buttons (A1, B1...), mute, and the gate switch.
Rectangle {
    id: chip
    required property var app
    property string text
    property bool checked
    property string tip
    property color onColor: app.accent
    signal toggled()

    implicitWidth: Math.max(44, label.implicitWidth + 20)
    implicitHeight: 28
    color: checked ? onColor : mouse.containsMouse ? app.hover : "transparent"
    border.color: checked ? onColor : app.line

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.checked ? chip.app.accentInk : chip.app.ink
        font.family: chip.app.mono
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.toggled()
    }

    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
