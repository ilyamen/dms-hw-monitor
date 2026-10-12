#!/bin/sh
# Печатает key=value: нагрузка и память видеокарты AMD + температуры (°C*1000).
for d in /sys/class/drm/card*/device; do
    if [ -r "$d/gpu_busy_percent" ]; then
        echo "gpu_busy=$(cat "$d/gpu_busy_percent")"
        echo "vram_used=$(cat "$d/mem_info_vram_used" 2>/dev/null)"
        echo "vram_total=$(cat "$d/mem_info_vram_total" 2>/dev/null)"
        break
    fi
done
for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name")" in
        coretemp|k10temp)
            for l in "$h"/temp*_label; do
                case "$(cat "$l")" in "Package id 0"|Tctl|Tdie) echo "cpu_temp=$(cat "${l%_label}_input")"; break;; esac
            done ;;
        amdgpu)
            for l in "$h"/temp*_label; do
                echo "gpu_$(cat "$l")=$(cat "${l%_label}_input")"
            done ;;
        nvme)
            [ -z "$nvme_done" ] && echo "nvme_temp=$(cat "$h/temp1_input")" && nvme_done=1 ;;
    esac
done
