import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: button
    required property var app
    property string text
    property string tip
    signal clicked()

    implicitHeight: 32
    implicitWidth: label.implicitWidth + 28
    color: mouse.pressed ? app.accent : mouse.containsMouse ? app.hover : "transparent"
    border.color: mouse.containsMouse ? app.accent : app.line

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: mouse.pressed ? button.app.accentInk : button.app.ink
        font.pixelSize: 12
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
