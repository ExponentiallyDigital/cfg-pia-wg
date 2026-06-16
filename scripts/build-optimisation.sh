#!/usr/bin/env bash
#
# Optimised Android / Flutter build environment installer & tuner
#
# Single-file installer that:
#  - Configures tmpfs for /tmp on systems with >= 16 GB RAM only; disabled on
#    <= 8 GB tiers where RAM is too scarce for a scratch disk that Android build
#    tools fill unpredictably (Gemini: filling /tmp causes builds to crash with
#    "No space left on device"; paging Gradle to ZRAM just to hold /tmp data is
#    counterproductive)
#  - Writes optimised ~/.gradle/gradle.properties with all three AI reviews
#    factored in: daemon, parallel (RAM-conditional), caching, RAM-tiered JVM
#    heap, workers.max, G1PeriodicGCInterval, ExitOnOutOfMemoryError, Kotlin
#    daemon heap, daemon idle timeout, and configuration-cache guidance
#  - Prepares ~/.pub-cache for Dart/Flutter package persistence
#  - Creates a tier-specific on-disk swapfile with explicit low priority (pri=10)
#    so ZRAM always takes precedence as the hot swap layer
#  - Configures ZRAM at ~50% of RAM (significantly larger than original
#    conservative sizing); ZRAM is the primary fast-swap layer, disk swap is the
#    safety net
#  - Sets vm.swappiness HIGH for low-RAM tiers — counterintuitive but correct
#    when ZRAM is the primary swap: the kernel prefers pushing anonymous heap
#    pages into compressed ZRAM over evicting the file cache that build tooling
#    reads constantly (Gemini); original had this backwards
#  - Sets vm.vfs_cache_pressure LOW for low-RAM tiers: retain more dentry/inode
#    metadata in cache; ZRAM absorbs heap pressure so we can afford to keep file
#    cache even on tight machines
#  - Applies device-type-aware I/O scheduler tuning via udev; acknowledged as
#    marginal on modern NVMe/SSD (GPT, Deepseek) but meaningful for HDD/eMMC;
#    read-ahead values reduced to match Android's random-read-heavy workload
#  - Adds per-user resource limits
#  - Adds user to the correct kvm device group with /dev/kvm existence check
#  - Verifies the full configuration after setup
#
# Supported RAM_GB values: 2, 4, 6, 8, 16, 32, 64
#   <= 8 GB: tmpfs disabled; ZRAM-first aggressive strategy; parallel=false
#   >= 16 GB: tmpfs enabled; balanced strategy; parallel=true
#
# ─── Change log from original ─────────────────────────────────────────────────
#
# BUGS FIXED (original code review):
#   FIX  ZRAM config writes zram-size as plain MiB integer (was "2G" etc., which
#        systemd-zram-generator silently ignores)
#   FIX  blockdev --setra removed; udev is now sole authority on read_ahead_kb
#        (--setra takes 512-byte sectors not KB; --setra 4096 = 2048 KB, silently
#        overwriting the HDD udev rule that correctly set 4096 KB)
#   FIX  Redundant fstab swap guard removed (grep -Fxq check never fired)
#   FIX  I/O scheduler verification now checks active [bracketed] value rather
#        than just confirming the sysfs path exists
#   FIX  eMMC (mmcblk) and virtio (vda) device parent detection added; both
#        previously fell through to a branch that set the partition as its own
#        parent, breaking all scheduler sysfs operations on those device types
#   FIX  btrfs root filesystem detection forces dd for swapfile (fallocate on
#        btrfs creates a CoW file that mkswap rejects)
#   FIX  Section numbering corrected (Section 3 was absent; two Section 12s)
#
# CHANGES FROM AI REVIEWS (GPT, Gemini, Deepseek):
#   CHG  ZRAM sizes increased to ~50% of RAM (was 25%; GPT: 25-50%; Gemini: up
#        to 100-150%; 50% is the pragmatic centre — matches common distro defaults)
#   CHG  Swapfile default is now tier-specific with no 32 GB universal floor
#        (all three reviews: 32 GB floor is absurd for low-RAM systems; Deepseek:
#        "4x physical RAM will thrash horribly"; GPT: 8 GB is sufficient safety net)
#   CHG  Swapfile gets explicit low priority (pri=10 vs ZRAM's default 100) so
#        the kernel always exhausts ZRAM before spilling to disk
#   CHG  vm.swappiness INCREASED for low-RAM tiers (Gemini: with ZRAM as primary
#        swap, higher swappiness is correct — it tells the kernel to push heap to
#        ZRAM and keep file cache; original values were backwards for a ZRAM setup)
#   CHG  vm.vfs_cache_pressure LOWERED for low-RAM tiers (retain dentry/inode
#        cache; ZRAM handles heap so we can afford more metadata retention)
#   CHG  org.gradle.parallel=false for <= 8 GB (GPT: multiple worker JVMs on
#        8 GB exhaust physical RAM; true only for >= 16 GB)
#   CHG  -XX:+UseG1GC reinstated (required to use G1-specific GC flags below;
#        while redundant as a default, its presence documents intent)
#   CHG  -XX:G1PeriodicGCInterval=3000 added (Gemini: releases idle JVM heap to
#        OS every 3 s between build tasks; requires JDK 12+; harmless on JDK 11
#        where it is silently ignored)
#   CHG  -XX:+ExitOnOutOfMemoryError added (Gemini: fail fast on OOM rather than
#        grinding through 90%+ CPU in GC trying to reclaim fragments)
#   CHG  Gradle heap values revised upward for low-RAM tiers (Gemini: 2 GB on
#        8 GB system causes GC overhead limit; G1PeriodicGCInterval allows a
#        larger ceiling since idle heap is periodically returned to OS)
#   CHG  org.gradle.configuration-cache guidance added as a commented-out block
#        (GPT: biggest modern omission; Deepseek: major rebuildd time reduction;
#        commented out because enabling it globally can break projects with
#        incompatible plugins — user must test and opt in per-project)
#   CHG  tmpfs on /tmp disabled for <= 8 GB tiers; enabled from 16 GB upward
#        (Gemini: filling /tmp causes "no space left" crashes; GPT: benefit is
#        marginal on NVMe anyway — 0-5% within measurement noise)
#   CHG  2 GB, 4 GB, 6 GB RAM tiers added with appropriate warnings (Deepseek:
#        "low RAM" should mean 2-6 GB; 8 GB is borderline, not truly low RAM)
#   CHG  flutter doctor removed from verification pass (GPT: unrelated to
#        optimisation; slow; can fail due to SDK issues unrelated to this script)
#   CHG  kvm section now checks /dev/kvm existence and reads actual device group
#        (Deepseek: some distros use libvirt, qemu, or vboxusers instead of kvm)
#   CHG  udev read_ahead_kb values reduced (GPT: Android builds are random-read-
#        heavy with many small files; large read-ahead windows add latency and
#        cache pressure rather than throughput)
#   REM  org.gradle.configureondemand removed (GPT, Gemini: deprecated Gradle 8;
#        can break multi-project builds with cross-project config dependencies)
#   ADD  org.gradle.daemon.idletimeout=600000 (Deepseek: default 3-hour idle
#        holds 25% of RAM hostage on 8 GB machine between builds)
#   ADD  org.gradle.workers.max per RAM tier (all reviews: single biggest missing
#        optimisation; uncapped workers multiply per-worker heap to OOM)
#   ADD  kotlin.daemon.jvm.options per RAM tier (GPT, Deepseek: Kotlin daemon is
#        a separate JVM with its own uncapped heap, invisible in gradle.properties)
#   FIX  nofile reduced from 1,048,576 to 262,144 (all reviews: 1 M indefensible;
#        256 K covers Gradle + Dart file watcher with headroom)
#   REM  "Pre-warms Gradle dependency cache" header claim removed (feature absent)
#
# Prerequisites: Flutter, Android SDK, JDK, and standard build tools must already
# be installed. ANDROID_HOME, ANDROID_SDK_ROOT, and JAVA_HOME are not modified.
#
# Usage:
#   sudo ./build-optimisation.sh
#   sudo ./build-optimisation.sh <RAM_GB> <DISK_DEVICE>
#   sudo SWAP_GB=16 ./build-optimisation.sh 8 /dev/sda5
#
# Supported RAM_GB values: 2, 4, 6, 8, 16, 32, 64

