import QtQuick
import QtQuick.Layouts

// Back of the right-hand side: how Vox looks, and (later) other settings.
ColumnLayout {
    id: panel
    required property var app
    spacing: 10

    function swatch(t) {
        return t.style === "auto"
            ? { bg: panel.app.systemWindow, text: panel.app.systemText, accent: panel.app.systemAccent }
            : { bg: t.window, text: t.text, accent: t.accent };
    }

    Text {
        text: panel.app.t("Settings")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: panel.app.soft ? 12 : 11
        font.weight: panel.app.soft ? Font.Medium : Font.Normal
        font.letterSpacing: panel.app.soft || panel.app.diamond ? 0.3 : 2
    }

    Text {
        Layout.topMargin: 6
        text: panel.app.t("Theme")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: panel.app.themeList
            Rectangle {
                id: card
                required property var modelData
                readonly property var sw: panel.swatch(modelData)
                readonly property bool selected: panel.app.theme.id === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 72
                radius: panel.app.rBox
                color: mouse.containsMouse ? Qt.tint(panel.app.panel, Qt.alpha(panel.app.accent, 0.10)) : panel.app.panel
                border.width: selected ? 2 : 1
                border.color: selected ? panel.app.accent : (panel.app.soft ? "transparent" : panel.app.line)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // A tiny preview of the theme's own colours.
                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 40
                        radius: card.modelData.style === "soft" ? 8 : 0
                        color: card.sw.bg
                        border.color: Qt.alpha(card.sw.text, 0.3)
                        Rectangle { x: 8; y: 9; width: 22; height: 6; radius: parent.radius > 0 ? 3 : 0; color: card.sw.accent }
                        Rectangle { x: 8; y: 21; width: 36; height: 4; radius: parent.radius > 0 ? 2 : 0; color: Qt.alpha(card.sw.text, 0.7) }
                        Rectangle { x: 8; y: 29; width: 26; height: 4; radius: parent.radius > 0 ? 2 : 0; color: Qt.alpha(card.sw.text, 0.35) }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            color: panel.app.ink
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.note
                            color: panel.app.dim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.app.change(c => c.theme = card.modelData.id)
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: "\"Follow system\" takes its look from your Plasma colour scheme. The others keep their own colours."
        color: panel.app.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    Item { Layout.fillHeight: true }
}
