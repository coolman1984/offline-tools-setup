import QtQuick
import QtQuick.Layouts

SurfaceCard {
    id: tile
    property string eyebrow: "STATUS"
    property string value: "—"
    property string note: ""
    property string tone: "neutral"
    property string glyph: ""

    implicitHeight: 130

    RowLayout {
        anchors.fill: parent
        anchors.margins: 17
        spacing: 12
        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignTop
            radius: 11
            color: tile.theme.toneBackground(tile.tone)
            border.width: 1
            border.color: tile.theme.toneBorder(tile.tone)
            Text {
                anchors.centerIn: parent
                text: tile.glyph
                color: tile.theme.toneForeground(tile.tone)
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: tile.eyebrow
                color: tile.theme.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.7
            }
            Text {
                text: tile.value
                color: tile.tone === "neutral" ? tile.theme.textStrong : tile.theme.toneForeground(tile.tone)
                font.pixelSize: 21
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: tile.note
                color: tile.theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
