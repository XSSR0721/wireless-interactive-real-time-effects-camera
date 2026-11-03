create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {pll_clk_24m}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# Photo export Ethernet: fixed 1Gb/s full-duplex RGMII, board reference input window.
create_clock -name ETH_RX -period 8.000 -waveform {0.000 4.000} [get_ports I_a_rgmii_rxc]
rename_clock -name ETH_TX [get_clocks {photo_network/pll_inst/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name ETH_TX90 [get_clocks {photo_network/pll_inst/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}]
set_input_delay -clock [get_clocks ETH_RX] -max 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks ETH_RX] -min 1.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks ETH_RX] -max -clock_fall -add_delay 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks ETH_RX] -min -clock_fall -add_delay 1.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
create_generated_clock -name ETH_TX_PIN -source [get_pins {photo_network/pll_inst/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}] -master_clock ETH_TX90 -divide_by 1 [get_ports O_a_rgmii_txc]
# PHY input requires >=1ns setup/hold; add0.2ns margin, referenced to the actual90deg forwarded clock.
set_output_delay -clock [get_clocks ETH_TX_PIN] -max 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks ETH_TX_PIN] -min -1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks ETH_TX_PIN] -clock_fall -add_delay -max 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks ETH_TX_PIN] -clock_fall -add_delay -min -1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_clock_groups -asynchronous \
 -group [get_clocks {ETH_RX photo_network/phy/regional.clkout}] \
 -group [get_clocks {ETH_TX ETH_TX90 ETH_TX_PIN}] \
 -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
 -group [get_clocks {sys_clk_50m pll_clk_100m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
 -group [get_clocks {pll_clk_24m}] \
 -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
