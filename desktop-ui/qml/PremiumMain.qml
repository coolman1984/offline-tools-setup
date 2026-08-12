import QtQuick
import QtQuick.Controls
import QtQuick.Controls.FluentWinUI3
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 1520
    height: 940
    minimumWidth: 1160
    minimumHeight: 760
    title: "Offline Automation & Development Suite"
    color: theme.canvas

    UiTokens { id: theme }

    palette.window: theme.canvas
    palette.windowText: theme.textStrong
    palette.base: theme.surface
    palette.alternateBase: theme.surfaceSoft
    palette.text: theme.textStrong
    palette.button: theme.surface
    palette.buttonText: theme.textStrong
    palette.highlight: theme.accent
    palette.highlightedText: "#FFFFFF"
    palette.mid: theme.border

    property int currentPage: 0
    property string selectedCarePreset: "quick-health"
    property string deviceSection: "overview"
    property real taskProgress: 0
    property string taskMessage: "Ready"
    property string toastTitle: ""
    property string toastMessage: ""
    property bool toastGood: true

    readonly property var navigation: [
        { "label": "Home", "glyph": "⌂", "hint": "Command center" },
        { "label": "Setup", "glyph": "+", "hint": "Build this PC" },
        { "label": "Safe Repair", "glyph": "◇", "hint": "Windows health" },
        { "label": "Device Details", "glyph": "▣", "hint": "Read-only evidence" },
        { "label": "Skills Hub", "glyph": "✦", "hint": "AI capability library" },
        { "label": "Logs & Evidence", "glyph": "≡", "hint": "Plans and receipts" }
    ]

    function pageTitle(index) {
        return ["Command Center", "Professional Setup", "Windows Safe Care", "Device Intelligence", "Skills Hub", "Logs & Evidence"][index]
    }

    function pageSubtitle(index) {
        return [
            "Workstation readiness, trusted actions and the next best step.",
            "Choose the outcome, review the footprint, then install from the verified local bundle.",
            "Inspect first. Apply only the maintenance actions you explicitly choose.",
            "A read-only view of hardware, Windows, network, storage and policy state.",
            "Manage one canonical local skill library across supported AI development tools.",
            "Inspect durable plans, runtime logs, state files and operation evidence."
        ][index]
    }

    function shortValue(value, fallback) {
        return value === undefined || value === null || value === "" ? fallback : value
    }

    function runCareWithConfirmation() {
        if (backend.careSummary.hasRepairs)
            repairDialog.open()
        else
            backend.runCare()
    }

    function showToast(title, message, good) {
        root.toastTitle = title
        root.toastMessage = message
        root.toastGood = good
        toastTimer.restart()
    }

    component Divider: Rectangle {
        implicitHeight: 1
        color: theme.border
    }

    component StepChip: Rectangle {
        id: step
        property string number: "1"
        property string label: "Choose"
        property bool active: false
        implicitWidth: row.implicitWidth + 20
        implicitHeight: 34
        radius: 17
        color: active ? theme.accentSoft : theme.surfaceSoft
        border.width: 1
        border.color: active ? theme.toneBorder("accent") : theme.border
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 7
            Rectangle {
                width: 20
                height: 20
                radius: 10
                color: step.active ? theme.accent : theme.borderStrong
                Text { anchors.centerIn: parent; text: step.number; color: "#FFFFFF"; font.pixelSize: 10; font.weight: Font.Bold }
            }
            Text { text: step.label; color: step.active ? theme.accent : theme.textMuted; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
    }

    component QuickAction: SurfaceCard {
        id: action
        required property var theme
        property string glyph: "→"
        property string title: "Action"
        property string description: ""
        signal activated()
        interactive: true
        implicitHeight: 142
        TapHandler { onTapped: action.activated() }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 17
            spacing: 7
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 38
                    height: 38
                    radius: 11
                    color: action.theme.accentSoft
                    Text { anchors.centerIn: parent; text: action.glyph; color: action.theme.accent; font.pixelSize: 16; font.weight: Font.DemiBold }
                }
                Item { Layout.fillWidth: true }
                Text { text: "›"; color: action.theme.textFaint; font.pixelSize: 22 }
            }
            Text { text: action.title; color: action.theme.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: action.description; color: action.theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }

    Dialog {
        id: repairDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 540
        title: "Confirm selected repairs"
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: backend.runCare()
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "You selected " + backend.careSummary.repairCount + " repair action(s). Diagnostics are read-only, but repairs change Windows maintenance state. A restore point is attempted first where policy allows it."
                color: theme.text
                font.pixelSize: 13
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 74
                radius: 12
                color: theme.warningSoft
                border.width: 1
                border.color: theme.toneBorder("warn")
                Text {
                    anchors.fill: parent
                    anchors.margins: 13
                    wrapMode: Text.WordWrap
                    text: "Safety boundaries stay enforced: no security-control bypass, no boot or encryption changes, no user-folder deletion, and no aggressive registry cleaning."
                    color: theme.warning
                    font.pixelSize: 11
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
            root.showToast(success ? "Completed" : "Action needs attention", message, success)
        }
        function onToastRequested(title, message) {
            root.showToast(title, message, true)
        }
    }

    Timer { id: toastTimer; interval: 4300; repeat: false }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            color: "#FAFCFF"

            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: theme.border }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    spacing: 11
                    Rectangle {
                        width: 42
                        height: 42
                        radius: 13
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#2368F4" }
                            GradientStop { position: 1.0; color: "#1148C9" }
                        }
                        Text { anchors.centerIn: parent; text: "O"; color: "#FFFFFF"; font.pixelSize: 19; font.weight: Font.Bold }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: "Offline Tools"; color: theme.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { text: "Workstation Suite"; color: theme.textMuted; font.pixelSize: 10 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    Text { text: "WORKSPACE"; color: theme.textFaint; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.0; Layout.fillWidth: true }
                    StatusPill { theme: theme; label: "LOCAL"; tone: "good"; dotVisible: false }
                }

                Repeater {
                    model: root.navigation
                    delegate: NavItem {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        theme: theme
                        selected: root.currentPage === index
                        text: modelData.label
                        glyph: modelData.glyph
                        hint: modelData.hint
                        onClicked: root.currentPage = index
                    }
                }

                Item { Layout.fillHeight: true }

                SurfaceCard {
                    theme: theme
                    Layout.fillWidth: true
                    implicitHeight: 112
                    baseColor: theme.surfaceSoft
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 9
                                height: 9
                                radius: 5
                                color: backend.preflight.ScanRunning ? theme.warning : theme.success
                                SequentialAnimation on opacity {
                                    running: backend.preflight.ScanRunning
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 650 }
                                    NumberAnimation { to: 1.0; duration: 650 }
                                }
                            }
                            Text {
                                text: backend.preflight.ScanRunning ? "Scanning workstation" : "Offline control ready"
                                color: theme.textStrong
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: backend.preflight.BundleManifestPresent ? "Verified bundle manifest detected." : "Developer checkout or bundle manifest not yet detected."
                            color: theme.textMuted
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text { text: shortValue(backend.preflight.ScannedAt, "Not scanned yet"); color: theme.textFaint; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
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
                Layout.preferredHeight: 88
                color: theme.surface
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 28
                    anchors.rightMargin: 28
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: root.pageTitle(root.currentPage); color: theme.textStrong; font.pixelSize: 22; font.weight: Font.DemiBold }
                        Text { text: root.pageSubtitle(root.currentPage); color: theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    StatusPill {
                        theme: theme
                        label: backend.preflight.ScanRunning ? "Scanning" : (backend.preflight.IsAdministrator ? "Administrator" : "Standard session")
                        tone: backend.preflight.ScanRunning ? "warn" : (backend.preflight.IsAdministrator ? "good" : "warn")
                    }
                    PremiumButton {
                        theme: theme
                        text: "Refresh scan"
                        glyph: "↻"
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
                        contentHeight: homeContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: homeContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 202
                                cardRadius: theme.radiusXL
                                clip: true
                                Rectangle {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#FFFFFF" }
                                        GradientStop { position: 0.58; color: "#F7FAFF" }
                                        GradientStop { position: 1.0; color: "#EBF2FF" }
                                    }
                                }
                                Rectangle {
                                    width: 280
                                    height: 280
                                    radius: 140
                                    color: "#DCE8FF"
                                    opacity: 0.5
                                    anchors.right: parent.right
                                    anchors.rightMargin: -96
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 24
                                    spacing: 24
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        StatusPill { theme: theme; label: "WORKSTATION COMMAND CENTER"; tone: "accent"; dotVisible: false }
                                        Text {
                                            text: backend.preflight.ScanRunning ? "Reading this PC before touching anything." : "Build a dependable offline workstation with confidence."
                                            color: theme.textStrong
                                            font.pixelSize: 27
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                            maximumLineCount: 2
                                        }
                                        Text {
                                            text: "The suite scans first, keeps every change explainable, and uses the verified local bundle as the source of truth."
                                            color: theme.textMuted
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                            maximumLineCount: 2
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.preferredWidth: 220
                                        spacing: 9
                                        PremiumButton { theme: theme; text: "Configure workstation"; glyph: "+"; tone: "primary"; Layout.fillWidth: true; onClicked: root.currentPage = 1 }
                                        PremiumButton { theme: theme; text: "Run full inventory"; glyph: "▣"; Layout.fillWidth: true; enabled: !backend.busy; onClicked: backend.collectDeviceInventory() }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 940 ? 4 : 2
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "W"; eyebrow: "WINDOWS"; value: shortValue(backend.preflight.WindowsName, "Scanning…"); note: "Build " + shortValue(backend.preflight.WindowsBuild, "—"); tone: backend.preflight.IsWindows && backend.preflight.Is64Bit ? "good" : "danger" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "C:"; eyebrow: "SYSTEM DRIVE"; value: backend.preflight.FreeDiskGb > 0 ? backend.preflight.FreeDiskGb.toFixed(1) + " GB free" : "Scanning…"; note: backend.preflight.FreeDiskGb >= 12 ? "Healthy capacity for a professional setup." : "Large profiles may need more free space."; tone: backend.preflight.FreeDiskGb >= 12 ? "good" : "warn" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "↻"; eyebrow: "RESTART STATE"; value: backend.preflight.PendingReboot ? "Restart pending" : "Clear"; note: backend.preflight.PendingReboot ? "Restart before a large install when practical." : "No restart marker detected."; tone: backend.preflight.PendingReboot ? "warn" : "good" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "O"; eyebrow: "OFFICE DESKTOP"; value: backend.preflight.OfficeInstalled ? "Detected" : "Not detected"; note: backend.preflight.OfficeInstalled ? shortValue(backend.preflight.OfficeArchitecture, "Architecture available after scan") : "File automation still works; app control requires Office."; tone: backend.preflight.OfficeInstalled ? "good" : "neutral" }
                            }

                            SectionTitle { theme: theme; eyebrow: "NEXT ACTION"; title: "Choose what you need to accomplish"; description: "Each area is isolated so installation, diagnostics and evidence stay easy to understand."; Layout.fillWidth: true; Layout.topMargin: 4 }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 3 : 1
                                columnSpacing: 10
                                rowSpacing: 10
                                QuickAction { theme: theme; Layout.fillWidth: true; glyph: "+"; title: "Build this workstation"; description: "Choose a preset or tune Office, PDF, data, web, AI and quality capabilities."; onActivated: root.currentPage = 1 }
                                QuickAction { theme: theme; Layout.fillWidth: true; glyph: "◇"; title: "Check Windows safely"; description: "Start with read-only diagnostics and reveal repair actions only when needed."; onActivated: root.currentPage = 2 }
                                QuickAction { theme: theme; Layout.fillWidth: true; glyph: "✦"; title: "Manage AI skills"; description: "Inspect the canonical local skills library and supported local targets."; onActivated: root.currentPage = 4 }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: setupContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: setupContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; eyebrow: "GUIDED SETUP"; title: "Choose the outcome first"; description: "Presets are safe starting points. Custom mode exposes every selectable capability without changing the locked core."; Layout.fillWidth: true }
                                RowLayout { spacing: 6; StepChip { number: "1"; label: "Choose"; active: true } StepChip { number: "2"; label: "Review" } StepChip { number: "3"; label: "Install" } }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: presetFlow.implicitHeight + 32
                                Flow {
                                    id: presetFlow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 9
                                    Repeater {
                                        model: backend.appData.presets || []
                                        delegate: RadioButton {
                                            required property var modelData
                                            text: modelData.displayName
                                            checked: backend.activePreset === modelData.id
                                            onClicked: backend.applyPreset(modelData.id)
                                        }
                                    }
                                    RadioButton { text: "Custom Selection"; checked: backend.activePreset === "custom"; onClicked: backend.useCustomSelection() }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 940 ? 4 : 2
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "P"; eyebrow: "SELECTED PROFILES"; value: backend.selectionSummary.profileCount.toString(); note: "Capability groups beyond the locked foundation." }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "#"; eyebrow: "COMPONENTS"; value: backend.selectionSummary.componentCount.toString(); note: "Individual optional capabilities in this plan." }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "GB"; eyebrow: "ESTIMATED FOOTPRINT"; value: "~" + backend.selectionSummary.estimatedGb.toFixed(1) + " GB"; note: "Safe target: about " + backend.selectionSummary.safeGb + " GB free." }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "C:"; eyebrow: "CURRENT FREE SPACE"; value: backend.preflight.FreeDiskGb > 0 ? backend.preflight.FreeDiskGb.toFixed(1) + " GB" : "Not scanned"; note: backend.selectionSummary.enoughSpace ? "Capacity is suitable for this plan." : "Reduce the plan or free disk space first."; tone: backend.preflight.FreeDiskGb <= 0 ? "neutral" : (backend.selectionSummary.enoughSpace ? "good" : "danger") }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: coreBody.implicitHeight + 32
                                baseColor: theme.infoSoft
                                ColumnLayout {
                                    id: coreBody
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 11
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Rectangle { width: 38; height: 38; radius: 11; color: "#FFFFFF"; border.width: 1; border.color: theme.border; Text { anchors.centerIn: parent; text: "✓"; color: theme.accent; font.pixelSize: 16; font.weight: Font.Bold } }
                                        ColumnLayout { Layout.fillWidth: true; spacing: 2; Text { text: backend.appData.core ? backend.appData.core.displayName : "Core Foundation"; color: theme.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold } Text { text: backend.appData.core ? backend.appData.core.description : "Always installed."; color: theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true } }
                                        StatusPill { theme: theme; label: "Always included"; tone: "good" }
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 7
                                        Repeater {
                                            model: backend.appData.core ? backend.appData.core.components : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                height: 28
                                                width: coreText.implicitWidth + 18
                                                radius: 9
                                                color: "#FFFFFF"
                                                border.width: 1
                                                border.color: theme.border
                                                Text { id: coreText; anchors.centerIn: parent; text: modelData.name; color: theme.textMuted; font.pixelSize: 10 }
                                            }
                                        }
                                    }
                                }
                            }

                            SectionTitle { theme: theme; eyebrow: "CAPABILITIES"; title: "Professional profiles"; description: "Select only what this PC needs. Unsupported items stay visible with a reason rather than failing later."; Layout.fillWidth: true }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: backend.appData.profiles || []
                                    delegate: SurfaceCard {
                                        id: profileCard
                                        required property var modelData
                                        readonly property string profileId: modelData.id
                                        theme: theme
                                        Layout.fillWidth: true
                                        selected: profileCheck.checked
                                        implicitHeight: profileBody.implicitHeight + 32
                                        ColumnLayout {
                                            id: profileBody
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 10
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 11
                                                CheckBox {
                                                    id: profileCheck
                                                    checked: { var v = backend.selectionVersion; return backend.isProfileSelected(modelData.id) }
                                                    onToggled: backend.setProfileSelected(modelData.id, checked)
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: modelData.displayName; color: theme.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                        StatusPill { visible: modelData.recommended === true; theme: theme; label: "Recommended"; tone: "good"; dotVisible: false }
                                                        StatusPill { theme: theme; label: "~" + (modelData.estimatedMb / 1024).toFixed(1) + " GB"; tone: "neutral"; dotVisible: false }
                                                    }
                                                    Text { text: modelData.description; color: theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: profileCheck.checked ? 3 : 2; elide: Text.ElideRight }
                                                }
                                            }
                                            Divider { Layout.fillWidth: true; visible: profileCheck.checked }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                visible: profileCheck.checked
                                                Repeater {
                                                    model: modelData.components || []
                                                    delegate: RowLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        spacing: 9
                                                        CheckBox {
                                                            checked: { var v = backend.selectionVersion; return backend.isComponentSelected(profileCard.profileId, modelData.id) }
                                                            enabled: modelData.supported !== false
                                                            onToggled: backend.setComponentSelected(profileCard.profileId, modelData.id, checked)
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2
                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                Text { text: modelData.name; color: modelData.supported === false ? theme.textFaint : theme.text; font.pixelSize: 12; font.weight: Font.Medium; Layout.fillWidth: true }
                                                                StatusPill { visible: modelData.nativeOptional === true; theme: theme; label: "Local media"; tone: "neutral"; dotVisible: false }
                                                                StatusPill { visible: modelData.heavy === true; theme: theme; label: "Large"; tone: "warn"; dotVisible: false }
                                                                StatusPill { visible: modelData.supported === false; theme: theme; label: "Unavailable"; tone: "danger"; dotVisible: false }
                                                            }
                                                            Text { text: modelData.supported === false ? modelData.reason : (modelData.description || backend.componentHint(modelData.id)); color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 116
                                baseColor: theme.surfaceRaised
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 14
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: "Review before changing the PC"; color: theme.textStrong; font.pixelSize: 15; font.weight: Font.DemiBold }
                                        Text { text: "The plan records selections, preflight state and the bundle source. Save it without installing, or start the verified local installation."; color: theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    PremiumButton { theme: theme; text: "Save plan"; enabled: !backend.busy; onClicked: backend.writeSetupPlan() }
                                    PremiumButton { theme: theme; text: "Install selected"; glyph: "→"; tone: "primary"; enabled: !backend.busy && backend.selectionSummary.profileCount > 0; onClicked: backend.startSetup() }
                                }
                            }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: careContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: careContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; eyebrow: "SAFE CARE"; title: "Diagnostics first, repairs second"; description: "Read-only presets stay separate from repairs. Repair actions appear only when you choose to reveal them."; Layout.fillWidth: true }
                                StatusPill { theme: theme; label: backend.careSummary.hasRepairs ? "Repairs selected" : "Read-only plan"; tone: backend.careSummary.hasRepairs ? "warn" : "good" }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: carePresetFlow.implicitHeight + 32
                                Flow {
                                    id: carePresetFlow
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 9
                                    Repeater {
                                        model: backend.appData.carePresets || []
                                        delegate: RadioButton {
                                            required property var modelData
                                            text: modelData.name
                                            checked: root.selectedCarePreset === modelData.id
                                            onClicked: { root.selectedCarePreset = modelData.id; backend.applyCarePreset(modelData.id) }
                                            ToolTip.visible: hovered
                                            ToolTip.text: modelData.description
                                        }
                                    }
                                    RadioButton { text: "Custom"; checked: root.selectedCarePreset === "custom" }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 940 ? 4 : 2
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "#"; eyebrow: "SELECTED ACTIONS"; value: backend.careSummary.selectedCount.toString(); note: "Diagnostics and repairs currently in the plan." }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "✓"; eyebrow: "READ-ONLY CHECKS"; value: backend.careSummary.diagnosticCount.toString(); note: "These inspect Windows without changing settings."; tone: "good" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "!"; eyebrow: "REPAIRS"; value: backend.careSummary.repairCount.toString(); note: backend.careSummary.hasRepairs ? "A separate confirmation is required." : "No repair action is selected."; tone: backend.careSummary.hasRepairs ? "warn" : "good" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "◷"; eyebrow: "LONG CHECKS"; value: backend.careSummary.longCount.toString(); note: "Deep integrity or storage checks can take longer."; tone: backend.careSummary.longCount > 0 ? "warn" : "neutral" }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 92
                                baseColor: theme.infoSoft
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 12
                                    Rectangle { width: 38; height: 38; radius: 11; color: "#FFFFFF"; border.width: 1; border.color: theme.border; Text { anchors.centerIn: parent; text: "✓"; color: theme.accent; font.pixelSize: 17; font.weight: Font.Bold } }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 2; Text { text: "Built-in safety boundaries"; color: theme.textStrong; font.pixelSize: 14; font.weight: Font.DemiBold } Text { text: "No user-folder cleanup, security-policy bypass, boot or encryption changes, installer-cache deletion, or aggressive registry cleaning."; color: theme.textMuted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; title: "Checks and repair actions"; description: "Each action explains what it does, expected duration and risk."; Layout.fillWidth: true }
                                Switch { id: showRepairs; text: "Show repair actions"; checked: false }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.appData.careActions || []
                                    delegate: SurfaceCard {
                                        required property var modelData
                                        theme: theme
                                        Layout.fillWidth: true
                                        visible: modelData.mode === "diagnostic" || showRepairs.checked
                                        implicitHeight: visible ? 92 : 0
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 10
                                            CheckBox {
                                                checked: { var v = backend.careSelectionVersion; return backend.isCareSelected(modelData.id) }
                                                onToggled: { root.selectedCarePreset = "custom"; backend.setCareSelected(modelData.id, checked) }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: modelData.name; color: theme.textStrong; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                    StatusPill { theme: theme; label: modelData.mode === "repair" ? "Repair" : "Check"; tone: modelData.mode === "repair" ? "warn" : "good"; dotVisible: false }
                                                    StatusPill { theme: theme; label: modelData.duration; tone: modelData.duration === "long" ? "warn" : "neutral"; dotVisible: false }
                                                    StatusPill { theme: theme; label: "Risk: " + modelData.risk; tone: modelData.risk === "moderate" ? "warn" : "neutral"; dotVisible: false }
                                                }
                                                Text { text: modelData.description; color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } PremiumButton { theme: theme; text: backend.careSummary.hasRepairs ? "Review and run" : "Run diagnostics"; glyph: "→"; tone: "primary"; enabled: !backend.busy && backend.careSummary.selectedCount > 0; onClicked: root.runCareWithConfirmation() } }
                        }
                    }
                }

                Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: deviceContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: deviceContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; eyebrow: "READ-ONLY"; title: "Device intelligence"; description: "Collect the latest hardware, Windows, storage, network, policy and problem evidence without changing the machine."; Layout.fillWidth: true }
                                PremiumButton { theme: theme; text: backend.busy ? "Working…" : "Refresh full inventory"; glyph: "↻"; tone: "primary"; enabled: !backend.busy; onClicked: backend.collectDeviceInventory() }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 940 ? 4 : 2
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "W"; eyebrow: "OPERATING SYSTEM"; value: shortValue(backend.preflight.WindowsName, "Unknown"); note: "Build " + shortValue(backend.preflight.WindowsBuild, "—"); tone: backend.preflight.IsWindows ? "good" : "danger" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "64"; eyebrow: "ARCHITECTURE"; value: backend.preflight.Is64Bit ? "64-bit" : "Unsupported"; note: "The managed suite targets Windows x64."; tone: backend.preflight.Is64Bit ? "good" : "danger" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "T"; eyebrow: "TEMP SPACE"; value: backend.preflight.TempFreeGb > 0 ? backend.preflight.TempFreeGb.toFixed(1) + " GB" : "Unknown"; note: "Installers often unpack here before final placement."; tone: backend.preflight.TempFreeGb >= 4 ? "good" : "warn" }
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "↔"; eyebrow: "LONG PATHS"; value: backend.preflight.LongPathsEnabled ? "Enabled" : "Needs setup"; note: "Useful for deep Python and web dependency trees."; tone: backend.preflight.LongPathsEnabled ? "good" : "warn" }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 56
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 4
                                    Repeater {
                                        model: [
                                            {"id":"overview","name":"Overview"}, {"id":"network","name":"Network & IP"}, {"id":"storage","name":"Storage"},
                                            {"id":"security","name":"Security & Policy"}, {"id":"problems","name":"Problems & Events"}, {"id":"updates","name":"Updates & Services"}
                                        ]
                                        delegate: Button {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            hoverEnabled: true
                                            onClicked: root.deviceSection = modelData.id
                                            background: Rectangle { radius: 9; color: root.deviceSection === modelData.id ? theme.surface : (parent.hovered ? theme.surfaceHover : "transparent"); border.width: root.deviceSection === modelData.id ? 1 : 0; border.color: theme.border }
                                            contentItem: Text { text: parent.text; color: root.deviceSection === modelData.id ? theme.textStrong : theme.textMuted; font.pixelSize: 10; font.weight: root.deviceSection === modelData.id ? Font.DemiBold : Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        }
                                    }
                                }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 480
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 9
                                    RowLayout { Layout.fillWidth: true; Text { text: "Structured evidence"; color: theme.textStrong; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true } StatusPill { theme: theme; label: backend.deviceData && Object.keys(backend.deviceData).length > 0 ? "Loaded" : "Waiting for scan"; tone: backend.deviceData && Object.keys(backend.deviceData).length > 0 ? "good" : "neutral" } }
                                    Text { text: "This view is deliberately read-only and mirrors the structured inventory saved to the managed state folder."; color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        TextArea {
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.NoWrap
                                            text: { var snapshot = backend.deviceData; return backend.deviceSectionJson(root.deviceSection) }
                                            font.family: "Consolas"
                                            font.pixelSize: 10
                                            color: theme.text
                                            background: Rectangle { color: "#FAFCFF"; radius: 11; border.width: 1; border.color: theme.border }
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
                        contentHeight: skillsContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: skillsContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; eyebrow: "LOCAL CAPABILITIES"; title: "One canonical skill library"; description: "Validate and reuse the same local skill packages across supported AI development tools."; Layout.fillWidth: true }
                                PremiumButton { theme: theme; text: "Refresh"; glyph: "↻"; onClicked: backend.refreshSkills() }
                                PremiumButton { theme: theme; text: "Advanced operations"; glyph: "→"; tone: "primary"; onClicked: backend.openSkillsEngine() }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 900 ? 3 : 1
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricTile { theme: theme; Layout.fillWidth: true; glyph: "✦"; eyebrow: "MANAGED SKILLS"; value: (backend.appData.skills ? backend.appData.skills.length : 0).toString(); note: "Built-in and managed local skill packages." }
                                MetricTile {
                                    theme: theme; Layout.fillWidth: true; glyph: "✓"; eyebrow: "READY TO USE"; tone: "good"
                                    value: { var count = 0; var list = backend.appData.skills || []; for (var i = 0; i < list.length; ++i) if (list[i].status === "Ready") count++; return count.toString() }
                                    note: "Skills with valid names and descriptions."
                                }
                                MetricTile {
                                    theme: theme; Layout.fillWidth: true; glyph: "AI"; eyebrow: "AI TARGETS DETECTED"
                                    value: { var count = 0; var list = backend.appData.skillTargets || []; for (var i = 0; i < list.length; ++i) if (list[i].installed) count++; return count + " / " + list.length }
                                    note: "Detected locally; no marketplace access is required."
                                }
                            }

                            SectionTitle { theme: theme; title: "AI tool detection"; description: "Missing targets remain visible so deployment readiness is obvious."; Layout.fillWidth: true }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 9
                                Repeater {
                                    model: backend.appData.skillTargets || []
                                    delegate: SurfaceCard {
                                        required property var modelData
                                        theme: theme
                                        width: 232
                                        height: 108
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 13
                                            spacing: 6
                                            RowLayout { Layout.fillWidth: true; Text { text: modelData.name; color: theme.textStrong; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight } StatusPill { theme: theme; label: modelData.installed ? "Detected" : "Missing"; tone: modelData.installed ? "good" : "neutral"; dotVisible: false } }
                                            Text { text: modelData.installed ? "Ready for local skill deployment." : "Install the pre-bundled tool profile first if this target is required."; color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; title: "Skill library"; description: "Search the local catalog by name or purpose."; Layout.fillWidth: true }
                                TextField { id: skillSearch; Layout.preferredWidth: 320; placeholderText: "Search skills…"; selectByMouse: true }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.appData.skills || []
                                    delegate: SurfaceCard {
                                        required property var modelData
                                        readonly property bool matchesSearch: skillSearch.text.length === 0 || modelData.name.toLowerCase().indexOf(skillSearch.text.toLowerCase()) >= 0 || modelData.description.toLowerCase().indexOf(skillSearch.text.toLowerCase()) >= 0
                                        theme: theme
                                        Layout.fillWidth: true
                                        visible: matchesSearch
                                        implicitHeight: visible ? 86 : 0
                                        interactive: true
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 13
                                            spacing: 12
                                            Rectangle { width: 40; height: 40; radius: 11; color: theme.accentSoft; Text { anchors.centerIn: parent; text: "✦"; color: theme.accent; font.pixelSize: 16 } }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 3; Text { text: modelData.name; color: theme.textStrong; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight } Text { text: modelData.description; color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight } }
                                            StatusPill { theme: theme; label: modelData.source; tone: "neutral"; dotVisible: false }
                                            StatusPill { theme: theme; label: modelData.status; tone: modelData.status === "Ready" ? "good" : "danger"; dotVisible: false }
                                            PremiumButton { theme: theme; text: "Open folder"; onClicked: backend.openPath(modelData.path) }
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
                        contentHeight: logsContent.implicitHeight + 58
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: logsContent
                            x: 28
                            y: 24
                            width: parent.width - 56
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                SectionTitle { theme: theme; eyebrow: "TRACEABILITY"; title: "Durable evidence, not mystery failures"; description: "Plans, runtime logs and state files stay visible so every operation can be diagnosed."; Layout.fillWidth: true }
                                PremiumButton { theme: theme; text: "Refresh files"; glyph: "↻"; onClicked: backend.refreshLogs() }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                implicitHeight: 70
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 13
                                    spacing: 10
                                    TextField { id: logSearch; Layout.fillWidth: true; placeholderText: "Search by file name or path…"; selectByMouse: true }
                                    ComboBox { id: logKind; model: ["All evidence", "Runtime", "State", "Plan"]; Layout.preferredWidth: 170 }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: backend.logs
                                    delegate: SurfaceCard {
                                        required property var modelData
                                        readonly property bool matchesText: logSearch.text.length === 0 || modelData.name.toLowerCase().indexOf(logSearch.text.toLowerCase()) >= 0 || modelData.path.toLowerCase().indexOf(logSearch.text.toLowerCase()) >= 0
                                        readonly property bool matchesKind: logKind.currentText === "All evidence" || modelData.kind === logKind.currentText
                                        theme: theme
                                        Layout.fillWidth: true
                                        visible: matchesText && matchesKind
                                        implicitHeight: visible ? 76 : 0
                                        interactive: true
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 13
                                            spacing: 11
                                            Rectangle { width: 36; height: 36; radius: 10; color: theme.surfaceSoft; Text { anchors.centerIn: parent; text: "≡"; color: theme.textMuted; font.pixelSize: 15 } }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 2; Text { text: modelData.name; color: theme.textStrong; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideMiddle } Text { text: modelData.path; color: theme.textMuted; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideMiddle } }
                                            StatusPill { theme: theme; label: modelData.kind; tone: "neutral"; dotVisible: false }
                                            Text { text: modelData.sizeKb + " KB"; color: theme.textMuted; font.pixelSize: 10 }
                                            Text { text: modelData.modified; color: theme.textMuted; font.pixelSize: 10 }
                                            PremiumButton { theme: theme; text: "Open"; onClicked: backend.openPath(modelData.path) }
                                        }
                                    }
                                }
                            }

                            SurfaceCard {
                                theme: theme
                                Layout.fillWidth: true
                                visible: backend.logs.length === 0
                                implicitHeight: visible ? 150 : 0
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Rectangle { Layout.alignment: Qt.AlignHCenter; width: 44; height: 44; radius: 13; color: theme.surfaceSoft; Text { anchors.centerIn: parent; text: "≡"; color: theme.textMuted; font.pixelSize: 18 } }
                                    Text { text: "No evidence files yet"; color: theme.textStrong; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: "Plans, setup logs and diagnostic state will appear here after you run operations."; color: theme.textMuted; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: backend.busy ? 70 : 0
                visible: backend.busy
                color: theme.surface
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 28
                    anchors.rightMargin: 28
                    spacing: 14
                    Rectangle { width: 34; height: 34; radius: 10; color: theme.accentSoft; Text { anchors.centerIn: parent; text: "↻"; color: theme.accent; font.pixelSize: 15; RotationAnimation on rotation { running: backend.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1200 } } }
                    ColumnLayout { Layout.fillWidth: true; spacing: 5; Text { text: root.taskMessage; color: theme.textStrong; font.pixelSize: 11; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight } ProgressBar { from: 0; to: 100; value: root.taskProgress; Layout.fillWidth: true } }
                    Text { text: Math.round(root.taskProgress) + "%"; color: theme.textMuted; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
            }
        }
    }

    SurfaceCard {
        id: toast
        theme: theme
        width: 410
        height: 92
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 22
        anchors.bottomMargin: backend.busy ? 90 : 22
        visible: toastTimer.running
        z: 100
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 4
            RowLayout { Layout.fillWidth: true; Rectangle { width: 9; height: 9; radius: 5; color: root.toastGood ? theme.success : theme.danger } Text { text: root.toastTitle; color: theme.textStrong; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight } }
            Text { text: root.toastMessage; color: theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }
}
