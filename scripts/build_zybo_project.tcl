# ==============================================================================
# Vivado TCL Automation Script: Build Zybo Z7-10 RV32I + SD Bitstream
#
# Usage (Run directly from shell in project directory):
#   vivado -mode batch -source scripts/build_zybo_project.tcl
# Or inside Vivado GUI TCL Console:
#   source scripts/build_zybo_project.tcl
# ==============================================================================

set proj_name "zybo_rv32i_sd"
set proj_dir  "./vivado_zybo"
set part      "xc7z010clg400-1"

puts "=========================================================="
puts "==> Step 1: Creating Vivado Project: $proj_name for $part"
puts "=========================================================="
create_project $proj_name $proj_dir -part $part -force

# 1. Add all Verilog RTL Sources & Instructions Hex
add_files -norecurse [glob ./rv32i/*.v]
add_files -norecurse [glob ./rtl/*.v]
add_files -norecurse "./rv32i/instructions.hex"
add_files -fileset constrs_1 -norecurse "./constraints/zybo_z7.xdc"
update_compile_order -fileset sources_1

# 2. Create Block Design for Processing System (PS7)
puts "=========================================================="
puts "==> Step 2: Configuring Zynq PS (SDIO 0, UART 1, DDR, AXI)"
puts "=========================================================="
set bd_name "system"
create_bd_design $bd_name
current_bd_design $bd_name

set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]

# Apply Zybo Z7-10 PS Configuration
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 47} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} \
] $ps7

# Make PS ports external to connect to zybo_rv32_sd_top
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_pins_external [get_bd_pins ps7/FCLK_CLK0]
make_bd_pins_external [get_bd_pins ps7/FCLK_RESET0_N]
make_bd_intf_pins_external [get_bd_intf_pins ps7/M_AXI_GP0]
make_bd_pins_external [get_bd_pins ps7/IRQ_F2P]

# Connect PS ACLK to FCLK_CLK0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]

# Validate and Save BD
validate_bd_design
save_bd_design

# 3. Generate Block Design Products & Wrapper
puts "=========================================================="
puts "==> Step 3: Generating Block Design Products"
puts "=========================================================="
generate_target all [get_files [get_property FILE_NAME [get_bd_designs $bd_name]]]
make_wrapper -files [get_files [get_property FILE_NAME [get_bd_designs $bd_name]]] -top
add_files -norecurse "$proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v"
update_compile_order -fileset sources_1

# Set zybo_rv32_sd_top as synthesis top
set_property top zybo_rv32_sd_top [current_fileset]
update_compile_order -fileset sources_1

# 4. Run Synthesis, Implementation, and Generate Bitstream
puts "=========================================================="
puts "==> Step 4: Running Synthesis & Implementation..."
puts "=========================================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

puts "==> Running Implementation & Bitstream Generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 5. Export Hardware XSA with Bitstream for Vitis
puts "=========================================================="
puts "==> Step 5: Exporting Hardware Platform (.xsa) with Bitstream"
puts "=========================================================="
file copy -force "$proj_dir/$proj_name.runs/impl_1/zybo_rv32_sd_top.bit" "./zybo_rv32i_sd.bit"
write_hw_platform -fixed -include_bit -force -file "./zybo_rv32i_sd.xsa"

puts "=========================================================="
puts ">>> SUCCESS: BITSTREAM & HARDWARE XSA GENERATED! <<<"
puts "Bitstream file: ./zybo_rv32i_sd.bit"
puts "Hardware XSA:   ./zybo_rv32i_sd.xsa"
puts "=========================================================="

