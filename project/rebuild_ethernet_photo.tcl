import_device ph1_35p.db -package PH1P35MDG324 -speed 3
set project_dir [file normalize [file join [file dirname [info script]] td_project]]
cd $project_dir
open_project camera_to_dsi_display.al -single_run
elaborate -top design_top_wrapper
read_adc ../user_source/constraints_source/pin.adc
read_ip_adc -ip ddr2 -file ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc
read_sdc camera_to_dsi_display.sdc
read_sdc -ip ddr2 ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc
read_sdc -ip w128_d512_fifo ../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl
set_param rtl min_ripple_len 24
optimize_rtl
optimize_gate -packarea speed_gate.area
legalize_phy_inst
export_db speed_gate.db
set_param place seed 3
place
update_timing -mode manhattan
report_timing_summary -file speed_place.timing
report_area -io_info -file speed_place.area
export_db speed_place.db
route
fix_hold
update_timing -mode final
report_timing_status -file speed_route.ts
report_timing_summary -file speed_route.timing
report_area -io_info -file speed_route.area
report_route_status -drc
export_db speed_route.db
set fh [open speed_route.ts r]
set txt [read $fh]
close $fh
if {![regexp {SWNS: (-?[0-9.]+)ns} $txt _ setup] || ![regexp {HWNS: (-?[0-9.]+)ns} $txt _ hold]} {error "Missing final timing"}
if {$setup<0 || $hold<0} {error "Timing failed; no BIT generated"}
bitgen -bit main_ethernet_speed.bit
exit

