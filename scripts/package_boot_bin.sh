#!/usr/bin/env bash
# =============================================================================
# package_boot_bin.sh
# Packages FSBL + bitstream + ARM ELF into BOOT.BIN using bootgen.
#
# Usage:
#   ./scripts/package_boot_bin.sh
#
# Prerequisites:
#   - fsbl/fsbl.elf              (built by scripts/build_fsbl.tcl, ONCE)
#   - zybo_rv32i_sd.bit          (built by vivado scripts/build_zybo_project.tcl)
#   - arm_firmware/build/sd_mailbox_server.elf  (built by scripts/build_arm_firmware.sh)
#   - bootgen in PATH
#     Location: <Vivado_install>/bin/bootgen   OR   <Vitis_install>/bin/bootgen
#     Add to PATH: export PATH=$PATH:/tools/Xilinx/Vivado/2023.1/bin
#
# Output: BOOT.BIN  (program this to QSPI flash)
# =============================================================================

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ_ROOT"

# ---- Check dependencies ----
check_file() {
    if [[ ! -f "$1" ]]; then
        echo "ERROR: Missing $1"
        echo "  $2"
        exit 1
    fi
}

check_file "fsbl/fsbl.elf" \
    "Run: xsct scripts/build_fsbl.tcl  (one-time step)"

check_file "zybo_rv32i_sd.bit" \
    "Run: vivado -mode batch -source scripts/build_zybo_project.tcl"

check_file "arm_firmware/build/sd_mailbox_server.elf" \
    "Run: ./scripts/build_arm_firmware.sh"

# ---- Find bootgen ----
BOOTGEN="${BOOTGEN:-bootgen}"
if ! command -v "$BOOTGEN" &>/dev/null; then
    # Try common Vivado locations
    for dir in \
        /tools/Xilinx/Vivado/2023.2/bin \
        /tools/Xilinx/Vivado/2023.1/bin \
        /tools/Xilinx/Vivado/2022.2/bin \
        /opt/Xilinx/Vivado/2023.2/bin \
        /opt/Xilinx/Vivado/2023.1/bin; do
        if [[ -x "$dir/bootgen" ]]; then
            BOOTGEN="$dir/bootgen"
            break
        fi
    done
fi

if ! command -v "$BOOTGEN" &>/dev/null; then
    echo "ERROR: bootgen not found!"
    echo "  Add Vivado bin/ to PATH:  export PATH=\$PATH:/tools/Xilinx/Vivado/2023.1/bin"
    echo "  Or set: BOOTGEN=/full/path/to/bootgen"
    exit 1
fi

echo "========================================================"
echo "  Packaging BOOT.BIN"
echo "  bootgen: $BOOTGEN"
echo "========================================================"

echo "[IN] fsbl/fsbl.elf"
echo "[IN] zybo_rv32i_sd.bit"
echo "[IN] arm_firmware/build/sd_mailbox_server.elf"

"$BOOTGEN" \
    -image boot.bif \
    -arch zynq \
    -w on \
    -o BOOT.BIN

echo ""
echo "========================================================"
ls -lh BOOT.BIN
echo ""
echo "  SUCCESS: BOOT.BIN created!"
echo ""
echo "  Next step — Program to QSPI Flash:"
echo "    ./scripts/program_qspi.sh"
echo "  OR using Vivado TCL:"
echo "    vivado -mode batch -source scripts/program_qspi.tcl"
echo "========================================================"

