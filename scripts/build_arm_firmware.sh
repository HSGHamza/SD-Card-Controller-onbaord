#!/usr/bin/env bash
# =============================================================================
# build_arm_firmware.sh
# Compile sd_mailbox_server.c into a standalone ARM ELF using arm-none-eabi-gcc
# NO Vitis, NO SDK, NO Xilinx BSP installation required.
#
# Usage:
#   chmod +x scripts/build_arm_firmware.sh
#   ./scripts/build_arm_firmware.sh
#
# Output:
#   arm_firmware/build/sd_mailbox_server.elf
#
# Prerequisites:
#   - arm-none-eabi-gcc (any version ≥ 9)
#     Install: sudo apt install gcc-arm-none-eabi  (Ubuntu/Debian)
#              sudo dnf install arm-none-eabi-gcc  (Fedora)
#              or download: https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
#
# =============================================================================

set -euo pipefail

# ---- Paths (relative to project root) ----
PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$PROJ_ROOT/arm_firmware/src"
BSP_DIR="$PROJ_ROOT/arm_firmware/bsp"
BUILD_DIR="$PROJ_ROOT/arm_firmware/build"

mkdir -p "$BUILD_DIR"

# ---- Toolchain ----
CC="${ARM_CC:-arm-none-eabi-gcc}"
OBJCOPY="${ARM_OBJCOPY:-arm-none-eabi-objcopy}"
OBJDUMP="${ARM_OBJDUMP:-arm-none-eabi-objdump}"
SIZE="${ARM_SIZE:-arm-none-eabi-size}"

# Verify toolchain is available
if ! command -v "$CC" &>/dev/null; then
    echo "ERROR: arm-none-eabi-gcc not found!"
    echo "  Install: sudo apt install gcc-arm-none-eabi"
    echo "  Or set ARM_CC=/path/to/arm-none-eabi-gcc"
    exit 1
fi

echo "========================================================"
echo "  Building ARM Cortex-A9 SD Mailbox Server"
echo "  Toolchain: $(${CC} --version | head -1)"
echo "========================================================"

# ---- Compiler Flags ----
# -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard  → match the A9's FPU
# -ffreestanding                                  → no hosted libc assumptions
# -nostartfiles                                   → we provide startup.c
# -nostdlib is NOT set — we link newlib (printf, etc.) from the toolchain
CFLAGS=(
    -mcpu=cortex-a9
    -mfpu=vfpv3
    -mfloat-abi=hard
    -marm                       # Force ARM (not Thumb) mode
    -O2
    -g3
    -Wall
    -Wextra
    -ffreestanding
    -fdata-sections
    -ffunction-sections
    -I"$BSP_DIR"                # Our hand-written BSP headers
    -I"$SRC_DIR"
)

LDFLAGS=(
    -mcpu=cortex-a9
    -mfpu=vfpv3
    -mfloat-abi=hard
    -marm
    -T "$BSP_DIR/zynq_a9.ld"   # Our linker script
    -nostartfiles               # We provide startup.c (reset_handler)
    -Wl,--gc-sections           # Remove unused sections
    -Wl,--print-memory-usage
    -lc                         # newlib libc (printf, memcpy, etc.)
    -lm                         # math library
    -lgcc                       # GCC runtime (soft-float helpers, etc.)
)

# ---- Source files to compile ----
SOURCES=(
    "$BSP_DIR/startup.c"        # Reset handler, UART _write, newlib stubs
    "$BSP_DIR/xsdps.c"          # Zynq PS SDIO driver (our implementation)
    "$SRC_DIR/sd_mailbox_server.c"  # Main ARM mailbox server
)

# ---- Compile each source to object ----
OBJECTS=()
for src in "${SOURCES[@]}"; do
    obj="$BUILD_DIR/$(basename "${src%.c}.o")"
    echo "[CC] $(basename "$src")"
    "$CC" "${CFLAGS[@]}" -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

# ---- Link ----
ELF="$BUILD_DIR/sd_mailbox_server.elf"
echo "[LD] Linking → $ELF"
"$CC" "${OBJECTS[@]}" "${LDFLAGS[@]}" -o "$ELF"

# ---- Print size ----
echo ""
echo "---- Section sizes ----"
"$SIZE" "$ELF"
echo ""

# ---- Generate binary (for reference / manual JTAG load) ----
BIN="$BUILD_DIR/sd_mailbox_server.bin"
"$OBJCOPY" -O binary "$ELF" "$BIN"
echo "[OK] ELF: $ELF"
echo "[OK] BIN: $BIN"

# ---- Optional: dump disassembly for debug ----
LST="$BUILD_DIR/sd_mailbox_server.lst"
"$OBJDUMP" -d "$ELF" > "$LST"
echo "[OK] Disassembly: $LST"

echo ""
echo "========================================================"
echo "  SUCCESS! ARM firmware built."
echo "  Next step: package into BOOT.BIN"
echo "    ./scripts/package_boot_bin.sh"
echo "========================================================"

