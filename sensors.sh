#!/bin/sh
# Prints key=value lines: load and memory of an AMD GPU, and temperatures (°C × 1000), power (W)

for d in /sys/class/drm/card*/device; do
    if [ -r "$d/gpu_busy_percent" ]; then
        echo "gpu_busy=$(cat "$d/gpu_busy_percent")"
        vram_u=$(cat "$d/mem_info_vram_used" 2>/dev/null || echo 0)
        vram_t=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
        gtt_u=$(cat "$d/mem_info_gtt_used" 2>/dev/null || echo 0)
        gtt_t=$(cat "$d/mem_info_gtt_total" 2>/dev/null || echo 0)
        # Sum of dedicated VRAM + dynamic GTT memory from RAM
        echo "vram_used=$((vram_u + gtt_u))"
        echo "vram_total=$((vram_t + gtt_t))"
        break
    fi
done

for h in /sys/class/hwmon/hwmon*; do
    name=$(cat "$h/name" 2>/dev/null)
    case "$name" in
        coretemp|k10temp)
            for l in "$h"/temp*_label; do
                case "$(cat "$l" 2>/dev/null)" in "Package id 0"|Tctl|Tdie) echo "cpu_temp=$(cat "${l%_label}_input")"; break;; esac
            done
            [ -z "${cpu_temp:-}" ] && [ -r "$h/temp1_input" ] && echo "cpu_temp=$(cat "$h/temp1_input")"
            ;;
        amdgpu)
            for l in "$h"/temp*_label; do
                echo "gpu_$(cat "$l")=$(cat "${l%_label}_input")"
            done
            [ -r "$h/temp1_input" ] && echo "gpu_edge=$(cat "$h/temp1_input")"
            if [ -r "$h/power1_input" ]; then
                pw=$(cat "$h/power1_input" 2>/dev/null || echo 0)
                echo "power_w=$((pw / 1000000))"
            fi
            ;;
        nvme)
            [ -z "${nvme_done:-}" ] && echo "nvme_temp=$(cat "$h/temp1_input")" && nvme_done=1 ;;
        drivetemp)
            [ -z "${hdd_done:-}" ] && echo "hdd_temp=$(cat "$h/temp1_input")" && hdd_done=1 ;;
    esac
done
