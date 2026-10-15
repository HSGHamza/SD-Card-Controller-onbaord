#!/bin/bash
# ==============================================================================
# F4PGA Open-Source Build Script for Digilent Zybo Z7-10 (XC7Z010-1CLG400C)
# 100% Pure Verilog - No Vivado, No Vitis, No ARM PS needed!
# ==============================================================================

set -e

PROJECT="rv32i_sd_pure_top"
PART="xc7z010"
PACKAGE="clg400-1"
OUT_DIR="./build_f4pga"

echo "=========================================================="
echo "==> Building 100% Pure Verilog RV32I + SD Bitstream with F4PGA"
echo "==> Target Part: ${PART}-${PACKAGE} (Zybo Z7-10)"
echo "=========================================================="

mkdir -p ${OUT_DIR}

# Copy instruction memory hex file to build directory
cp ./rv32i/instructions.hex ${OUT_DIR}/instructions.hex
cp ./rv32i/instructions.hex ./instructions.hex

# 1. Synthesis with Yosys
echo "==> Step 1: Synthesizing with Yosys..."
yosys -p "
    read_verilog -sv rv32i/ProgramCounter.v \
                     rv32i/instructionMemory.v \
                     rv32i/decoder.v \
                     rv32i/ControlLogic.v \
                     rv32i/RegFile.v \
                     rv32i/RI_alu.v \
                     rv32i/bAlu.v \
                     rv32i/alu.v \
                     rv32i/dataMemory.v \
                     rv32i/immTo32.v \
                     rv32i/Datapath.v \
                     rtl/sd_spi_controller.v \
                     rtl/rv32i_sd_pure_top.v
    synth_xilinx -top ${PROJECT} -edif ${OUT_DIR}/${PROJECT}.edif -json ${OUT_DIR}/${PROJECT}.json
" > ${OUT_DIR}/yosys_synth.log

echo "==> Synthesis completed successfully!"

# 2. Place & Route (F4PGA / NextPNR-Xilinx or VPR)
if command -v nextpnr-xilinx &> /dev/null; then
    echo "==> Step 2: Place & Route with NextPNR-Xilinx..."
    nextpnr-xilinx --chipdb ${F4PGA_SHARE_DIR}/arch/xc7z010.bin \
                   --xdc constraints/zybo_z7_pure.xdc \
                   --json ${OUT_DIR}/${PROJECT}.json \
                   --fasm ${OUT_DIR}/${PROJECT}.fasm
elif command -v f4pga &> /dev/null; then
    echo "==> Step 2: Running F4PGA toolchain..."
    f4pga build --flow xilinx --part ${PART}
else
    echo "==> Note: Yosys synthesis JSON/EDIF generated at ${OUT_DIR}/${PROJECT}.json"
    echo "    Run your local F4PGA / NextPNR PnR step to generate the final .fasm & .bit file."
fi

# 3. Bitstream Generation
if command -v xc7frames2bit &> /dev/null; then
    echo "==> Step 3: Generating bitstream (.bit)..."
    xc7frames2bit --part_file ${F4PGA_SHARE_DIR}/xc7z010.yaml \
                  --fasm_file ${OUT_DIR}/${PROJECT}.fasm \
                  --bit_file ./${PROJECT}.bit
    echo "=========================================================="
    echo ">>> SUCCESS: Bitstream generated at ./${PROJECT}.bit <<<"
    echo "=========================================================="
fi