set -euo pipefail

# ─── Environment & OS Validation ──────────────────────────────────────────────
OS_TYPE="$(uname -s)"
case "${OS_TYPE}" in
  CYGWIN*|MINGW*|MSYS*|Windows_NT*)
    echo "ERROR: This script is built exclusively for Linux."
    echo "It cannot be executed within a Windows native shell (Git Bash/Cygwin/MSYS)."
    exit 1
    ;;
esac

if grep -qi 'microsoft' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  echo "ERROR: Windows Subsystem for Linux (WSL) detected."
  echo "This tuner configures low-level Linux hardware optimizations (ZRAM, I/O schedulers, fstab)."
  echo "These configurations do not apply inside a WSL container managed by the Windows host."
  exit 1
fi

# ─── 1. Root Privilege & User Context ─────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (sudo)."
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
UNDO_FILE="${TARGET_HOME}/android_build_undo_${TIMESTAMP}.sh"

print_usage() {
  cat <<EOF
Usage: sudo $0 [RAM_GB] [DISK_DEVICE]
  RAM_GB      : 2 | 4 | 6 | 8 | 16 | 32 | 64
  DISK_DEVICE : block device or partition (e.g. /dev/sda5 or /dev/nvme0n1p3)
  SWAP_GB     : optional env var to override swapfile size (e.g. SWAP_GB=16)
EOF
}

# ─── 2. Argument Parsing ──────────────────────────────────────────────────────
RAM_GB="${1:-}"
DISK_DEVICE="${2:-}"

if [ -z "$RAM_GB" ]; then
  read -rp "Enter system RAM tier in GB (2, 4, 6, 8, 16, 32, 64): " RAM_GB
fi

if [ -z "$DISK_DEVICE" ]; then
  read -rp "Enter block device target (e.g., /dev/sda5): " DISK_DEVICE
fi

if [ ! -b "${DISK_DEVICE}" ]; then
  echo "ERROR: '${DISK_DEVICE}' is not a valid block device."
  print_usage
  exit 1
fi

