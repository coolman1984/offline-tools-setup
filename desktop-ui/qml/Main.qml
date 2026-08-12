import QtQuick
import QtQuick.Controls
import QtQuick.Controls.FluentWinUI3
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 720
    title: "Offline Automation & Development Suite"
    color: "#F5F7FA"

    palette.window: "#F5F7FA"
    palette.windowText: "#172033"
    palette.base: "#FFFFFF"
    palette.alternateBase: "#F8FAFC"
    palette.text: "#172033"
    palette.button: "#FFFFFF"
    palette.buttonText: "#172033"
    palette.highlight: "#2563EB"
    palette.highlightedText: "#FFFFFF"
    palette.mid: "#D9E0E8"

    property color canvas: "#F5F7FA"
    property color surface: "#FFFFFF"
    property color surfaceSoft: "#F8FAFC"
    property color border: "#E4E9F0"
    property color textStrong: "#172033"
    property color textMuted: "#667085"
    property color accent: "#2563EB"
    property color accentSoft: "#EAF1FF"
    property color success: "#18794E"
    property color successSoft: "#EAF8F1"
    property color warning: "#B54708"
    property color warningSoft: "#FFF5E8"
    property color danger: "#B42318"
    property color dangerSoft: "#FFF0EE"
    property int currentPage: 0
    property string selectedCarePreset: "quick-health"
    property string deviceSection: "overview"
    property real taskProgress: 0
    property string taskMessage: "Ready"
    property string toastTitle: ""
    property string toastMessage: ""

    readonly property var navigation: [
        { "label": "Home", "glyph": "⌂", "description": "Status and quick actions" },
        { "label": "Setup", "glyph": "＋", "description": "Install your workstation" },
        { "label": "Safe Repair", "glyph": "◇", "description": "Diagnostics and safe care" },
        { "label": "Device Details", "glyph": "▣", "description": "Hardware and Windows state" },
        { "label": "Skills Hub", "glyph": "✦", "description": "AI skills and targets" },
        { "label": "Logs & Evidence", "glyph": "≡", "description": "Plans, state and receipts" }
    ]

    function pageTitle(index) {
        return ["Home", "Professional Setup", "Windows Safe Care", "Device Details", "Developer Skills Hub", "Logs & Evidence"][index]
    }

    function pageSubtitle(index) {
        return [
            "A clear view of workstation readiness, tools and next actions.",
            "Choose a ready-made setup or tailor exactly what this PC needs.",
            "Run diagnostics first, then apply only the repairs you explicitly approve.",
            "Read-only hardware, Windows, storage, network and policy intelligence.",
            "Manage one local skill library and publish it to supported AI development tools.",
            "Review durable plans, logs, state files and evidence from every operation."
        ][index]
    }

    function shortValue(value, fallback) {
        if (value === undefined || value === null || value === "")
            return fallback
        return value
    }

    function runCareWithConfirmation() {
        if (backend.careSummary.hasRepairs)
            repairDialog.open()
        else
            backend.runCare()
    }

    component Surface: Rectangle {
        color: root.surface
        radius: 16
        border.width: 1
        border.color: root.border
    }

    component SoftSurface: Rectangle {
        color: root.surfaceSoft
        radius: 14
        border.width: 1
        border.color: root.border
    }

    component Badge: Rectangle {
        id: badge
        property string label: "Ready"
        property string tone: "neutral"
        implicitWidth: badgeText.implicitWidth + 18
        implicitHeight: 26
        radius: 13
        color: tone === "good" ? root.successSoft : tone === "warn" ? root.warningSoft : tone === "danger" ? root.dangerSoft : root.surfaceSoft
        border.width: 1
        border.color: tone === "good" ? "#CDEDDD" : tone === "warn" ? "#F5D7AE" : tone === "danger" ? "#F2C5C0" : root.border
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label
            color: badge.tone === "good" ? root.success : badge.tone === "warn" ? root.warning : badge.tone === "danger" ? root.danger : root.textMuted
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    component NavButton: Button {
        id: navButton
        required property int pageIndex
        property string glyph: ""
        property string description: ""
        Layout.fillWidth: true
        implicitHeight: 58
        hoverEnabled: true
        leftPadding: 14
        rightPadding: 12
        onClicked: root.currentPage = pageIndex
        background: Rectangle {
            radius: 12
            color: root.currentPage === navButton.pageIndex ? root.accentSoft : navButton.hovered ? "#F0F3F7" : "transparent"
            border.width: root.currentPage === navButton.pageIndex ? 1 : 0
            border.color: "#D5E2FF"
            Rectangle {
                visible: root.currentPage === navButton.pageIndex
                width: 3
                height: 28
                radius: 2
                color: root.accent
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        contentItem: RowLayout {
            spacing: 12
            Text {
                text: navButton.glyph
                color: root.currentPage === navButton.pageIndex ? root.accent : root.textMuted
                font.pixelSize: 20
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Text {
                    text: navButton.text
                    color: root.textStrong
                    font.pixelSize: 14
                    font.weight: root.currentPage === navButton.pageIndex ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: navButton.description
                    color: root.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }

    component MetricCard: Surface {
        id: metric
        property string eyebrow: "STATUS"
        property string value: "—"
        property string note: ""
        property string tone: "neutral"
        implicitHeight: 126
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 5
            Text {
                text: metric.eyebrow
                color: root.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
            Text {
                text: metric.value
                color: metric.tone === "good" ? root.success : metric.tone === "warn" ? root.warning : metric.tone === "danger" ? root.danger : root.textStrong
                font.pixelSize: 23
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: metric.note
                color: root.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    component SectionHeading: ColumnLayout {
        property string title: ""
        property string description: ""
        spacing: 4
        Text {
            text: parent.title
            color: root.textStrong
            font.pixelSize: 19
            font.weight: Font.DemiBold
        }
        Text {
            text: parent.description
            color: root.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    component SegmentedButton: Button {
        id: segment
        property bool selected: false
        hoverEnabled: true
        implicitHeight: 38
        leftPadding: 14
        rightPadding: 14
        background: Rectangle {
            radius: 9
            color: segment.selected ? root.surface : segment.hovered ? "#F1F4F8" : "transparent"
            border.width: segment.selected ? 1 : 0
            border.color: root.border
        }
        contentItem: Text {
            text: segment.text
            color: segment.selected ? root.textStrong : root.textMuted
            font.pixelSize: 12
            font.weight: segment.selected ? Font.DemiBold : Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Dialog {
        id: repairDialog
        anchors.centerIn: Overlay.overlay
        modal: true
        title: "Confirm safe repairs"
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 520
        onAccepted: backend.runCare()
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "You selected " + backend.careSummary.repairCount + " repair action(s). Diagnostics are read-only, but repairs change Windows maintenance state. A restore point is attempted first where Windows and policy allow it."
                color: root.textStrong
                font.pixelSize: 13
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 68
                radius: 12
                color: root.warningSoft
                border.width: 1
                border.color: "#F5D7AE"
                Text {
                    anchors.fill: parent
                    anchors.margins: 12
                    wrapMode: Text.WordWrap
                    text: "The suite never disables security controls, changes boot or encryption settings, deletes user folders, or performs aggressive registry cleaning."
                    color: root.warning
                    font.pixelSize: 12
                }
            }
        }
    }

    Connections {
        target: backend
        function onProgressChanged(percent, message) {
            root.taskProgress = percent
            root.taskMessage = message
        }
        function onProcessFinished(success, message) {
            root.toastTitle = success ? "Completed" : "Action needs attention"
            root.toastMessage = message
            toastTimer.restart()
        }
        function onToastRequested(title, message) {
            root.toastTitle = title
            root.toastMessage = message
            toastTimer.restart()
        }
    }

    Timer {
        id: toastTimer
        interval: 4200
        repeat: false
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 262
            Layout.fillHeight: true
            color: "#FBFCFE"
            border.width: 0

            Rectangle {
                width: 1
                color: root.border
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    spacing: 12
                    Rectangle {
                        width: 42
                        height: 42
                        radius: 13
                        color: root.accent
                        Text {
                            anchors.centerIn: parent
                            text: "O"
                            color: "white"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Text {
                            text: "Offline Tools"
                            color: root.textStrong
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Workstation Suite"
                            color: root.textMuted
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    text: "WORKSPACE"
                    color: "#98A2B3"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    Layout.topMargin: 8
                    Layout.leftMargin: 10
                }

                Repeater {
                    model: root.navigation
                    delegate: NavButton {
                        required property int index
                        required property var modelData
                        pageIndex: index
                        text: modelData.label
                        glyph: modelData.glyph
                        description: modelData.description
                    }
                }

                Item { Layout.fillHeight: true }

                SoftSurface {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 9
                                height: 9
                                radius: 5
                                color: backend.preflight.ScanRunning ? root.warning : root.success
                            }
                            Text {
                                text: backend.preflight.ScanRunning ? "Scanning workstation" : "Local-only control"
                                color: root.textStrong
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: "Software and dependencies come from the verified offline bundle."
                            color: root.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                color: root.surface
                border.width: 0
                Rectangle {
                    height: 1
                    color: root.border
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 30
                    anchors.rightMargin: 30
                    spacing: 16
                    ColumnLayout {
                        spacing: 3
                        Layout.fillWidth: true
                        Text {
                            text: root.pageTitle(root.currentPage)
                            color: root.textStrong
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.pageSubtitle(root.currentPage)
                            color: root.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Badge {
                        label: backend.preflight.ScanRunning ? "Scanning" : (backend.preflight.IsAdministrator ? "Administrator" : "Standard session")
                        tone: backend.preflight.ScanRunning ? "warn" : (backend.preflight.IsAdministrator ? "good" : "warn")
                    }
                    Button {
                        text: "Refresh scan"
                        enabled: !backend.busy && !backend.preflight.ScanRunning
                        onClicked: backend.runPreflight()
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentPage

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: homeContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}

                        ColumnLayout {
                            id: homeContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: 190
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 15
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#FFFFFF" }
                                        GradientStop { position: 1.0; color: "#F2F6FF" }
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 26
                                    spacing: 26
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 9
                                        Badge { label: "OFFLINE WORKSTATION CONTROL"; tone: "neutral" }
                                        Text {
                                            text: "Everything this PC needs, without the guesswork."
                                            color: root.textStrong
                                            font.pixelSize: 28
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: "Scan first, choose a purpose-built setup, review the plan, then let the existing installation engines do the work with checkpoints and evidence."
                                            color: root.textMuted
                                            font.pixelSize: 13
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.preferredWidth: 210
                                        spacing: 10
                                        Button {
                                            text: "Configure setup"
                                            highlighted: true
                                            Layout.fillWidth: true
                                            onClicked: root.currentPage = 1
                                        }
                                        Button {
                                            text: "Run device scan"
                                            Layout.fillWidth: true
                                            enabled: !backend.busy
                                            onClicked: backend.collectDeviceInventory()
                                        }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 4 : 2
                                columnSpacing: 12
                                rowSpacing: 12
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "WINDOWS"
                                    value: root.shortValue(backend.preflight.WindowsName, "Scanning…")
                                    note: "Build " + root.shortValue(backend.preflight.WindowsBuild, "—")
                                    tone: backend.preflight.IsWindows && backend.preflight.Is64Bit ? "good" : "danger"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "SYSTEM DRIVE"
                                    value: backend.preflight.FreeDiskGb > 0 ? backend.preflight.FreeDiskGb.toFixed(1) + " GB free" : "Scanning…"
                                    note: backend.preflight.FreeDiskGb >= 12 ? "Healthy capacity for a professional setup." : "Large profiles may need more free space."
                                    tone: backend.preflight.FreeDiskGb >= 12 ? "good" : "warn"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "RESTART STATE"
                                    value: backend.preflight.PendingReboot ? "Restart pending" : "Clear"
                                    note: backend.preflight.PendingReboot ? "Restart before a large install when practical." : "No restart marker detected."
                                    tone: backend.preflight.PendingReboot ? "warn" : "good"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "OFFICE DESKTOP"
                                    value: backend.preflight.OfficeInstalled ? "Detected" : "Not detected"
                                    note: backend.preflight.OfficeInstalled ? root.shortValue(backend.preflight.OfficeArchitecture, "Architecture available after scan") : "File automation still works; app control requires Office."
                                    tone: backend.preflight.OfficeInstalled ? "good" : "neutral"
                                }
                            }

                            SectionHeading {
                                title: "What would you like to do?"
                                description: "The suite separates installation, diagnostics and evidence so each action is easy to understand before it changes anything."
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 880 ? 3 : 1
                                columnSpacing: 12
                                rowSpacing: 12
                                Surface {
                                    Layout.fillWidth: true
                                    implicitHeight: 150
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 18
                                        spacing: 8
                                        Text { text: "Build this workstation"; color: root.textStrong; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Text { text: "Pick a preset or select individual Office, PDF, data, web, AI and quality components."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Item { Layout.fillHeight: true }
                                        Button { text: "Open Setup"; onClicked: root.currentPage = 1 }
                                    }
                                }
                                Surface {
                                    Layout.fillWidth: true
                                    implicitHeight: 150
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 18
                                        spacing: 8
                                        Text { text: "Check Windows safely"; color: root.textStrong; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Text { text: "Start with read-only checks, then select only the repair actions you actually need."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Item { Layout.fillHeight: true }
                                        Button { text: "Open Safe Repair"; onClicked: root.currentPage = 2 }
                                    }
                                }
                                Surface {
                                    Layout.fillWidth: true
                                    implicitHeight: 150
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 18
                                        spacing: 8
                                        Text { text: "Manage AI skills"; color: root.textStrong; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Text { text: "See the canonical local skill library and which supported AI development tools are detected."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Item { Layout.fillHeight: true }
                                        Button { text: "Open Skills Hub"; onClicked: root.currentPage = 4 }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: setupContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: setupContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            SectionHeading {
                                title: "Choose the outcome first"
                                description: "Presets are safe starting points. Custom mode lets you tune every profile and component without losing the locked Core Foundation."
                                Layout.fillWidth: true
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: presetGrid.implicitHeight + 34
                                Flow {
                                    id: presetGrid
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 17
                                    spacing: 10
                                    Repeater {
                                        model: backend.appData.presets || []
                                        delegate: RadioButton {
                                            required property var modelData
                                            text: modelData.displayName
                                            checked: backend.activePreset === modelData.id
                                            onClicked: backend.applyPreset(modelData.id)
                                        }
                                    }
                                    RadioButton {
                                        text: "Custom Selection"
                                        checked: backend.activePreset === "custom"
                                        onClicked: backend.useCustomSelection()
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 4 : 2
                                columnSpacing: 12
                                rowSpacing: 12
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "SELECTED PROFILES"
                                    value: backend.selectionSummary.profileCount.toString()
                                    note: "Professional capability groups beyond the locked core."
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "COMPONENTS"
                                    value: backend.selectionSummary.componentCount.toString()
                                    note: "Individual optional components in the current plan."
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "ESTIMATED FOOTPRINT"
                                    value: "~" + backend.selectionSummary.estimatedGb.toFixed(1) + " GB"
                                    note: "Safe target: about " + backend.selectionSummary.safeGb + " GB free."
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "CURRENT FREE SPACE"
                                    value: backend.preflight.FreeDiskGb > 0 ? backend.preflight.FreeDiskGb.toFixed(1) + " GB" : "Not scanned"
                                    note: backend.selectionSummary.enoughSpace ? "Capacity is suitable for this plan." : "Reduce the plan or free disk space first."
                                    tone: backend.preflight.FreeDiskGb <= 0 ? "neutral" : (backend.selectionSummary.enoughSpace ? "good" : "danger")
                                }
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: coreColumn.implicitHeight + 36
                                ColumnLayout {
                                    id: coreColumn
                                    anchors.fill: parent
                                    anchors.margins: 18
                                    spacing: 12
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text { text: backend.appData.core ? backend.appData.core.displayName : "Core Foundation"; color: root.textStrong; font.pixelSize: 17; font.weight: Font.DemiBold }
                                            Text { text: backend.appData.core ? backend.appData.core.description : "Always installed."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        }
                                        Badge { label: "Always included"; tone: "good" }
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: backend.appData.core ? backend.appData.core.components : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                height: 30
                                                width: coreChipText.implicitWidth + 20
                                                radius: 9
                                                color: root.surfaceSoft
                                                border.width: 1
                                                border.color: root.border
                                                Text { id: coreChipText; anchors.centerIn: parent; text: modelData.name; color: root.textMuted; font.pixelSize: 11 }
                                            }
                                        }
                                    }
                                }
                            }

                            SectionHeading {
                                title: "Professional profiles"
                                description: "Each profile explains its purpose, footprint and selectable components. Unsupported items remain visible with the reason instead of failing mysteriously later."
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Repeater {
                                    model: backend.appData.profiles || []
                                    delegate: Surface {
                                        id: profileCard
                                        required property var modelData
                                        readonly property string profileId: modelData.id
                                        Layout.fillWidth: true
                                        implicitHeight: profileBody.implicitHeight + 36
                                        ColumnLayout {
                                            id: profileBody
                                            anchors.fill: parent
                                            anchors.margins: 18
                                            spacing: 10
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12
                                                CheckBox {
                                                    id: profileCheck
                                                    checked: {
                                                        var version = backend.selectionVersion
                                                        return backend.isProfileSelected(modelData.id)
                                                    }
                                                    onClicked: backend.setProfileSelected(modelData.id, checked)
                                                    enabled: {
                                                        var scan = backend.preflight
                                                        return backend.profileAvailable(modelData.id)
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: modelData.displayName; color: root.textStrong; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                        Badge { visible: modelData.recommended === true; label: "Recommended"; tone: "good" }
                                                        Badge { label: "~" + (modelData.estimatedMb / 1024).toFixed(1) + " GB"; tone: "neutral" }
                                                    }
                                                    Text { text: modelData.description; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                                }
                                            }
                                            Rectangle { Layout.fillWidth: true; height: 1; color: root.border; visible: profileCheck.checked }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                visible: profileCheck.checked
                                                Repeater {
                                                    model: modelData.components || []
                                                    delegate: RowLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        spacing: 10
                                                        CheckBox {
                                                            checked: {
                                                                var version = backend.selectionVersion
                                                                return backend.isComponentSelected(profileCard.profileId, modelData.id)
                                                            }
                                                            enabled: {
                                                                var scan = backend.preflight
                                                                return modelData.supported !== false && backend.componentAvailable(modelData.id)
                                                            }
                                                            onClicked: backend.setComponentSelected(profileCard.profileId, modelData.id, checked)
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2
                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                Text { text: modelData.name; color: modelData.supported === false ? "#98A2B3" : root.textStrong; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                                                                Badge { visible: modelData.nativeOptional === true; label: "Local media"; tone: "neutral" }
                                                                Badge { visible: modelData.heavy === true; label: "Large"; tone: "warn" }
                                                                Badge { visible: modelData.supported === false; label: "Unavailable"; tone: "danger" }
                                                                Badge { visible: modelData.supported !== false && !backend.componentAvailable(modelData.id); label: "Media missing"; tone: "danger" }
                                                            }
                                                            Text {
                                                                text: modelData.supported === false ? modelData.reason : (!backend.componentAvailable(modelData.id) ? "Required local installation media is not included in this bundle." : (modelData.description || backend.componentHint(modelData.id)))
                                                                color: root.textMuted
                                                                font.pixelSize: 11
                                                                wrapMode: Text.WordWrap
                                                                Layout.fillWidth: true
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: 126
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 18
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text { text: "Review before changing the PC"; color: root.textStrong; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Text { text: "The generated plan records the selected profiles, components, preflight state and local bundle location. You can save it without installing anything."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    Button { text: "Save plan only"; enabled: !backend.busy; onClicked: backend.writeSetupPlan() }
                                    Button { text: "Install selected"; highlighted: true; enabled: !backend.busy && backend.selectionSummary.profileCount > 0; onClicked: backend.startSetup() }
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: careContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: careContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            SectionHeading {
                                title: "Diagnostics first"
                                description: "Quick, deep and complete presets are read-only. Repair actions are never added unless you select them yourself."
                                Layout.fillWidth: true
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: carePresets.implicitHeight + 34
                                Flow {
                                    id: carePresets
                                    anchors.fill: parent
                                    anchors.margins: 17
                                    spacing: 10
                                    Repeater {
                                        model: backend.appData.carePresets || []
                                        delegate: RadioButton {
                                            required property var modelData
                                            text: modelData.name
                                            checked: root.selectedCarePreset === modelData.id
                                            onClicked: {
                                                root.selectedCarePreset = modelData.id
                                                backend.applyCarePreset(modelData.id)
                                            }
                                            ToolTip.visible: hovered
                                            ToolTip.text: modelData.description
                                        }
                                    }
                                    RadioButton {
                                        text: "Custom"
                                        checked: root.selectedCarePreset === "custom"
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 4 : 2
                                columnSpacing: 12
                                rowSpacing: 12
                                MetricCard { Layout.fillWidth: true; eyebrow: "SELECTED ACTIONS"; value: backend.careSummary.selectedCount.toString(); note: "Diagnostics and repairs currently in the plan." }
                                MetricCard { Layout.fillWidth: true; eyebrow: "READ-ONLY CHECKS"; value: backend.careSummary.diagnosticCount.toString(); note: "These inspect Windows without changing settings."; tone: "good" }
                                MetricCard { Layout.fillWidth: true; eyebrow: "REPAIRS"; value: backend.careSummary.repairCount.toString(); note: backend.careSummary.hasRepairs ? "A separate confirmation is required." : "No repair action is selected."; tone: backend.careSummary.hasRepairs ? "warn" : "good" }
                                MetricCard { Layout.fillWidth: true; eyebrow: "LONG CHECKS"; value: backend.careSummary.longCount.toString(); note: "Long integrity or storage checks may take noticeably longer."; tone: backend.careSummary.longCount > 0 ? "warn" : "neutral" }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 96
                                radius: 14
                                color: "#F0F7FF"
                                border.width: 1
                                border.color: "#CFE1FA"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 14
                                    Text { text: "✓"; color: root.accent; font.pixelSize: 24; font.weight: Font.Bold }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: "Built-in safety boundaries"; color: root.textStrong; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Text { text: "No user-folder cleanup, no security-policy bypass, no boot or encryption changes, no manual Windows Installer cache deletion, and no aggressive registry cleaners."; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                SectionHeading {
                                    title: "Checks and repair actions"
                                    description: "Every item states what it does, expected duration and risk before you select it."
                                    Layout.fillWidth: true
                                }
                                Switch {
                                    id: showRepairs
                                    text: "Show repair actions"
                                    checked: false
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.appData.careActions || []
                                    delegate: Surface {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        visible: modelData.mode === "diagnostic" || showRepairs.checked
                                        implicitHeight: visible ? 92 : 0
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 5
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                CheckBox {
                                                    checked: {
                                                        var version = backend.careSelectionVersion
                                                        return backend.isCareSelected(modelData.id)
                                                    }
                                                    onToggled: {
                                                        root.selectedCarePreset = "custom"
                                                        backend.setCareSelected(modelData.id, checked)
                                                    }
                                                }
                                                Text { text: modelData.name; color: root.textStrong; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                Badge { label: modelData.mode === "repair" ? "Repair" : "Check"; tone: modelData.mode === "repair" ? "warn" : "good" }
                                                Badge { label: modelData.duration; tone: modelData.duration === "long" ? "warn" : "neutral" }
                                                Badge { label: "Risk: " + modelData.risk; tone: modelData.risk === "moderate" ? "warn" : "neutral" }
                                            }
                                            Text { text: modelData.description; color: root.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.leftMargin: 38 }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: backend.careSummary.hasRepairs ? "Review and run" : "Run diagnostics"
                                    highlighted: true
                                    enabled: !backend.busy && backend.careSummary.selectedCount > 0
                                    onClicked: root.runCareWithConfirmation()
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: deviceContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: deviceContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                SectionHeading {
                                    title: "Read-only device intelligence"
                                    description: "Refresh to collect the latest hardware, Windows, storage, network, policy and problem evidence."
                                    Layout.fillWidth: true
                                }
                                Button {
                                    text: backend.busy ? "Working…" : "Refresh full inventory"
                                    highlighted: true
                                    enabled: !backend.busy
                                    onClicked: backend.collectDeviceInventory()
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 4 : 2
                                columnSpacing: 12
                                rowSpacing: 12
                                MetricCard { Layout.fillWidth: true; eyebrow: "OPERATING SYSTEM"; value: root.shortValue(backend.preflight.WindowsName, "Unknown"); note: "Build " + root.shortValue(backend.preflight.WindowsBuild, "—"); tone: backend.preflight.IsWindows ? "good" : "danger" }
                                MetricCard { Layout.fillWidth: true; eyebrow: "ARCHITECTURE"; value: backend.preflight.Is64Bit ? "64-bit" : "Unsupported"; note: "The managed suite targets Windows x64."; tone: backend.preflight.Is64Bit ? "good" : "danger" }
                                MetricCard { Layout.fillWidth: true; eyebrow: "TEMP SPACE"; value: backend.preflight.TempFreeGb > 0 ? backend.preflight.TempFreeGb.toFixed(1) + " GB" : "Unknown"; note: "Installers often unpack here before writing final files."; tone: backend.preflight.TempFreeGb >= 4 ? "good" : "warn" }
                                MetricCard { Layout.fillWidth: true; eyebrow: "LONG PATHS"; value: backend.preflight.LongPathsEnabled ? "Enabled" : "Needs setup"; note: "Useful for deep Python and web dependency trees."; tone: backend.preflight.LongPathsEnabled ? "good" : "warn" }
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: 56
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4
                                    Repeater {
                                        model: [
                                            {"id":"overview","name":"Overview"},
                                            {"id":"network","name":"Network & IP"},
                                            {"id":"storage","name":"Storage"},
                                            {"id":"security","name":"Security & Policy"},
                                            {"id":"problems","name":"Problems & Events"},
                                            {"id":"updates","name":"Updates & Services"}
                                        ]
                                        delegate: SegmentedButton {
                                            required property var modelData
                                            text: modelData.name
                                            selected: root.deviceSection === modelData.id
                                            onClicked: root.deviceSection = modelData.id
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: 470
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 18
                                    spacing: 10
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Structured evidence"; color: root.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Badge { label: backend.deviceData && Object.keys(backend.deviceData).length > 0 ? "Loaded" : "Waiting for scan"; tone: backend.deviceData && Object.keys(backend.deviceData).length > 0 ? "good" : "neutral" }
                                    }
                                    Text {
                                        text: "This view stays read-only. It exposes the same structured inventory that is saved under the managed state folder for diagnostics and evidence."
                                        color: root.textMuted
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        TextArea {
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.NoWrap
                                            text: {
                                                var snapshot = backend.deviceData
                                                return backend.deviceSectionJson(root.deviceSection)
                                            }
                                            font.family: "Consolas"
                                            font.pixelSize: 11
                                            color: root.textStrong
                                            background: Rectangle { color: "#FAFBFD"; radius: 10; border.width: 1; border.color: root.border }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: skillsContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: skillsContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                SectionHeading {
                                    title: "One canonical local skill library"
                                    description: "Validate and reuse the same skill package across supported AI development tools instead of maintaining separate copies by hand."
                                    Layout.fillWidth: true
                                }
                                Button { text: "Refresh"; onClicked: backend.refreshSkills() }
                                Button { text: "Advanced operations"; highlighted: true; onClicked: backend.openSkillsEngine() }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 3 : 1
                                columnSpacing: 12
                                rowSpacing: 12
                                MetricCard { Layout.fillWidth: true; eyebrow: "MANAGED SKILLS"; value: (backend.appData.skills ? backend.appData.skills.length : 0).toString(); note: "Built-in and managed local skill packages." }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "READY TO USE"
                                    value: {
                                        var count = 0
                                        var list = backend.appData.skills || []
                                        for (var i = 0; i < list.length; ++i) if (list[i].status === "Ready") count++
                                        return count.toString()
                                    }
                                    note: "Skills with valid names and descriptions."
                                    tone: "good"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    eyebrow: "AI TARGETS DETECTED"
                                    value: {
                                        var count = 0
                                        var list = backend.appData.skillTargets || []
                                        for (var i = 0; i < list.length; ++i) if (list[i].installed) count++
                                        return count + " / " + list.length
                                    }
                                    note: "Detected locally; no marketplace access is required."
                                }
                            }

                            SectionHeading {
                                title: "AI tool detection"
                                description: "Detection tells you where skills can be published. Missing tools remain visible so the result is understandable."
                                Layout.fillWidth: true
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: backend.appData.skillTargets || []
                                    delegate: Surface {
                                        required property var modelData
                                        width: 230
                                        height: 104
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 6
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: modelData.name; color: root.textStrong; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Badge { label: modelData.installed ? "Detected" : "Not detected"; tone: modelData.installed ? "good" : "neutral" }
                                            }
                                            Text { text: modelData.installed ? "Ready for local skill deployment." : "Install the pre-bundled tool profile first if you need this target."; color: root.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                SectionHeading {
                                    title: "Skill library"
                                    description: "Search the local catalog by skill name or purpose. Advanced validation, deployment and Project Brain operations continue through the existing engine during this first UI migration."
                                    Layout.fillWidth: true
                                }
                                TextField {
                                    id: skillSearch
                                    Layout.preferredWidth: 300
                                    placeholderText: "Search skills…"
                                    selectByMouse: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.appData.skills || []
                                    delegate: Surface {
                                        required property var modelData
                                        readonly property bool matchesSearch: skillSearch.text.length === 0 || modelData.name.toLowerCase().indexOf(skillSearch.text.toLowerCase()) >= 0 || modelData.description.toLowerCase().indexOf(skillSearch.text.toLowerCase()) >= 0
                                        Layout.fillWidth: true
                                        visible: matchesSearch
                                        implicitHeight: visible ? 92 : 0
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 15
                                            spacing: 14
                                            Rectangle {
                                                width: 42
                                                height: 42
                                                radius: 12
                                                color: root.accentSoft
                                                Text { anchors.centerIn: parent; text: "✦"; color: root.accent; font.pixelSize: 18 }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text { text: modelData.name; color: root.textStrong; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                                Text { text: modelData.description; color: root.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
                                            }
                                            Badge { label: modelData.source; tone: "neutral" }
                                            Badge { label: modelData.status; tone: modelData.status === "Ready" ? "good" : "danger" }
                                            Button { text: "Open folder"; onClicked: backend.openPath(modelData.path) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: logsContent.implicitHeight + 64
                        clip: true
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: logsContent
                            x: 30
                            y: 28
                            width: parent.width - 60
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                SectionHeading {
                                    title: "Durable evidence, not mystery failures"
                                    description: "Setup plans, runtime logs and state files stay visible so a failed operation can be diagnosed instead of simply repeated."
                                    Layout.fillWidth: true
                                }
                                Button { text: "Refresh files"; onClicked: backend.refreshLogs() }
                            }

                            Surface {
                                Layout.fillWidth: true
                                implicitHeight: 72
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12
                                    TextField { id: logSearch; Layout.fillWidth: true; placeholderText: "Search by file name or path…"; selectByMouse: true }
                                    ComboBox { id: logKind; model: ["All evidence", "Runtime", "State", "Plan"]; Layout.preferredWidth: 170 }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.logs
                                    delegate: Surface {
                                        required property var modelData
                                        readonly property bool matchesText: logSearch.text.length === 0 || modelData.name.toLowerCase().indexOf(logSearch.text.toLowerCase()) >= 0 || modelData.path.toLowerCase().indexOf(logSearch.text.toLowerCase()) >= 0
                                        readonly property bool matchesKind: logKind.currentText === "All evidence" || modelData.kind === logKind.currentText
                                        Layout.fillWidth: true
                                        visible: matchesText && matchesKind
                                        implicitHeight: visible ? 78 : 0
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12
                                            Rectangle { width: 36; height: 36; radius: 10; color: root.surfaceSoft; Text { anchors.centerIn: parent; text: "≡"; color: root.textMuted; font.pixelSize: 16 } }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { text: modelData.name; color: root.textStrong; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                                Text { text: modelData.path; color: root.textMuted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                            }
                                            Badge { label: modelData.kind; tone: "neutral" }
                                            Text { text: modelData.sizeKb + " KB"; color: root.textMuted; font.pixelSize: 11 }
                                            Text { text: modelData.modified; color: root.textMuted; font.pixelSize: 11 }
                                            Button { text: "Open"; onClicked: backend.openPath(modelData.path) }
                                        }
                                    }
                                }
                            }

                            Surface {
                                Layout.fillWidth: true
                                visible: backend.logs.length === 0
                                implicitHeight: visible ? 130 : 0
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: "No evidence files yet"; color: root.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: "Plans, setup logs and diagnostic state will appear here after you run operations."; color: root.textMuted; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: backend.busy ? 74 : 0
                visible: backend.busy
                color: "#FFFFFF"
                border.width: 0
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: root.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 30
                    anchors.rightMargin: 30
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Text { text: root.taskMessage; color: root.textStrong; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        ProgressBar { from: 0; to: 100; value: root.taskProgress; Layout.fillWidth: true }
                    }
                    Text { text: Math.round(root.taskProgress) + "%"; color: root.textMuted; font.pixelSize: 12; font.weight: Font.DemiBold }
                }
            }
        }
    }

    Rectangle {
        id: toast
        width: 390
        height: 88
        radius: 14
        color: root.surface
        border.width: 1
        border.color: root.border
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: backend.busy ? 98 : 24
        visible: toastTimer.running
        z: 100
        layer.enabled: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 4
            Text { text: root.toastTitle; color: root.textStrong; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: root.toastMessage; color: root.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }
}
