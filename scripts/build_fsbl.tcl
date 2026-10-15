# =============================================================================
# build_fsbl.tcl — Generate FSBL from XSA using Vitis XSCT (command-line only)
#
# This is the ONE-TIME step needed to get the FSBL ELF.
# After this you never need Vitis or XSCT again.
#
# Prerequisites:
#   - Vivado has already generated zybo_rv32i_sd.xsa  (via build_zybo_project.tcl)
#   - Vitis is installed (we use its XSCT command-line tool, not the GUI)
#
# Usage:
#   xsct scripts/build_fsbl.tcl
#   (XSCT is at: <Vitis_install>/bin/xsct)
#
# Output: fsbl/fsbl.elf
#
# Alternative (No Vitis at all):
#   Use a prebuilt FSBL from Digilent's Zybo Z7-10 board files:
#   https://github.com/Digilent/Zybo-Z7/releases  → download BOOT.BIN
#   Extract FSBL with: bootgen -read BOOT.BIN -arch zynq -dump fsbl
#   This prebuilt FSBL works for any bitstream targeting the Zybo Z7-10.
# =============================================================================

set xsa_file  "./zybo_rv32i_sd.xsa"
set workspace "./fsbl_workspace"
set app_name  "fsbl"
set out_dir   "./fsbl"

# Sanity check
if {![file exists $xsa_file]} {
    puts "ERROR: $xsa_file not found. Run build_zybo_project.tcl first."
    exit 1
}

puts "===> Creating FSBL from $xsa_file"

# Create a minimal Vitis workspace (XSCT headless)
setws $workspace

# Create platform from XSA
platform create -name "zybo_platform" -hw $xsa_file
platform generate

# Create FSBL application
app create -name $app_name -template "Zynq FSBL" -platform zybo_platform -domain standalone_domain
app build -name $app_name

# Copy ELF to output directory
file mkdir $out_dir
set elf_src "$workspace/$app_name/Debug/${app_name}.elf"
file copy -force $elf_src "$out_dir/fsbl.elf"

puts "===> FSBL built: $out_dir/fsbl.elf"
puts "===> Next: ./scripts/package_boot_bin.sh"

