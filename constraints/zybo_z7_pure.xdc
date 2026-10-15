# ==============================================================================
# Constraints file for Digilent Zybo Z7-10 (XC7Z010-1CLG400C)
# Target: rv32i_sd_pure_top (100% Pure Verilog / F4PGA compatible)
# ==============================================================================

# 125 MHz System Clock & Reset Button
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clk }];

set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn0 }]; # Active High Reset

# MicroSD SPI Interface (Digilent Pmod JE)
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { sd_cs_n }]; # Pmod JE Pin 1 (CS)
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports { sd_mosi }]; # Pmod JE Pin 2 (MOSI)
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sd_miso }]; # Pmod JE Pin 3 (MISO)
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { sd_sclk }]; # Pmod JE Pin 4 (SCK)
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { sd_cd }];   # Pmod JE Pin 9 (CD)

# User LEDs (Active High)
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; # LD0: Heartbeat / Ready
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; # LD1: SD Controller BUSY
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; # LD2: SD Sector Read DONE
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; # LD3: MBR (0x55AA) Verified by RV32!