# ─── 3. Low-RAM Tier Warning ──────────────────────────────────────────────────
# 2-4 GB is genuinely extreme for modern Android/Flutter builds. The Gradle daemon
# alone can consume 1-2 GB; AAPT2 and R8/D8 add more. Builds will be slow and may
# fail on larger projects. Warn prominently before proceeding.
if [ "${RAM_GB}" -le 4 ] 2>/dev/null; then
  echo ""
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│  WARNING: ${RAM_GB} GB is extremely low for modern Android/Flutter builds.  │"
  echo "│  Expect slow builds and potential OOM failures on large projects.   │"
  echo "│  This configuration prioritises build survival over speed.          │"
  echo "│  A 16 GB machine is the practical minimum for comfortable Flutter   │"
  echo "│  development; 8 GB is workable; below that is heroic.              │"
  echo "└─────────────────────────────────────────────────────────────────────┘"
  echo ""
  read -rp "Proceed with ${RAM_GB} GB configuration? (y/N): " LOWRAM_CONFIRM
  if [[ ! "${LOWRAM_CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# ─── 4. Memory-Profile Variables ──────────────────────────────────────────────
#
# TMPFS_SIZE      : "disabled" for <= 8 GB (RAM too scarce; /tmp stays on disk);
#                   size string for >= 16 GB. Android build tools can fill /tmp
#                   unpredictably: a full tmpfs causes "No space left on device"
#                   crashes, and paging Gradle out to hold /tmp data in RAM is
#                   self-defeating. On NVMe/SSD the benefit is 0-5% anyway.
#
# ZRAM_SIZE_MIB   : ~50% of physical RAM in MiB (plain integer required by
#                   systemd-zram-generator). Previous values were ~25%, which is
#                   overly conservative. Most distributions now default to 25-50%;
#                   50% uses zstd compression (≈2.5:1 ratio) for ~125% effective
#                   swap in a ~50% RAM footprint.
#
# SWAP_GB_DEFAULT : On-disk swapfile size default, tier-specific. No 32 GB floor.
#                   The disk swapfile is the safety net beneath ZRAM — it needs to
#                   be large enough to absorb genuine OOM events but not so large
#                   that a thrashing machine becomes a slowly-dying machine.
#                   Swapfile gets priority 10 vs ZRAM's 100: disk is never touched
#                   until ZRAM is exhausted.
#
# SYS_SWAPPINESS  : HIGHER for low-RAM tiers — counterintuitive but correct when
#                   ZRAM is the primary swap layer. High swappiness tells the
#                   kernel to push anonymous memory (JVM heap pages that are idle
#                   between tasks) into compressed ZRAM, freeing physical RAM for
#                   the active compilation and the file cache it reads constantly.
#                   Original had this backwards (low swappiness on low RAM), which
#                   causes the kernel to evict file cache instead of using ZRAM.
#
# SYS_VFS         : vm.vfs_cache_pressure — LOWER for low-RAM tiers. Lower values
#                   make the kernel retain dentry/inode metadata longer. Android
#                   builds read thousands of small files repeatedly; retaining
#                   their metadata in cache is valuable. With ZRAM handling heap
#                   pressure, we can afford this even on tight machines.
#
# GRADLE_JVM_MAX  : Gradle daemon -Xmx heap ceiling. Increased from original for
#                   low-RAM tiers: too small a heap causes GC overhead limit errors
#                   (Gemini). G1PeriodicGCInterval allows a higher ceiling because
#                   idle heap is periodically returned to the OS between tasks.
#
# GRADLE_WORKERS  : org.gradle.workers.max — caps parallel worker JVM count. Each
#                   worker can consume up to GRADLE_JVM_MAX; without a cap a build
#                   with N modules spawns N worker JVMs silently exhausting RAM.
#
# KOTLIN_JVM_MAX  : Kotlin compiler daemon -Xmx. Independent of Gradle's heap;
#                   invisible to gradle.properties without explicit configuration.
#
# GRADLE_PARALLEL : false for <= 8 GB (multiple concurrent JVMs exhaust RAM);
#                   true for >= 16 GB.
#
case "$RAM_GB" in
  2)  TMPFS_SIZE="disabled"; ZRAM_SIZE_MIB=2048;  SWAP_GB_DEFAULT=4;  SYS_SWAPPINESS=100; SYS_VFS=50; GRADLE_JVM_MAX="1024m"; GRADLE_WORKERS=1; KOTLIN_JVM_MAX="384m";  GRADLE_PARALLEL="false" ;;
  4)  TMPFS_SIZE="disabled"; ZRAM_SIZE_MIB=3072;  SWAP_GB_DEFAULT=4;  SYS_SWAPPINESS=100; SYS_VFS=50; GRADLE_JVM_MAX="1536m"; GRADLE_WORKERS=1; KOTLIN_JVM_MAX="384m";  GRADLE_PARALLEL="false" ;;
  6)  TMPFS_SIZE="disabled"; ZRAM_SIZE_MIB=4096;  SWAP_GB_DEFAULT=4;  SYS_SWAPPINESS=90;  SYS_VFS=50; GRADLE_JVM_MAX="2048m"; GRADLE_WORKERS=2; KOTLIN_JVM_MAX="512m";  GRADLE_PARALLEL="false" ;;
  8)  TMPFS_SIZE="disabled"; ZRAM_SIZE_MIB=4096;  SWAP_GB_DEFAULT=8;  SYS_SWAPPINESS=80;  SYS_VFS=50; GRADLE_JVM_MAX="3072m"; GRADLE_WORKERS=2; KOTLIN_JVM_MAX="512m";  GRADLE_PARALLEL="false" ;;
  16) TMPFS_SIZE="2G";       ZRAM_SIZE_MIB=8192;  SWAP_GB_DEFAULT=8;  SYS_SWAPPINESS=60;  SYS_VFS=60; GRADLE_JVM_MAX="4096m"; GRADLE_WORKERS=3; KOTLIN_JVM_MAX="1024m"; GRADLE_PARALLEL="true"  ;;
  32) TMPFS_SIZE="4G";       ZRAM_SIZE_MIB=16384; SWAP_GB_DEFAULT=4;  SYS_SWAPPINESS=40;  SYS_VFS=70; GRADLE_JVM_MAX="6144m"; GRADLE_WORKERS=4; KOTLIN_JVM_MAX="2048m"; GRADLE_PARALLEL="true"  ;;
  64) TMPFS_SIZE="4G";       ZRAM_SIZE_MIB=16384; SWAP_GB_DEFAULT=4;  SYS_SWAPPINESS=20;  SYS_VFS=75; GRADLE_JVM_MAX="8192m"; GRADLE_WORKERS=6; KOTLIN_JVM_MAX="2048m"; GRADLE_PARALLEL="true"  ;;
  *) echo "Unsupported RAM tier: $RAM_GB"; print_usage; exit 1 ;;
esac

# Swapfile size: tier-specific default, overridable via SWAP_GB env var.
# No 32 GB floor. The disk swapfile is a safety net, not the primary swap.
# Override: sudo SWAP_GB=16 ./build-optimisation.sh 8 /dev/sda5
if [ -n "${SWAP_GB:-}" ]; then
  if ! printf '%s' "${SWAP_GB}" | grep -qE '^[0-9]+$'; then
    echo "ERROR: SWAP_GB must be a positive integer number of GB (got '${SWAP_GB}')."
    exit 1
  fi
  SWAP_SIZE="${SWAP_GB}G"
else
  SWAP_SIZE="${SWAP_GB_DEFAULT}G"
fi

# ─── 5. Parent Block Device, Type, and Scheduler Detection ────────────────────
# The I/O scheduler sysfs interface lives on the parent block device, not the
# partition node. Derive the parent and device type from the supplied path.
#
# Device family parent derivation:
#   nvme0n1p3  -> nvme0n1    (NVMe;       strip trailing pN)
#   sda5       -> sda         (SATA;       strip trailing digits)
#   mmcblk0p1  -> mmcblk0    (eMMC;       strip trailing pN)
#   vda1       -> vda         (virtio-blk; strip trailing digits)
DISK_BASE=$(basename "${DISK_DEVICE}")
if echo "${DISK_BASE}" | grep -qE "^nvme"; then
  DISK_PARENT=$(echo "${DISK_BASE}" | sed 's/p[0-9]*$//')
  IO_SCHEDULER="none"
  DISK_TYPE="nvme"
elif echo "${DISK_BASE}" | grep -qE "^mmcblk"; then
  DISK_PARENT=$(echo "${DISK_BASE}" | sed 's/p[0-9]*$//')
  IO_SCHEDULER="mq-deadline"
  DISK_TYPE="emmc"
elif echo "${DISK_BASE}" | grep -qE "^vd[a-z]"; then
  DISK_PARENT=$(echo "${DISK_BASE}" | sed 's/[0-9]*$//')
  IO_SCHEDULER="mq-deadline"
  DISK_TYPE="virtio"
elif echo "${DISK_BASE}" | grep -qE "^sd"; then
  DISK_PARENT=$(echo "${DISK_BASE}" | sed 's/[0-9]*$//')
  IO_SCHEDULER="mq-deadline"
  DISK_TYPE="sata"
else
  DISK_PARENT="${DISK_BASE}"
  IO_SCHEDULER="mq-deadline"
  DISK_TYPE="unknown"
  echo "[!] Unrecognised device type for '${DISK_BASE}' — I/O scheduler rules may not target the correct device."
fi

