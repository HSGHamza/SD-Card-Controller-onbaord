# ==============================================================================
# Vivado TCL Script: Create Block Design for Zybo Z7-10 with SD Mailbox
# Usage:
#   vivado -mode batch -source scripts/create_bd.tcl
# or inside Vivado TCL console:
#   source scripts/create_bd.tcl
# ==============================================================================

set project_name "zybo_z7_sd_controller"
set project_dir  "./vivado_project"
set part_name    "xc7z010clg400-1"

# 1. Create or Open Project
if {[file exists $project_dir]} {
    puts "Opening existing project..."
    open_project "$project_dir/$project_name.xpr"
} else {
    puts "Creating project $project_name for $part_name..."
    create_project $project_name $project_dir -part $part_name
    set_property board_part digilentinc.com:zybo-z7-10:part0:1.1 [current_project]
}

# 2. Add RTL Sources
add_files -norecurse "./rtl/axi_sd_mailbox.v"
update_compile_order -fileset sources_1

# 3. Create Block Design
set bd_name "system"
create_bd_design $bd_name
current_bd_design $bd_name

# 4. Instantiate Processing System 7 (ARM Cortex-A9)
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]

# Configure Zybo Z7-10 PS peripherals: SDIO 0, UART 1, M_AXI_GP0, Clocking
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
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

# 5. Instantiate AXI SmartConnect / Interconnect (2 Slave ports: ARM + RV32)
set axi_intercon [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list \
    CONFIG.NUM_SI {2} \
    CONFIG.NUM_MI {1} \
] $axi_intercon

# 6. Instantiate Mailbox RTL Module
set sd_mailbox [create_bd_cell -type module -reference axi_sd_mailbox axi_sd_mailbox_0]

# 7. Instantiate Processor System Reset
set rst_gen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100M]

# 8. Connect Clocks & Resets
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_gen/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_intercon/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_intercon/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_intercon/S01_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_intercon/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins sd_mailbox/s_axi_aclk]

connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_gen/ext_reset_in]
connect_bd_net [get_bd_pins rst_gen/interconnect_aresetn] [get_bd_pins axi_intercon/ARESETN]
connect_bd_net [get_bd_pins rst_gen/peripheral_aresetn] [get_bd_pins axi_intercon/S00_ARESETN]
connect_bd_net [get_bd_pins rst_gen/peripheral_aresetn] [get_bd_pins axi_intercon/S01_ARESETN]
connect_bd_net [get_bd_pins rst_gen/peripheral_aresetn] [get_bd_pins axi_intercon/M00_ARESETN]
connect_bd_net [get_bd_pins rst_gen/peripheral_aresetn] [get_bd_pins sd_mailbox/s_axi_aresetn]

# 9. Connect AXI Buses
# Port S00: ARM Cortex-A9 Master GP0
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_intercon/S00_AXI]

# Port M00: Connect to Mailbox Slave
connect_bd_intf_net [get_bd_intf_pins axi_intercon/M00_AXI] [get_bd_intf_pins sd_mailbox/s_axi]

# Port S01: Make external for RV32 Core AXI Master connection
# (If your RV32 core is in the Block Design, connect RV32's M_AXI to axi_intercon/S01_AXI instead)
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_RV32
connect_bd_intf_net [get_bd_intf_pins axi_intercon/S01_AXI] [get_bd_intf_ports S_AXI_RV32]

# 10. Memory Address Mapping
create_bd_addr_seg -range 4K -offset 0x43C00000 \
    [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs sd_mailbox/s_axi/reg0] SEG_ps7_sd_mailbox

create_bd_addr_seg -range 4K -offset 0x43C00000 \
    [get_bd_addr_spaces S_AXI_RV32] \
    [get_bd_addr_segs sd_mailbox/s_axi/reg0] SEG_rv32_sd_mailbox

# 11. Validate and Generate Block Design
validate_bd_design
save_bd_design

# 12. Create HDL Wrapper
make_wrapper -files [get_files [get_property FILE_NAME [get_bd_designs $bd_name]]] -top
add_files -norecurse "$project_dir/$project_name.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v"
update_compile_order -fileset sources_1

puts "=========================================================="
puts "Block Design '$bd_name' successfully generated!"
puts "SD Mailbox mapped at 0x43C0_0000 for both ARM and RV32."
puts "=========================================================="

