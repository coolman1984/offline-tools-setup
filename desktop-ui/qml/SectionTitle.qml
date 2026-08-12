import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: section
    required property var theme
    property string title: ""
    property string description: ""
    property string eyebrow: ""
    spacing: 4

    Text {
        visible: section.eyebrow.length > 0
        text: section.eyebrow.toUpperCase()
        color: section.theme.accent
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 0.9
    }
    Text {
        text: section.title
        color: section.theme.textStrong
        font.pixelSize: 19
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    Text {
        visible: section.description.length > 0
        text: section.description
        color: section.theme.textMuted
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