# ─── 6. Setup Banner ──────────────────────────────────────────────────────────
echo "=========================================="
echo " Starting Optimised Build Environment Setup"
echo " User:                 ${TARGET_USER}"
echo " Home:                 ${TARGET_HOME}"
echo " RAM tier:             ${RAM_GB} GB"
echo " Drive:                ${DISK_DEVICE} (type=${DISK_TYPE}, scheduler=${IO_SCHEDULER})"
echo " ZRAM:                 ${ZRAM_SIZE_MIB} MiB (~50% RAM, primary fast swap)"
echo " Swapfile:             ${SWAP_SIZE} (low-priority safety net)"
echo " vm.swappiness:        ${SYS_SWAPPINESS} (higher = prefer ZRAM over file cache eviction)"
echo " vm.vfs_cache_pressure:${SYS_VFS} (lower = retain more dentry/inode metadata)"
echo " Gradle heap:          ${GRADLE_JVM_MAX}, workers.max=${GRADLE_WORKERS}, parallel=${GRADLE_PARALLEL}"
echo " Kotlin daemon heap:   ${KOTLIN_JVM_MAX}"
if [ "${TMPFS_SIZE}" = "disabled" ]; then
  echo " tmpfs /tmp:           disabled (RAM tier <= 8 GB; /tmp stays on disk)"
else
  echo " tmpfs /tmp:           ${TMPFS_SIZE}"
fi
echo "=========================================="

# ─── 7. Initialise the Timestamped Undo Engine ────────────────────────────────
cat << 'EOF' > "$UNDO_FILE"
#!/usr/bin/env bash
set -euo pipefail
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This recovery script must be run as root (sudo)."
  exit 1
fi
echo "Initiating system recovery rollback..."
EOF

# ─── 8. Directory Layout and Ownership ────────────────────────────────────────
echo "[*] Creating cache directory layout..."
sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/.gradle/caches" \
         "${TARGET_HOME}/.gradle/daemon" \
         "${TARGET_HOME}/.gradle/native" \
         "${TARGET_HOME}/.gradle/wrapper" \
         "${TARGET_HOME}/.pub-cache"

chmod 1777 /tmp || true

# ─── 9. Optimised ~/.gradle/gradle.properties ─────────────────────────────────
# NOTE: This is the global (~/.gradle) properties file. Settings apply to every
# Gradle project run by TARGET_USER. The JVM heap, workers.max, and Kotlin caps
# are the most impactful on a low-RAM machine and the most likely to need
# project-specific override via a local gradle.properties at the project root
# (which takes precedence over this global file).
echo "[*] Writing optimised Gradle properties..."
GRADLE_PROPS="${TARGET_HOME}/.gradle/gradle.properties"

if [ -f "${GRADLE_PROPS}" ]; then
  cp "${GRADLE_PROPS}" "${GRADLE_PROPS}.bak.${TIMESTAMP}"
  cat << EOF >> "$UNDO_FILE"
echo "  - Restoring original gradle.properties..."
if [ -f "${GRADLE_PROPS}.bak.${TIMESTAMP}" ]; then
  mv "${GRADLE_PROPS}.bak.${TIMESTAMP}" "${GRADLE_PROPS}"
  chown "${TARGET_USER}:${TARGET_USER}" "${GRADLE_PROPS}"
else
  rm -f "${GRADLE_PROPS}"
fi
EOF
else
  cat << EOF >> "$UNDO_FILE"
echo "  - Removing generated gradle.properties block..."
sed -i '/# BUILD TUNER START/,/# BUILD TUNER END/d' "${GRADLE_PROPS}" 2>/dev/null || true
EOF
fi

sed -i '/# BUILD TUNER START/,/# BUILD TUNER END/d' "${GRADLE_PROPS}" 2>/dev/null || true

cat >> "${GRADLE_PROPS}" << EOF
# BUILD TUNER START
org.gradle.daemon=true

# Reclaim daemon heap 10 minutes after the build completes. The default (3 hours)
# keeps a ${GRADLE_JVM_MAX} JVM resident indefinitely — 25% of RAM on an 8 GB machine.
org.gradle.daemon.idletimeout=600000

# Parallel builds disabled on <= 8 GB: each worker JVM can consume the full heap
# ceiling, and spawning multiple workers on a tight machine causes OOM before the
# build completes. Enabled on >= 16 GB where the tradeoff is favourable.
org.gradle.parallel=${GRADLE_PARALLEL}

org.gradle.caching=true

# Cap worker JVMs. Without this, Gradle spawns one worker per CPU core by default.
# On an 8-core machine with 8 GB RAM, 8 workers * ${GRADLE_JVM_MAX} = instant OOM.
# This is the single most effective low-RAM optimisation and was missing entirely
# from the original script (flagged by all three AI reviews).
org.gradle.workers.max=${GRADLE_WORKERS}

# JVM flags:
#  -XX:+UseG1GC              : explicit (required to use G1-specific flags below)
#  -XX:G1PeriodicGCInterval  : run a GC pass every 3 s when the JVM is idle,
#                               releasing heap back to the OS between build tasks.
#                               Allows a higher -Xmx ceiling without permanently
#                               consuming that RAM. Requires JDK 12+; silently
#                               ignored on JDK 11.
#  -XX:+ExitOnOutOfMemoryError: kill the JVM immediately on OOM rather than
#                               grinding through 90%+ CPU in GC trying to reclaim
#                               fragments. Fail fast; identify the problem.
org.gradle.jvmargs=-Xmx${GRADLE_JVM_MAX} -XX:+UseG1GC -XX:G1PeriodicGCInterval=3000 -XX:+ExitOnOutOfMemoryError -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8

# Kotlin compiler daemon heap. This is a completely separate JVM process from
# the Gradle daemon, with its own independent heap. Without this setting, the
# Kotlin daemon can silently consume as much memory as it wants, defeating the
# purpose of capping the Gradle daemon. Missing from the original script.
kotlin.daemon.jvm.options=-Xmx${KOTLIN_JVM_MAX} -XX:MaxMetaspaceSize=256m

# ─── Configuration Cache ───────────────────────────────────────────────────────
# The configuration cache skips the entire Gradle configuration phase on
# subsequent builds. Rebuild times can improve 50-80% once the cache is warm.
# This is the biggest modern Gradle optimisation omitted from the original script
# (flagged by GPT and Deepseek reviews).
#
# WHY THIS IS COMMENTED OUT:
#   Enabling it globally here would affect every project run by ${TARGET_USER}.
#   Some plugins (particularly older AGP versions, some annotation processors,
#   and certain custom tasks) are not yet configuration-cache compatible. An
#   incompatible plugin causes the build to fail with a CC violation error.
#
# HOW TO ENABLE:
#   1. Test your specific project first:
#        ./gradlew --configuration-cache assembleDebug
#   2. If the build succeeds with no CC problems reported, uncomment below.
#   3. If there are violations, add --configuration-cache-problems=warn to
#      see which plugins are incompatible before committing to enabling it.
#
# org.gradle.configuration-cache=true
# org.gradle.configuration-cache.problems=warn
# ──────────────────────────────────────────────────────────────────────────────
# BUILD TUNER END
EOF

