# Hardware Monitor for DankMaterialShell

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) desktop widget with load graphs for CPU, GPU, RAM and VRAM, and every temperature in one row: CPU package, GPU edge and hotspot, VRAM and the first NVMe drive. Temperatures turn amber and red as they get hot. Disk and network throughput are shown too.

CPU and RAM come from DMS itself (dgop). The GPU load, VRAM and temperatures are read from sysfs by `sensors.sh`, which takes a few milliseconds and needs no extra packages.

The interface is in Russian for now.

## Requirements

- DMS 1.6.0 or newer
- For the GPU tiles, an AMD GPU (`amdgpu` exposes `gpu_busy_percent` and VRAM usage). Intel `coretemp` and AMD `k10temp` CPUs are both supported for the CPU temperature.

## Installation

In DMS Settings → Plugins, add the registry `https://github.com/ilyamen/dms-plugin-registry.git` and install **Hardware Monitor** from Browse, or:

```sh
git clone https://github.com/ilyamen/dms-hw-monitor ~/.config/DankMaterialShell/plugins/hwMonitor
```

Enable it in Settings → Plugins and add the widget in Settings → Desktop Widgets.

## License

MIT
