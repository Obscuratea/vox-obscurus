import QtQuick
import QtQuick.Controls.Basic

// A square button with a line icon, and optionally a label beside it. `checked` gives it the accent.
Rectangle {
    id: button
    required property var app
    property string icon
    property string text
    property string tip
    property bool checked: false
    property color tint: app.accent
    property bool quiet: false          // no fill or edge until hovered
    signal clicked()

    implicitHeight: 34
    implicitWidth: text !== "" ? row.implicitWidth + 22 : 34
    radius: app.soft ? 11 : 0
    color: checked ? Qt.alpha(tint, 0.16) : mouse.containsMouse ? app.hover : quiet || !app.soft ? "transparent" : app.tonal
    border.color: checked ? Qt.alpha(tint, 0.5) : quiet ? "transparent" : app.soft ? app.controlEdge : app.line
    opacity: enabled ? 1 : 0.35

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            name: button.icon
            color: button.checked ? button.tint : button.app.ink
            width: 17; height: 17
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.text !== ""
            text: button.text
            color: button.checked ? button.tint : button.app.ink
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
