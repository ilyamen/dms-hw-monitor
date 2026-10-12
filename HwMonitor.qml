import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Hardware monitor: CPU / GPU / RAM / VRAM with graphs and every temperature in one block.
// CPU, RAM, network and disk come from DgopService (like the built-in DMS monitor),
// the GPU and temperatures from sysfs through sensors.sh.
DesktopPluginComponent {
    id: root

    minWidth: 420
    minHeight: 260

    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 80) / 100
    property int historyLength: 60

    readonly property color bgColor: Theme.withAlpha(Theme.surface, backgroundOpacity)
    readonly property color tileBg: Theme.withAlpha(Theme.surfaceContainerHigh, backgroundOpacity)

    // ---------- data ----------

    property var sensors: ({})
    property var gpuHistory: []
    property var vramHistory: []

    readonly property real gpuBusy: sensors.gpu_busy ?? 0
    readonly property real vramUsed: sensors.vram_used ?? 0
    readonly property real vramTotal: sensors.vram_total ?? 0

    readonly property var modules: ["cpu", "memory", "network", "disk"]
    Component.onCompleted: DgopService.addRef(modules)
    Component.onDestruction: DgopService.removeRef(modules)

    // GPU model from dgop: "Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M" -> "Radeon RX 7900"
    property string gpuName: ""
    Process {
        running: true
        command: ["dgop", "gpu", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const gpus = JSON.parse(text).gpus ?? [];
                    const gpu = gpus.find(g => g.driver === "amdgpu") ?? gpus[0];
                    root.gpuName = root.shortGpuName(gpu?.displayName ?? "");
                } catch (e) {
                    root.gpuName = "";
                }
            }
        }
    }

    function shortGpuName(name) {
        const variants = name.split("/");
        if (variants.length < 2)
            return name;
        const words = variants[0].split(" ");
        const common = words.indexOf(variants[1].trim().split(" ")[0]);
        return common > 0 ? words.slice(0, common + 1).join(" ") : variants[0];
    }

    Process {
        id: sensorsProc
        command: ["sh", Qt.resolvedUrl("sensors.sh").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0)
                        s[line.slice(0, i)] = Number(line.slice(i + 1));
                }
                root.sensors = s;
                root.gpuHistory = root.gpuHistory.concat([s.gpu_busy ?? 0]).slice(-root.historyLength);
                const vram = s.vram_total ? s.vram_used / s.vram_total * 100 : 0;
                root.vramHistory = root.vramHistory.concat([vram]).slice(-root.historyLength);
            }
        }
    }

    Timer {
        interval: (pluginData.updateSeconds ?? 2) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sensorsProc.running = true
    }

    // ---------- formatting ----------

    function gb(bytes) { return (bytes / 1073741824).toFixed(1); }

    function rate(bytesPerSec) {
        const b = bytesPerSec || 0;
        if (b >= 1048576)
            return I18n.trFor("hwMonitor", "%1 MB/s").arg((b / 1048576).toFixed(1));
        if (b >= 1024)
            return I18n.trFor("hwMonitor", "%1 KB/s").arg(Math.round(b / 1024));
        return I18n.trFor("hwMonitor", "%1 B/s").arg(Math.round(b));
    }

    function tempColor(t, warn, hot) {
        if (t >= hot)
            return Theme.error;
        if (t >= warn)
            return Theme.warning ?? "#ffb74d";
        return Theme.surfaceText;
    }

    // ---------- components ----------

    // Tile: title, large value, caption, graph
    component Tile: Rectangle {
        id: tile
        property string icon
        property string title
        property string value
        property string sub
        property var history: []
        property real maxValue: 100
        property real fill: -1   // 0..1: fill bar (for memory)

        radius: Theme.cornerRadius / 1.5
        color: root.tileBg

        // graph
        Canvas {
            id: graph
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.45
            property var points: tile.history
            onPointsChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const pts = points || [];
                if (pts.length < 2)
                    return;
                const n = root.historyLength;
                const step = width / (n - 1);
                const x0 = width - (pts.length - 1) * step;
                const y = v => height - Math.min(1, v / tile.maxValue) * (height - 2) - 1;
                ctx.beginPath();
                ctx.moveTo(x0, height);
                for (let i = 0; i < pts.length; i++)
                    ctx.lineTo(x0 + i * step, y(pts[i]));
                ctx.lineTo(width, height);
                ctx.closePath();
                ctx.fillStyle = Theme.withAlpha(Theme.primary, 0.18).toString();
                ctx.fill();
                ctx.beginPath();
                for (let i = 0; i < pts.length; i++)
                    i === 0 ? ctx.moveTo(x0, y(pts[0])) : ctx.lineTo(x0 + i * step, y(pts[i]));
                ctx.strokeStyle = Theme.primary.toString();
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
            Connections {
                target: Theme
                function onPrimaryChanged() { graph.requestPaint(); }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: 2

            RowLayout {
                spacing: Theme.spacingXS
                DankIcon { name: tile.icon; size: Theme.fontSizeMedium + 2; color: Theme.primary }
                StyledText { text: tile.title; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceTextSecondary }
            }
            StyledText {
                text: tile.value
                font.pixelSize: Theme.fontSizeXLarge + 6
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            StyledText {
                visible: tile.sub !== ""
                text: tile.sub
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextSecondary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Rectangle {
                visible: tile.fill >= 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 4
                radius: 2
                color: Theme.withAlpha(Theme.surfaceText, 0.12)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, tile.fill))
                    height: parent.height
                    radius: 2
                    color: Theme.primary
                }
            }
        }
    }

    // Temperature: value over label. The row gives every one the same width.
    component TempItem: Column {
        property string label
        property real temp: 0
        property real warn: 70
        property real hot: 85
        visible: temp > 0
        spacing: 0
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(parent.temp) + "°"
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Font.Medium
            color: root.tempColor(parent.temp, parent.warn, parent.hot)
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceTextSecondary
        }
    }

    // ---------- view ----------

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.bgColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS
                DankIcon { name: "monitoring"; size: Theme.iconSize; color: Theme.primary }
                StyledText { text: I18n.trFor("hwMonitor", "System"); font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium; color: Theme.surfaceText }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: "↓ " + root.rate(DgopService.networkRxRate) + "   ↑ " + root.rate(DgopService.networkTxRate)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextSecondary
                }
            }

            // Load
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                columnSpacing: Theme.spacingS
                rowSpacing: Theme.spacingS

                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "memory"; title: I18n.trFor("hwMonitor", "CPU")
                    value: Math.round(DgopService.cpuUsage) + "%"
                    sub: DgopService.cpuFrequency > 0 ? I18n.trFor("hwMonitor", "%1 GHz").arg((DgopService.cpuFrequency / 1000).toFixed(1)) : ""
                    history: DgopService.cpuHistory
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "developer_board"; title: I18n.trFor("hwMonitor", "GPU")
                    value: Math.round(root.gpuBusy) + "%"
                    sub: root.gpuName
                    history: root.gpuHistory
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "memory_alt"; title: I18n.trFor("hwMonitor", "Memory")
                    value: Math.round(DgopService.memoryUsage) + "%"
                    sub: I18n.trFor("hwMonitor", "%1 / %2 GB").arg(root.gb(DgopService.usedMemoryKB * 1024)).arg(root.gb(DgopService.totalMemoryKB * 1024))
                    history: DgopService.memoryHistory
                    fill: DgopService.memoryUsage / 100
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "view_in_ar"; title: I18n.trFor("hwMonitor", "VRAM")
                    value: root.vramTotal > 0 ? Math.round(root.vramUsed / root.vramTotal * 100) + "%" : "—"
                    sub: I18n.trFor("hwMonitor", "%1 / %2 GB").arg(root.gb(root.vramUsed)).arg(root.gb(root.vramTotal))
                    fill: root.vramTotal > 0 ? root.vramUsed / root.vramTotal : 0
                    history: root.vramHistory
                }
            }

            // Two blocks on the tile grid: temperatures under the first three tiles, disk under VRAM
            Item {
                id: bottomRow
                readonly property real spacing: Theme.spacingS
                // Same columns as the tile grid above
                readonly property real column: (width - spacing * 3) / 4
                Layout.fillWidth: true
                Layout.preferredHeight: tempRow.implicitHeight + Theme.spacingM * 2

                Rectangle {
                    width: bottomRow.column * 3 + bottomRow.spacing * 2
                    height: parent.height
                    radius: Theme.cornerRadius / 1.5
                    color: root.tileBg

                    RowLayout {
                        id: tempRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon { name: "thermostat"; size: Theme.iconSize; color: Theme.primary }
                        // Equal cells, so a long label ("GPU hotspot") does not push the others aside
                        Row {
                            id: temps
                            readonly property int count: {
                                let n = 0;
                                for (let i = 0; i < children.length; i++)
                                    if (children[i].visible)
                                        n++;
                                return n;
                            }
                            readonly property real cellWidth: count > 0 ? width / count : 0
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter

                            TempItem { width: temps.cellWidth; label: "CPU"; temp: (root.sensors.cpu_temp ?? 0) / 1000; warn: 75; hot: 90 }
                            TempItem { width: temps.cellWidth; label: "GPU"; temp: (root.sensors.gpu_edge ?? 0) / 1000; warn: 75; hot: 90 }
                            TempItem { width: temps.cellWidth; label: I18n.trFor("hwMonitor", "GPU hotspot"); temp: (root.sensors.gpu_junction ?? 0) / 1000; warn: 90; hot: 105 }
                            TempItem { width: temps.cellWidth; label: "VRAM"; temp: (root.sensors.gpu_mem ?? 0) / 1000; warn: 85; hot: 100 }
                            TempItem { width: temps.cellWidth; label: "SSD"; temp: (root.sensors.nvme_temp ?? 0) / 1000; warn: 60; hot: 70 }
                        }
                    }
                }

                Rectangle {
                    x: parent.width - width
                    width: bottomRow.column
                    height: parent.height
                    radius: Theme.cornerRadius / 1.5
                    color: root.tileBg

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.spacingM
                        width: parent.width - Theme.spacingM * 2
                        spacing: 0

                        Row {
                            spacing: Theme.spacingXS
                            DankIcon { name: "hard_drive"; size: Theme.fontSizeMedium; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            StyledText { text: I18n.trFor("hwMonitor", "Disk"); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceTextSecondary }
                        }
                        StyledText { width: parent.width; elide: Text.ElideRight; text: "R " + root.rate(DgopService.diskReadRate); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                        StyledText { width: parent.width; elide: Text.ElideRight; text: "W " + root.rate(DgopService.diskWriteRate); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                    }
                }
            }
        }
    }
}