chown "${TARGET_USER}:${TARGET_USER}" "${GRADLE_PROPS}"

# ─── 10. fstab: tmpfs and Swapfile ────────────────────────────────────────────
echo "[*] Configuring fstab entries..."

cat << EOF >> "$UNDO_FILE"
echo "  - Removing swapfile and tmpfs fstab entries..."
sed -i '/^\/swapfile/d' /etc/fstab
sed -i '/[[:space:]]\/tmp[[:space:]]tmpfs/d' /etc/fstab
EOF

# tmpfs on /tmp: disabled for <= 8 GB tiers.
# Reasons: RAM is too scarce; Android build tools fill /tmp unpredictably;
# a full tmpfs crashes the build; paging Gradle to hold /tmp data is
# counterproductive; NVMe/SSD benefit is marginal (0-5%).
if [ "${TMPFS_SIZE}" != "disabled" ]; then
  if systemctl list-unit-files tmp.mount 2>/dev/null | grep -q "tmp.mount"; then
    echo "[*] systemd tmp.mount detected — configuring size via drop-in..."
    mkdir -p /etc/systemd/system/tmp.mount.d
    cat > /etc/systemd/system/tmp.mount.d/build-size.conf << EOF
[Mount]
Options=size=${TMPFS_SIZE},mode=1777
EOF
    systemctl daemon-reload
    systemctl restart tmp.mount || true

    cat << 'EOF' >> "$UNDO_FILE"
echo "  - Removing systemd tmp.mount size drop-in..."
rm -f /etc/systemd/system/tmp.mount.d/build-size.conf
systemctl daemon-reload
EOF
  else
    sed -i '/[[:space:]]\/tmp[[:space:]]tmpfs/d' /etc/fstab
    FSTAB_LINE_TMP="tmpfs /tmp tmpfs size=${TMPFS_SIZE},mode=1777 0 0"
    echo "${FSTAB_LINE_TMP}" >> /etc/fstab
    mountpoint -q /tmp || mount /tmp || true
  fi
else
  echo "[*] tmpfs on /tmp skipped for ${RAM_GB} GB RAM tier — /tmp remains on disk."
  # Remove any tmpfs /tmp entry a previous run of this script may have written.
  sed -i '/[[:space:]]\/tmp[[:space:]]tmpfs/d' /etc/fstab
fi

# Swapfile fstab: remove any existing line and unconditionally re-add the
# canonical form with explicit low priority (pri=10). ZRAM via zram-generator
# gets priority 100 by default; pri=10 ensures the kernel exhausts ZRAM
# before touching the disk, making it a true last-resort safety net.
sed -i '/^\/swapfile/d' /etc/fstab
FSTAB_LINE_SWAP="/swapfile none swap sw,pri=10 0 0"
echo "${FSTAB_LINE_SWAP}" >> /etc/fstab

# ─── 11. Swapfile ─────────────────────────────────────────────────────────────
# Strategy: grow-not-shrink. If no swapfile exists, create at SWAP_SIZE. If one
# exists but is smaller, rebuild it larger. If it already meets the target, leave
# it untouched and ensure it is active.
#
# Priority: explicit pri=10 via swapon (-p 10 below). The disk swapfile is the
# safety net beneath ZRAM; it should only be reached under genuine memory
# exhaustion, not as a first-resort performance trade.
#
# btrfs: fallocate creates a CoW-backed file that mkswap rejects. We detect
# btrfs on the root fs and force dd in that case. dd is slower but correct.
SWAP_TARGET_BYTES=$(( ${SWAP_SIZE%G} * 1024 * 1024 * 1024 ))
CURRENT_SWAP_BYTES=0
[ -f /swapfile ] && CURRENT_SWAP_BYTES=$(stat -c %s /swapfile 2>/dev/null || echo 0)

ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
if [ "${ROOT_FS}" = "btrfs" ]; then
  SWAPFILE_USE_DD=1
  echo "[*] btrfs root filesystem detected — using dd for swapfile (fallocate on btrfs creates a CoW file that mkswap rejects)."
elif command -v fallocate >/dev/null 2>&1; then
  SWAPFILE_USE_DD=0
else
  SWAPFILE_USE_DD=1
fi

provision_swapfile() {
  local size_str="$1"
  local mb_count
  mb_count=$(( ${size_str%G} * 1024 ))
  if [ "${SWAPFILE_USE_DD}" -eq 1 ]; then
    echo "[*] Provisioning swapfile via dd (${size_str}) — this may take a while..."
    dd if=/dev/zero of=/swapfile bs=1M count="${mb_count}" status=progress
  else
    echo "[*] Provisioning swapfile via fallocate (${size_str})..."
    fallocate -l "${size_str}" /swapfile
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon -p 10 /swapfile
}

if [ "${CURRENT_SWAP_BYTES}" -lt "${SWAP_TARGET_BYTES}" ]; then
  if [ -f /swapfile ]; then
    echo "[*] Existing swapfile ($(( CURRENT_SWAP_BYTES / 1024 / 1024 / 1024 )) GB) is below target ${SWAP_SIZE} — rebuilding larger..."
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile
  fi
  provision_swapfile "${SWAP_SIZE}"

  cat << 'EOF' >> "$UNDO_FILE"
echo "  - Deactivating and removing swapfile..."
swapoff /swapfile || true
rm -f /swapfile
EOF
else
  echo "[*] Existing swapfile ($(( CURRENT_SWAP_BYTES / 1024 / 1024 / 1024 )) GB) already meets target ${SWAP_SIZE} — leaving as is."
  swapon --show 2>/dev/null | grep -q "/swapfile" || swapon -p 10 /swapfile 2>/dev/null || true
fi

# ─── 12. ZRAM Configuration ───────────────────────────────────────────────────
echo "[*] Configuring ZRAM compressed swap device..."
ZRAM_CONF="/etc/systemd/zram-generator.conf"

if [ -f "$ZRAM_CONF" ]; then
  cat "$ZRAM_CONF" > "${ZRAM_CONF}.bak.${TIMESTAMP}"
  cat << EOF >> "$UNDO_FILE"
if [ -f "${ZRAM_CONF}.bak.${TIMESTAMP}" ]; then
  mv "${ZRAM_CONF}.bak.${TIMESTAMP}" "$ZRAM_CONF"
else
  rm -f "$ZRAM_CONF"
fi
EOF
else
  cat << EOF >> "$UNDO_FILE"
rm -f "$ZRAM_CONF"
EOF
fi

ZRAM_READY=0
if [ -e /usr/lib/systemd/system-generators/zram-generator ] || \
   [ -e /lib/systemd/system-generators/zram-generator ]; then
  ZRAM_READY=1
