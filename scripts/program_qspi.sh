#!/usr/bin/env bash
# =============================================================================
# program_qspi.sh — Program BOOT.BIN into Zybo Z7-10 QSPI Flash
#
# Uses Vivado's program_flash utility (no Vitis needed, ships with Vivado).
#
# Usage:
#   ./scripts/program_qspi.sh
#
# Prerequisites:
#   - Zybo Z7-10 connected via USB JTAG (Digilent HS2 or onboard FTDI)
#   - Zybo powered on
#   - BOOT.BIN built by scripts/package_boot_bin.sh
#   - Vivado in PATH (for program_flash)
#
# After programming:
#   1. Set JP5 to QSPI mode (pin 2-3)  — see README.md for jumper diagram
#   2. Power cycle or press SRST
#   3. ARM boots automatically, runs sd_mailbox_server
#   4. FPGA fabric configured by FSBL automatically
# =============================================================================

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ_ROOT"

BOOT_BIN="$PROJ_ROOT/BOOT.BIN"

if [[ ! -f "$BOOT_BIN" ]]; then
    echo "ERROR: BOOT.BIN not found. Run ./scripts/package_boot_bin.sh first."
    exit 1
fi

# Find program_flash
PF="${PROGRAM_FLASH:-program_flash}"
if ! command -v "$PF" &>/dev/null; then
    for dir in \
        /tools/Xilinx/Vivado/2023.2/bin \
        /tools/Xilinx/Vivado/2023.1/bin \
        /tools/Xilinx/Vivado/2022.2/bin \
        /opt/Xilinx/Vivado/2023.2/bin; do
        if [[ -x "$dir/program_flash" ]]; then
            PF="$dir/program_flash"
            break
        fi
    done
fi

if ! command -v "$PF" &>/dev/null; then
    echo "ERROR: program_flash not found. Add Vivado bin/ to PATH."
    exit 1
fi

echo "========================================================"
echo "  Programming QSPI Flash on Zybo Z7-10"
echo "  program_flash: $PF"
echo "  Image: $BOOT_BIN ($(du -h "$BOOT_BIN" | cut -f1))"
echo "========================================================"
echo ""
echo "  Make sure Zybo is powered on and USB-JTAG is connected."
echo ""

# Zybo Z7-10 uses a Micron N25Q256 (32 MB, QSPI x4 single)
"$PF" \
    -f "$BOOT_BIN" \
    -offset 0 \
    -flash_type qspi-x4-single \
    -cable type digilent

echo ""
echo "========================================================"
echo "  QSPI Flash programmed successfully!"
echo ""
echo "  NEXT STEPS:"
echo "  1. Set jumper JP5 to QSPI mode (pins 2-3)"
echo "     JTAG mode = pins 1-2 (default from factory)"
echo "     QSPI mode = pins 2-3"
echo "  2. Power cycle the board (or press SRST button)"
echo "  3. Open UART terminal: 115200 baud 8N1"
echo "     Example: screen /dev/ttyUSB1 115200"
echo "     Or:      minicom -D /dev/ttyUSB1 -b 115200"
echo "  4. Watch ARM boot messages:"
echo "     [ARM-SD] Checking AXI SD Mailbox at 0x43C00000..."
echo "     [ARM-SD] Server running. Listening for RV32 sector requests..."
echo "========================================================"

