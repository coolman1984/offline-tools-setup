import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property var theme
    property bool interactive: false
    property bool selected: false
    property color baseColor: theme.surface
    property int cardRadius: theme.radiusLarge

    radius: cardRadius
    color: selected ? theme.accentSoft : (interactive && hover.hovered ? theme.surfaceRaised : baseColor)
    border.width: selected ? 1 : 1
    border.color: selected ? theme.toneBorder("accent") : (interactive && hover.hovered ? theme.borderStrong : theme.border)

    HoverHandler { id: hover; enabled: card.interactive }

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    scale: interactive && hover.hovered ? 1.006 : 1.0

    Rectangle {
        visible: card.interactive && hover.hovered
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 2
        radius: 1
        color: card.selected ? theme.accent : "#DCE4EF"
        opacity: 0.8
    }
}