else
  echo "[*] systemd zram-generator not present — installing..."
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-zram-generator \
      && ZRAM_READY=1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y zram-generator && ZRAM_READY=1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm zram-generator && ZRAM_READY=1
  fi
  if [ "${ZRAM_READY}" -ne 1 ]; then
    echo "[!] Could not install the zram-generator package automatically."
    echo "    ZRAM will not activate until it is installed."
  fi
fi

# zram-size MUST be a plain integer (MiB) or an expression like "ram / 2".
# String suffixes like "4G" are not valid tokens and are silently ignored,
# resulting in no ZRAM device with no visible error. This was the original bug.
cat > "${ZRAM_CONF}" << EOF
[zram0]
zram-size = ${ZRAM_SIZE_MIB}
compression-algorithm = zstd
EOF

cat << 'EOF' >> "$UNDO_FILE"
echo "  - Deactivating ZRAM swap device..."
systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true
swapoff /dev/zram0 2>/dev/null || true
systemctl daemon-reload || true
EOF

if [ "${ZRAM_READY}" -eq 1 ]; then
  modprobe zram 2>/dev/null || true
  systemctl daemon-reload || true
  if systemctl restart systemd-zram-setup@zram0.service 2>/dev/null \
     && swapon --show | grep -q zram; then
    echo "[*] ZRAM device active: $(swapon --show | awk '/zram/{print $1, $3}')"
  else
    echo "[~] ZRAM is configured (${ZRAM_SIZE_MIB} MiB) but could not activate right now."
    echo "    Most likely cause: insufficient free RAM at this moment. Close any running"
    echo "    builds or emulators and re-run, or just reboot. ZRAM activates on the next"
    echo "    boot once RAM is available. The swapfile covers swap in the meantime."
  fi
fi

# ─── 13. sysctl Kernel Tuning ─────────────────────────────────────────────────
# Swappiness rationale (counterintuitive with ZRAM):
#   Higher swappiness tells the kernel to prefer moving anonymous memory (idle
#   JVM heap pages) into swap before evicting the file (page) cache. Without
#   ZRAM this is bad — swap is slow disk. With ZRAM as the primary swap target,
#   it is correct: the kernel pushes idle heap into fast compressed ZRAM,
#   keeping physical RAM available for active computation and the file cache that
#   build tooling reads repeatedly. The original script had LOW swappiness on
#   LOW RAM, which is the opposite of the right choice for a ZRAM setup.
#
# vfs_cache_pressure rationale:
#   Lower values make the kernel retain dentry/inode metadata longer. Android
#   builds access thousands of small files repeatedly; retaining their filesystem
#   metadata in cache reduces repeated directory lookups. With ZRAM handling heap
#   pressure, we can afford lower vfs_cache_pressure even on tight machines.
#   The original had HIGH values (80) on LOW RAM, which is also backwards.
#
# Note on practical impact: swappiness and vfs_cache_pressure tuning is
# acknowledged by reviewers as providing modest build time improvement (GPT:
# "mostly placebo"; Deepseek: "unlikely to noticeably affect build times").
# The values here are defensible and correct, but not transformative.
echo "[*] Applying kernel parameter tuning via sysctl..."
SYSCTL_CONF="/etc/sysctl.d/99-build-optim.conf"

MANAGED_SYSCTL_KEYS=(
  vm.swappiness
  vm.vfs_cache_pressure
  fs.inotify.max_user_watches
  fs.inotify.max_user_instances
  fs.file-max
)

cat << EOF >> "$UNDO_FILE"
echo "  - Removing build sysctl config..."
rm -f "${SYSCTL_CONF}"
sysctl --system || true
EOF

# Neutralise any conflicts in /etc/sysctl.conf. That file is applied LAST by
# sysctl --system (after all /etc/sysctl.d/*.conf files), silently overriding
# our drop-in on every boot regardless of numeric prefix.
if [ -f /etc/sysctl.conf ]; then
  SYSCTL_CONF_CONFLICT=0
  for key in "${MANAGED_SYSCTL_KEYS[@]}"; do
    if grep -qE "^[[:space:]]*${key//./\\.}[[:space:]]*=" /etc/sysctl.conf; then
      SYSCTL_CONF_CONFLICT=1
      break
    fi
  done

  if [ "${SYSCTL_CONF_CONFLICT}" -eq 1 ]; then
    echo "[*] /etc/sysctl.conf sets keys this script manages — neutralising conflicts..."
    cp /etc/sysctl.conf "/etc/sysctl.conf.bak.${TIMESTAMP}"
    echo "[*] Backed up to: /etc/sysctl.conf.bak.${TIMESTAMP}"

    cat << EOF >> "$UNDO_FILE"
echo "  - Restoring original /etc/sysctl.conf..."
if [ -f "/etc/sysctl.conf.bak.${TIMESTAMP}" ]; then
  mv "/etc/sysctl.conf.bak.${TIMESTAMP}" /etc/sysctl.conf
fi
sysctl --system || true
EOF

    for key in "${MANAGED_SYSCTL_KEYS[@]}"; do
      key_esc="${key//./\\.}"
      sed -i -E \
        "s|^([[:space:]]*${key_esc}[[:space:]]*=.*)$|# [build-optim] superseded by ${SYSCTL_CONF}: \1|" \
        /etc/sysctl.conf
    done
  fi
fi

cat > "${SYSCTL_CONF}" << EOF
# Build environment kernel parameters
# See changelog for rationale on swappiness and vfs_cache_pressure direction.
vm.swappiness=${SYS_SWAPPINESS}
vm.vfs_cache_pressure=${SYS_VFS}
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
fs.file-max=2097152
EOF
sysctl --system || true

# ─── 14. I/O Scheduler and Read-Ahead (udev) ──────────────────────────────────
# Acknowledged limitation: I/O scheduler tuning is largely irrelevant on modern
# NVMe and SATA SSDs — gains are 0-1% and modern kernels already select sensible
# defaults (GPT, Deepseek). These rules are retained because they do matter for
# HDDs and eMMC, and because setting them explicitly prevents regressions from
# kernel upgrades changing defaults.
#
# read_ahead_kb values are deliberately conservative. Android builds are
# random-read-heavy (thousands of small class files, XML resources, dex chunks).
# Large read-ahead windows waste cache space and add latency on random workloads.
# GPT: "not evidence-based for this workload."
echo "[*] Writing device-type-aware I/O optimisation rules (udev)..."
UDEV_RULE="/etc/udev/rules.d/60-io-scheduler.rules"

cat << EOF >> "$UNDO_FILE"
echo "  - Removing I/O scheduler udev rules..."
rm -f "${UDEV_RULE}"
udevadm control --reload
EOF

