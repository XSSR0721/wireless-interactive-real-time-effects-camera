// PHY frontend follows the PH1P35 board reference RGMII primitive mapping.
// Current low-resource profile requires a 1000BASE-T full-duplex link.
module photo_rgmii(input tx_clk,tx_clk90,rst_n,input[7:0]tx_byte,input tx_valid,
 input rx_clock,input[3:0]rx_data,input rx_control,
 output tx_clock,output[3:0]tx_data,output tx_control,
 output rx_clk,output reg[7:0]rx_byte,output reg rx_valid,rx_error);
 wire rx_fast;wire[7:0]sample;wire v0,v1;
 wire[3:0]rx_delayed;wire ctl_delayed;
 // Input-pad delay balances the pad-to-SCLK clock insertion. 8 physical taps.
 PH1P_LOGIC_DYNAMIC_HD_IDELAY #(.CAS_MODE("NONE")) control_delay(
 .i(rx_control),.dly(5'd8),.cas_i(1'b0),.cas_rtn_i(1'b0),.cas_rtn_o(),.cas_o(),.o(ctl_delayed));
 PH1P_LOGIC_BUFG fast(.i(rx_clock),.o(rx_fast));
 PH1P_PHY_LCLK regional(.ce(1'b1),.clkin(rx_clock),.rst(1'b0),.clkout(rx_clk),.clkdivout());
 // Keep the forwarded PHY clock running; avoid a reset path crossing the90-degree clock phase.
 PH1P_LOGIC_HD_ODDR clock_out(.clk(tx_clk90),.rst(1'b0),.d0(1'b1),.d1(1'b0),.q(tx_clock));
 PH1P_LOGIC_HD_ODDR ctl_out(.clk(tx_clk),.rst(!rst_n),.d0(tx_valid),.d1(tx_valid),.q(tx_control));
 PH1P_LOGIC_HD_IDDR ctl_in(.clk(rx_fast),.rst(!rst_n),.d(ctl_delayed),.q0(v0),.q1(v1));
 genvar i;generate for(i=0;i<4;i=i+1)begin:bit_lane
  PH1P_LOGIC_HD_ODDR data_out(.clk(tx_clk),.rst(!rst_n),.d0(tx_byte[i]),.d1(tx_byte[i+4]),.q(tx_data[i]));
  PH1P_LOGIC_DYNAMIC_HD_IDELAY #(.CAS_MODE("NONE")) data_delay(
   .i(rx_data[i]),.dly(5'd8),.cas_i(1'b0),.cas_rtn_i(1'b0),.cas_rtn_o(),.cas_o(),.o(rx_delayed[i]));
  PH1P_LOGIC_HD_IDDR data_in(.clk(rx_fast),.rst(!rst_n),.d(rx_delayed[i]),.q0(sample[i]),.q1(sample[i+4]));
 end endgenerate
 always @(posedge rx_clk)begin rx_byte<=sample;rx_valid<=v0;rx_error<=v0^v1;end
endmodule
