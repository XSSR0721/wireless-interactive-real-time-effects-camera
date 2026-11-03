module photo_ethernet(input sys_clk,rst_n,ddr_clk,ddr_rst_n,trigger,snapshot_valid,
 input[1:0]snapshot_bank,input[127:0]stickers,
 input write_busy,display_busy,display_safe,read_idle,input[9:0]display_outstanding,
 input ready,data_valid,input[127:0]data,
 output locked,ddr_busy,ddr_read,photo_response,output[24:0]ddr_address,
 output phy_reset_n,input[3:0]rgmii_rxd,input rgmii_rxc,rgmii_rx_ctl,
 output[3:0]rgmii_txd,output rgmii_txc,rgmii_tx_ctl);
 wire net_clk,phase_clk,slow_clk,pll_locked;
 photo_eth_pll pll_inst(.refclk(sys_clk),.reset(!rst_n),.clk0_out(net_clk),.clk1_out(phase_clk),.clk2_out(slow_clk),.lock(pll_locked));
 reg[22:0]power_wait;
 always @(posedge net_clk or negedge rst_n)begin
  if(!rst_n)power_wait<=0;else if(!pll_locked)power_wait<=0;else if(!(&power_wait))power_wait<=power_wait+1'b1;
 end
 assign phy_reset_n=&power_wait;
 wire net_rst_n=rst_n && pll_locked && phy_reset_n;
 wire rx_clk,rx_valid,rx_error;wire[7:0]rx_byte,tx_byte;wire tx_valid;
 photo_rgmii phy(.tx_clk(net_clk),.tx_clk90(phase_clk),.rst_n(net_rst_n),.tx_byte(tx_byte),.tx_valid(tx_valid),
 .rx_clock(rgmii_rxc),.rx_data(rgmii_rxd),.rx_control(rgmii_rx_ctl),.tx_clock(rgmii_txc),.tx_data(rgmii_txd),.tx_control(rgmii_tx_ctl),
 .rx_clk(rx_clk),.rx_byte(rx_byte),.rx_valid(rx_valid),.rx_error(rx_error));
 wire cmd_request,cmd_ack;wire[127:0]command;
 photo_udp_command receiver(.clk(rx_clk),.rst_n(net_rst_n),.data(rx_byte),.valid(rx_valid),.error(rx_error),.ack(cmd_ack),.request(cmd_request),.command(command));
 wire tx_start,tx_busy,tx_done;wire[10:0]length,app_address;wire[7:0]app_byte;
 photo_udp_tx sender(.clk(net_clk),.rst_n(net_rst_n),.start(tx_start),.length(length),.app_byte(app_byte),.app_address(app_address),.busy(tx_busy),.done(tx_done),.tx_data(tx_byte),.tx_valid(tx_valid));
 wire dma_request,dma_ack,dma_failed;wire[21:0]offset;wire[1:0]held_bank;wire[9:0]photo_address;wire[7:0]photo_byte;
 photo_export_control control(.clk(net_clk),.rst_n(net_rst_n),.command(command),.cmd_request(cmd_request),.cmd_ack(cmd_ack),
 .trigger(trigger),.snapshot_valid(snapshot_valid),.snapshot_bank(snapshot_bank),.stickers(stickers),.locked(locked),.held_bank(held_bank),
 .dma_request(dma_request),.dma_offset(offset),.dma_ack(dma_ack),.dma_failed(dma_failed),.tx_start(tx_start),.tx_length(length),.tx_busy(tx_busy),.tx_done(tx_done),
 .app_address(app_address),.photo_byte(photo_byte),.app_byte(app_byte),.photo_address(photo_address));
 photo_block_dma reader(.clk(ddr_clk),.rst_n(ddr_rst_n),.request(dma_request),.offset(offset),.bank(held_bank),.acknowledge(dma_ack),.failed(dma_failed),.busy(ddr_busy),
 .rd_en(ddr_read),.address(ddr_address),.ready(ready),.write_busy(write_busy),.display_busy(display_busy),.display_outstanding(display_outstanding),.read_idle(read_idle),.display_safe(display_safe),
 .data_valid(data_valid),.data(data),.net_clk(net_clk),.net_address(photo_address),.net_byte(photo_byte),.photo_response(photo_response));
endmodule