cat > "${UDEV_RULE}" << 'EOF'
# NVMe: passthrough — NVMe manages its own internal queue; none is already the
# kernel default on most systems. 128 KB read-ahead: minimal, suits random reads.
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="128"
# SATA SSD: mq-deadline, 256 KB read-ahead (reduced from 2048 KB in original;
# SSDs do not benefit from large read-ahead on random-access build workloads).
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="256"
# SATA HDD: mq-deadline, 2048 KB read-ahead. HDDs benefit meaningfully from
# sequential prefetch; 2 MB is a practical ceiling for mixed workloads.
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="2048"
# eMMC: mq-deadline, 256 KB read-ahead (flash storage; conservative prefetch).
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="256"
# virtio-blk: mq-deadline, 256 KB (VM; host storage handles its own caching).
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/read_ahead_kb}="256"
EOF

udevadm control --reload
udevadm trigger --action=change "/dev/${DISK_PARENT}" || true
# blockdev --setra intentionally absent. It takes 512-byte sectors, not KB;
# calling it after the udev trigger would silently overwrite the rule's value.

# ─── 15. Per-User Resource Limits ─────────────────────────────────────────────
echo "[*] Writing per-user resource limits..."
LIMITS_FILE="/etc/security/limits.d/99-${TARGET_USER}-build.conf"

cat << EOF >> "$UNDO_FILE"
echo "  - Removing user resource limit file..."
rm -f "${LIMITS_FILE}"
EOF

cat > "${LIMITS_FILE}" << EOF
# Build resource limits for ${TARGET_USER}
# nofile: 262,144 — covers Gradle + Dart file watcher file descriptor usage
#          with comfortable headroom. The original value (1,048,576) was
#          indefensible and flagged by all three AI reviews. 256 K is the
#          practical ceiling recommended for build environments.
# nproc : 65,536  — prevents runaway fork bombs or OOM from crashed parallel
#          compilation while allowing aggressive concurrent builds.
${TARGET_USER} soft nofile 262144
${TARGET_USER} hard nofile 262144
${TARGET_USER} soft nproc  65536
${TARGET_USER} hard nproc  65536
EOF

# ─── 16. User Shell Environment (~/.bashrc) ───────────────────────────────────
echo "[*] Injecting build environment variables into ~/.bashrc..."
BASHRC_FILE="${TARGET_HOME}/.bashrc"

touch "${BASHRC_FILE}"
chown "${TARGET_USER}:${TARGET_USER}" "${BASHRC_FILE}"

cat << EOF >> "$UNDO_FILE"
echo "  - Removing build environment block from .bashrc..."
sed -i '/# ANDROID BUILD VARIABLES START/,/# ANDROID BUILD VARIABLES END/d' "${BASHRC_FILE}"
echo "Shell restore complete. Close and reopen any active shell sessions."
EOF

sed -i '/# ANDROID BUILD VARIABLES START/,/# ANDROID BUILD VARIABLES END/d' "${BASHRC_FILE}"

# Single-quoted heredoc: ${HOME} and ${PUB_CACHE} expand at shell runtime per
# the active user, not at install time under root context.
cat << 'EOF' >> "${BASHRC_FILE}"
# ANDROID BUILD VARIABLES START
export GRADLE_USER_HOME="${HOME}/.gradle"
export PUB_CACHE="${HOME}/.pub-cache"
# ANDROID BUILD VARIABLES END
EOF

# ─── 17. kvm Group Membership (Android Emulator Support) ──────────────────────
# Determine the actual device group of /dev/kvm rather than assuming "kvm".
# Some distros use libvirt, qemu, or vboxusers. (Deepseek review)
if [ -e /dev/kvm ]; then
  KVM_GROUP=$(stat -c '%G' /dev/kvm 2>/dev/null || echo "kvm")
  if getent group "${KVM_GROUP}" > /dev/null 2>&1; then
    echo "[*] Adding ${TARGET_USER} to '${KVM_GROUP}' group (/dev/kvm device group)..."
    usermod -aG "${KVM_GROUP}" "${TARGET_USER}"
    cat << EOF >> "$UNDO_FILE"
echo "  - Removing ${TARGET_USER} from ${KVM_GROUP} group..."
gpasswd -d "${TARGET_USER}" "${KVM_GROUP}" || true
EOF
  else
    echo "[~] /dev/kvm exists but its group ('${KVM_GROUP}') was not found in /etc/group."
  fi
else
  echo "[~] /dev/kvm not found — KVM hardware acceleration unavailable."
  echo "    Ensure KVM kernel modules are loaded: modprobe kvm_intel  (or kvm_amd)"
  echo "    Then re-run this script to add ${TARGET_USER} to the device group."
fi

# ─── 18. Verification Pass ────────────────────────────────────────────────────
# Note: flutter doctor has been removed from this pass. It is not related to
# build optimisation, is slow, and can fail due to SDK issues unrelated to
# anything this script controls. (GPT review)
echo " "
echo "=========================================="
echo " Post-Installation Verification"
echo "=========================================="

VERIFY_FAIL=0

# tmpfs (only relevant for >= 16 GB tiers)
if [ "${TMPFS_SIZE}" != "disabled" ]; then
  if findmnt -n -t tmpfs /tmp > /dev/null; then
    echo "[✓] /tmp is actively mounted as tmpfs (${TMPFS_SIZE})"
  else
    echo "[✗] /tmp is NOT mounted as tmpfs"
    VERIFY_FAIL=1
  fi
else
  echo "[✓] /tmp tmpfs deliberately disabled for ${RAM_GB} GB tier"
fi

# Swapfile
if swapon --show | grep -q "/swapfile"; then
  SWAP_PRI=$(swapon --show --raw | awk '/\/swapfile/{print $4}')
  echo "[✓] Swapfile is active (priority: ${SWAP_PRI:-unknown})"
else
  echo "[✗] Swapfile is NOT active"
  VERIFY_FAIL=1
fi

# ZRAM
if swapon --show | grep -q "zram"; then
  ZRAM_INFO=$(swapon --show | awk '/zram/{print $1, $3}')
  echo "[✓] ZRAM swap is active: ${ZRAM_INFO}"
elif [ ! -e /usr/lib/systemd/system-generators/zram-generator ] && \
     [ ! -e /lib/systemd/system-generators/zram-generator ]; then
  echo "[✗] ZRAM inactive: systemd-zram-generator package is not installed"
  VERIFY_FAIL=1
else
  echo "[~] ZRAM configured (${ZRAM_SIZE_MIB} MiB) but not active yet — activates on next reboot"
  echo "    The swapfile covers swap in the meantime."
fi

# vm.swappiness
ACTUAL_SWAPPINESS=$(sysctl -n vm.swappiness)
if [ "${ACTUAL_SWAPPINESS}" -eq "${SYS_SWAPPINESS}" ]; then
  echo "[✓] vm.swappiness = ${ACTUAL_SWAPPINESS}"
else
  echo "[✗] vm.swappiness = ${ACTUAL_SWAPPINESS} (expected ${SYS_SWAPPINESS})"
  VERIFY_FAIL=1
