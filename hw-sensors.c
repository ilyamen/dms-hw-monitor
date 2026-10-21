#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/statvfs.h>
#include <unistd.h>

static int read_int_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int val = 0;
    if (fscanf(f, "%d", &val) != 1) val = 0;
    fclose(f);
    return val;
}

static long long read_ll_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    long long val = 0;
    if (fscanf(f, "%lld", &val) != 1) val = 0;
    fclose(f);
    return val;
}

int main(void) {
    int gpu_busy = 0;
    long long vram_used = 0, vram_total = 0;

    // 1. GPU busy & VRAM
    DIR *drm_dir = opendir("/sys/class/drm");
    if (drm_dir) {
        struct dirent *ent;
        while ((ent = readdir(drm_dir)) != NULL) {
            if (strncmp(ent->d_name, "card", 4) == 0 && strchr(ent->d_name, '-') == NULL) {
                char path[256];
                snprintf(path, sizeof(path), "/sys/class/drm/%s/device/gpu_busy_percent", ent->d_name);
                if (access(path, R_OK) == 0) {
                    gpu_busy = read_int_file(path);
                    snprintf(path, sizeof(path), "/sys/class/drm/%s/device/mem_info_vram_used", ent->d_name);
                    long long vu = read_ll_file(path);
                    snprintf(path, sizeof(path), "/sys/class/drm/%s/device/mem_info_vram_total", ent->d_name);
                    long long vt = read_ll_file(path);
                    snprintf(path, sizeof(path), "/sys/class/drm/%s/device/mem_info_gtt_used", ent->d_name);
                    long long gu = read_ll_file(path);
                    snprintf(path, sizeof(path), "/sys/class/drm/%s/device/mem_info_gtt_total", ent->d_name);
                    long long gt = read_ll_file(path);
                    vram_used = vu + gu;
                    vram_total = vt + gt;
                    break;
                }
            }
        }
        closedir(drm_dir);
    }

    int cpu_temp = 0, gpu_temp = 0, nvme_temp = 0, hdd_temp = 0, power_w = 0;

    // 2. Temperatures & Power
    DIR *hwmon_dir = opendir("/sys/class/hwmon");
    if (hwmon_dir) {
        struct dirent *ent;
        while ((ent = readdir(hwmon_dir)) != NULL) {
            if (strncmp(ent->d_name, "hwmon", 5) == 0) {
                char name_path[256];
                snprintf(name_path, sizeof(name_path), "/sys/class/hwmon/%s/name", ent->d_name);
                FILE *nf = fopen(name_path, "r");
                if (!nf) continue;
                char name[64] = {0};
                if (fgets(name, sizeof(name), nf)) {
                    char *nl = strchr(name, '\n');
                    if (nl) *nl = '\0';
                }
                fclose(nf);

                char val_path[256];
                if (strcmp(name, "k10temp") == 0 || strcmp(name, "coretemp") == 0) {
                    snprintf(val_path, sizeof(val_path), "/sys/class/hwmon/%s/temp1_input", ent->d_name);
                    int t = read_int_file(val_path);
                    if (t > 0) cpu_temp = t / 1000;
                } else if (strcmp(name, "amdgpu") == 0) {
                    snprintf(val_path, sizeof(val_path), "/sys/class/hwmon/%s/temp1_input", ent->d_name);
                    int t = read_int_file(val_path);
                    if (t > 0) gpu_temp = t / 1000;

                    snprintf(val_path, sizeof(val_path), "/sys/class/hwmon/%s/power1_input", ent->d_name);
                    int p = read_int_file(val_path);
                    if (p > 0) power_w = p / 1000000;
                } else if (strcmp(name, "nvme") == 0) {
                    snprintf(val_path, sizeof(val_path), "/sys/class/hwmon/%s/temp1_input", ent->d_name);
                    int t = read_int_file(val_path);
                    if (t > 0 && nvme_temp == 0) nvme_temp = t / 1000;
                } else if (strcmp(name, "drivetemp") == 0) {
                    snprintf(val_path, sizeof(val_path), "/sys/class/hwmon/%s/temp1_input", ent->d_name);
                    int t = read_int_file(val_path);
                    if (t > 0 && hdd_temp == 0) hdd_temp = t / 1000;
                }
            }
        }
        closedir(hwmon_dir);
    }

    // 3. Statvfs Root
    int root_total = 0, root_used = 0, root_avail = 0, root_pct = 0;
    struct statvfs st;
    if (statvfs("/", &st) == 0) {
        unsigned long long blksize = st.f_frsize;
        unsigned long long total = (st.f_blocks * blksize) / (1024ULL * 1024 * 1024);
        unsigned long long avail = (st.f_bavail * blksize) / (1024ULL * 1024 * 1024);
        unsigned long long used = total > avail ? (total - avail) : 0;
        root_total = (int)total;
        root_avail = (int)avail;
        root_used = (int)used;
        if (root_total > 0) root_pct = (int)((used * 100ULL) / total);
    }

    // 4. Statvfs /data
    int data_mounted = 0, data_total = 0, data_used = 0, data_avail = 0, data_pct = 0;
    if (statvfs("/data", &st) == 0 && st.f_blocks > 0) {
        // Check if actually mounted separately
        struct statvfs root_st;
        if (statvfs("/", &root_st) == 0 && st.f_fsid != root_st.f_fsid) {
            data_mounted = 1;
            unsigned long long blksize = st.f_frsize;
            unsigned long long total = (st.f_blocks * blksize) / (1024ULL * 1024 * 1024);
            unsigned long long avail = (st.f_bavail * blksize) / (1024ULL * 1024 * 1024);
            unsigned long long used = total > avail ? (total - avail) : 0;
            data_total = (int)total;
            data_avail = (int)avail;
            data_used = (int)used;
            if (data_total > 0) data_pct = (int)((used * 100ULL) / total);
        }
    }

    printf("{\"gpu_busy\":%d,\"vram_used\":%lld,\"vram_total\":%lld,\"cpu_temp\":%d,\"gpu_temp\":%d,\"nvme_temp\":%d,\"hdd_temp\":%d,\"power_w\":%d,\"root_total\":%d,\"root_used\":%d,\"root_avail\":%d,\"root_pct\":%d,\"data_mounted\":%s,\"data_total\":%d,\"data_used\":%d,\"data_avail\":%d,\"data_pct\":%d}\n",
           gpu_busy, vram_used, vram_total, cpu_temp, gpu_temp, nvme_temp, hdd_temp, power_w,
           root_total, root_used, root_avail, root_pct,
           data_mounted ? "true" : "false", data_total, data_used, data_avail, data_pct);
    return 0;
}
