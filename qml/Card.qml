import QtQuick

// The box every strip and panel sits in: the theme's fill, edge and corner style.
Rectangle {
    id: card
    required property var app
    property bool selected: false
    property real corner: app.rCard

    color: app.diamond ? "transparent" : app.panelFill
    radius: corner
    border.width: selected ? 2 : 1
    border.color: selected ? app.accent : app.diamond ? "transparent" : app.edge

    Raised { app: card.app; radius: card.corner }
    Glass { app: card.app; radius: card.corner }
    CutFrame { visible: card.app.diamond; anchors.fill: parent; cut: card.app.cut; fill: card.app.panelFill; stroke: card.selected ? card.app.accent : card.app.frameDim }
}
