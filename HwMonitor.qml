import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Системный монитор: CPU / GPU / RAM / VRAM с графиками и блок всех температур.
// CPU, RAM, сеть и диск — из DgopService (как у встроенного монитора DMS),
// видеокарта и температуры — из sysfs через sensors.sh.
DesktopPluginComponent {
    id: root

    minWidth: 420
    minHeight: 260

    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 80) / 100
    property int historyLength: 60

    readonly property color bgColor: Theme.withAlpha(Theme.surface, backgroundOpacity)
    readonly property color tileBg: Theme.withAlpha(Theme.surfaceContainerHigh, backgroundOpacity)

    // ---------- данные ----------

    property var sensors: ({})
    property var gpuHistory: []
    property var vramHistory: []

    readonly property real gpuBusy: sensors.gpu_busy ?? 0
    readonly property real vramUsed: sensors.vram_used ?? 0
    readonly property real vramTotal: sensors.vram_total ?? 0

    readonly property var modules: ["cpu", "memory", "network", "disk"]
    Component.onCompleted: DgopService.addRef(modules)
    Component.onDestruction: DgopService.removeRef(modules)

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

    // ---------- формат ----------

    function gb(bytes) { return (bytes / 1073741824).toFixed(1); }

    function rate(bytesPerSec) {
        const b = bytesPerSec || 0;
        if (b >= 1048576)
            return (b / 1048576).toFixed(1) + " МБ/с";
        if (b >= 1024)
            return Math.round(b / 1024) + " КБ/с";
        return Math.round(b) + " Б/с";
    }

    function tempColor(t, warn, hot) {
        if (t >= hot)
            return Theme.error;
        if (t >= warn)
            return Theme.warning ?? "#ffb74d";
        return Theme.surfaceText;
    }

    // ---------- элементы ----------

    // Плитка: заголовок, крупное значение, подпись, график
    component Tile: Rectangle {
        id: tile
        property string icon
        property string title
        property string value
        property string sub
        property var history: []
        property real maxValue: 100
        property real fill: -1   // 0..1 — полоска заполнения (для памяти)

        radius: Theme.cornerRadius / 1.5
        color: root.tileBg

        // график
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

    // Температура: подпись + значение
    component TempItem: ColumnLayout {
        property string label
        property real temp: 0
        property real warn: 70
        property real hot: 85
        visible: temp > 0
        spacing: 0
        StyledText {
            text: Math.round(parent.temp) + "°"
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Font.Medium
            color: root.tempColor(parent.temp, parent.warn, parent.hot)
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            text: parent.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceTextSecondary
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ---------- вид ----------

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
                StyledText { text: "Система"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium; color: Theme.surfaceText }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: "↓ " + root.rate(DgopService.networkRxRate) + "   ↑ " + root.rate(DgopService.networkTxRate)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextSecondary
                }
            }

            // Нагрузка
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                columnSpacing: Theme.spacingS
                rowSpacing: Theme.spacingS

                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "memory"; title: "Процессор"
                    value: Math.round(DgopService.cpuUsage) + "%"
                    sub: DgopService.cpuFrequency > 0 ? (DgopService.cpuFrequency / 1000).toFixed(1) + " ГГц" : ""
                    history: DgopService.cpuHistory
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "developer_board"; title: "Видеокарта"
                    value: Math.round(root.gpuBusy) + "%"
                    sub: "RX 7900"
                    history: root.gpuHistory
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "memory_alt"; title: "Память"
                    value: Math.round(DgopService.memoryUsage) + "%"
                    sub: root.gb(DgopService.usedMemoryKB * 1024) + " / " + root.gb(DgopService.totalMemoryKB * 1024) + " ГБ"
                    history: DgopService.memoryHistory
                    fill: DgopService.memoryUsage / 100
                }
                Tile {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    icon: "view_in_ar"; title: "Видеопамять"
                    value: root.vramTotal > 0 ? Math.round(root.vramUsed / root.vramTotal * 100) + "%" : "—"
                    sub: root.gb(root.vramUsed) + " / " + root.gb(root.vramTotal) + " ГБ"
                    fill: root.vramTotal > 0 ? root.vramUsed / root.vramTotal : 0
                    history: root.vramHistory
                }
            }

            // Температуры одним блоком + диск
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: tempRow.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius / 1.5
                color: root.tileBg

                RowLayout {
                    id: tempRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingL

                    DankIcon { name: "thermostat"; size: Theme.iconSize; color: Theme.primary }
                    TempItem { label: "CPU"; temp: (root.sensors.cpu_temp ?? 0) / 1000; warn: 75; hot: 90; Layout.fillWidth: true }
                    TempItem { label: "GPU"; temp: (root.sensors.gpu_edge ?? 0) / 1000; warn: 75; hot: 90; Layout.fillWidth: true }
                    TempItem { label: "GPU хотспот"; temp: (root.sensors.gpu_junction ?? 0) / 1000; warn: 90; hot: 105; Layout.fillWidth: true }
                    TempItem { label: "VRAM"; temp: (root.sensors.gpu_mem ?? 0) / 1000; warn: 85; hot: 100; Layout.fillWidth: true }
                    TempItem { label: "SSD"; temp: (root.sensors.nvme_temp ?? 0) / 1000; warn: 60; hot: 70; Layout.fillWidth: true }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.outlineVariant; opacity: 0.5 }

                    ColumnLayout {
                        spacing: 0
                        StyledText { text: "Диск"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceTextSecondary }
                        StyledText { text: "R " + root.rate(DgopService.diskReadRate); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                        StyledText { text: "W " + root.rate(DgopService.diskWriteRate); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                    }
                }
            }
        }
    }
}