fi

# vm.vfs_cache_pressure
ACTUAL_VFS=$(sysctl -n vm.vfs_cache_pressure)
if [ "${ACTUAL_VFS}" -eq "${SYS_VFS}" ]; then
  echo "[✓] vm.vfs_cache_pressure = ${ACTUAL_VFS}"
else
  echo "[✗] vm.vfs_cache_pressure = ${ACTUAL_VFS} (expected ${SYS_VFS})"
  VERIFY_FAIL=1
fi

# I/O scheduler: extract the active [bracketed] value and compare.
SCHED_PATH="/sys/block/${DISK_PARENT}/queue/scheduler"
if [ -f "${SCHED_PATH}" ]; then
  ACTIVE_SCHED=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "${SCHED_PATH}")
  if [ "${ACTIVE_SCHED}" = "${IO_SCHEDULER}" ]; then
    echo "[✓] I/O scheduler (${DISK_PARENT}): active=${ACTIVE_SCHED}"
  else
    echo "[✗] I/O scheduler (${DISK_PARENT}): active=${ACTIVE_SCHED} (expected ${IO_SCHEDULER})"
    echo "    Full scheduler file: $(cat "${SCHED_PATH}")"
    VERIFY_FAIL=1
  fi
else
  echo "[~] Scheduler sysfs path not readable at ${SCHED_PATH} (device type: ${DISK_TYPE})"
fi

# read_ahead_kb
RA_PATH="/sys/block/${DISK_PARENT}/queue/read_ahead_kb"
if [ -f "${RA_PATH}" ]; then
  echo "[✓] read_ahead_kb (${DISK_PARENT}): $(cat "${RA_PATH}")"
else
  echo "[~] read_ahead_kb sysfs path not readable at ${RA_PATH}"
fi

# Per-user resource limits
if grep -q "nofile" "${LIMITS_FILE}" 2>/dev/null; then
  echo "[✓] Per-user resource limits written (effective on next login)"
else
  echo "[✗] Per-user limits file is missing expected nofile content"
  VERIFY_FAIL=1
fi

# gradle.properties: check all managed keys
if grep -q "org.gradle.daemon=true"            "${GRADLE_PROPS}" && \
   grep -q "org.gradle.caching=true"           "${GRADLE_PROPS}" && \
   grep -q "org.gradle.parallel=${GRADLE_PARALLEL}" "${GRADLE_PROPS}" && \
   grep -q "org.gradle.daemon.idletimeout"     "${GRADLE_PROPS}" && \
   grep -q "org.gradle.workers.max"            "${GRADLE_PROPS}" && \
   grep -q "kotlin.daemon.jvm.options"         "${GRADLE_PROPS}" && \
   grep -q "G1PeriodicGCInterval"              "${GRADLE_PROPS}" && \
   grep -q "ExitOnOutOfMemoryError"            "${GRADLE_PROPS}"; then
  echo "[✓] gradle.properties: daemon, caching, parallel=${GRADLE_PARALLEL}, idletimeout,"
  echo "    workers.max=${GRADLE_WORKERS}, G1PeriodicGCInterval, ExitOnOOM, Kotlin heap"
  echo "    Gradle JVM max heap:  ${GRADLE_JVM_MAX}"
  echo "    Kotlin daemon heap:   ${KOTLIN_JVM_MAX}"
else
  echo "[✗] gradle.properties is missing one or more expected entries"
  VERIFY_FAIL=1
fi

# ~/.pub-cache
if [ -d "${TARGET_HOME}/.pub-cache" ]; then
  echo "[✓] ~/.pub-cache directory is present"
else
  echo "[✗] ~/.pub-cache directory is missing"
  VERIFY_FAIL=1
fi

# kvm
if [ -e /dev/kvm ]; then
  KVM_GRP=$(stat -c '%G' /dev/kvm 2>/dev/null || echo "kvm")
  if id -nG "${TARGET_USER}" | grep -qw "${KVM_GRP}"; then
    echo "[✓] ${TARGET_USER} is in the '${KVM_GRP}' group (effective on next login)"
  else
    echo "[~] ${TARGET_USER} is not in '${KVM_GRP}' — emulator hardware acceleration unavailable"
  fi
else
  echo "[~] /dev/kvm not present — KVM unavailable (check kernel module)"
fi

# ─── 19. Finalise and Set Recovery File Permissions ───────────────────────────
chmod +x "$UNDO_FILE"
chown "${TARGET_USER}:${TARGET_USER}" "$UNDO_FILE"

echo " "
if [ "${VERIFY_FAIL}" -eq 0 ]; then
  echo "[✓] All critical verifications passed."
else
  echo "[!] One or more critical verifications failed. Review output above before proceeding."
fi

echo "==============================================================="
echo " Build Environment Optimisation Complete"
echo "==============================================================="
echo " User:                  ${TARGET_USER}"
echo " RAM bracket:           ${RAM_GB} GB"
echo " ZRAM:                  ${ZRAM_SIZE_MIB} MiB (primary swap, priority 100)"
echo " Swapfile:              ${SWAP_SIZE} (safety net, priority 10)"
echo " vm.swappiness:         ${SYS_SWAPPINESS}"
echo " vm.vfs_cache_pressure: ${SYS_VFS}"
echo " Gradle JVM heap:       ${GRADLE_JVM_MAX}"
echo " Gradle workers.max:    ${GRADLE_WORKERS}"
echo " Gradle parallel:       ${GRADLE_PARALLEL}"
echo " Kotlin daemon heap:    ${KOTLIN_JVM_MAX}"
echo " Daemon idle timeout:   600000 ms (10 min)"
echo " Device:                ${DISK_TYPE} (${DISK_PARENT}), scheduler=${IO_SCHEDULER}"
if [ "${TMPFS_SIZE}" = "disabled" ]; then
  echo " tmpfs /tmp:            disabled"
else
  echo " tmpfs /tmp:            ${TMPFS_SIZE}"
fi
echo " "
echo " Next steps:"
echo "   1. Reboot to fully activate ZRAM, kernel params, and group membership."
echo "   2. Test configuration cache compatibility before enabling it globally:"
echo "      cd <your-project> && ./gradlew --configuration-cache assembleDebug"
echo "      If successful, uncomment org.gradle.configuration-cache=true in:"
echo "      ${GRADLE_PROPS}"
echo " "
echo " To undo all changes:"
echo "   sudo ${UNDO_FILE}"
echo "==============================================================="
echo " "

read -rp "A restart is recommended to fully apply kernel parameters. Reboot now? (y/N): " REBOOT_ANSWER
if [[ "${REBOOT_ANSWER}" =~ ^[Yy]$ ]]; then
  echo "Rebooting..."
  reboot
fi