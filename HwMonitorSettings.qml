import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "hwMonitor"

    SliderSetting {
        settingKey: "updateSeconds"
        label: "Обновлять каждые"
        description: "Как часто читать нагрузку видеокарты и температуры. CPU и RAM обновляет сам DMS."
        defaultValue: 2
        minimum: 1
        maximum: 10
        unit: " с"
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: "Непрозрачность фона"
        defaultValue: 80
        minimum: 0
        maximum: 100
        unit: "%"
    }
}
