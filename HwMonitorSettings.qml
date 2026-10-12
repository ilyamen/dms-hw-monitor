import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "hwMonitor"

    SliderSetting {
        settingKey: "updateSeconds"
        label: I18n.trFor("hwMonitor", "Update every")
        description: I18n.trFor("hwMonitor", "How often to read the GPU load and temperatures. DMS updates CPU and RAM itself.")
        defaultValue: 2
        minimum: 1
        maximum: 10
        unit: I18n.trFor("hwMonitor", " s")
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: I18n.trFor("hwMonitor", "Background opacity")
        defaultValue: 80
        minimum: 0
        maximum: 100
        unit: "%"
    }
}
