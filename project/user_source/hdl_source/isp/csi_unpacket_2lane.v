/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********csi_unpacket_2lane MIPI CSI解码***********
--版本号1.0
--MIPI IP数据解码为32bit数据输出给下一级使用，这里需要了解MIPI协议的数据格式
*********************************************************************/

`timescale 1ns / 1ns

module csi_unpacket_2lane 
(
input wire          I_clk,  //来自MIPI 核的时钟
input wire          I_rst_n,//异步复位

input wire          I_hs_valid,//synthesis keep //来自MIPI核的数据有效信号,其中也包含的数据类型
input wire[15: 0]   I_hs_data, //synthesis keep //来自MIPI核的数据,其中也包含的数据类型数据，这里定义2LANE，1BYTE模式

output reg           O_csi_frame_start, //帧起始，1个周期有效
output reg           O_csi_frame_end,   //帧结束，1个周期有效
output reg           O_csi_valid, //synthesis keep      //有效数据输出
output reg           O_csi_hs,
output reg  [31: 0]  O_csi_data   //synthesis keep      //有效数据，这里定义2LANE，1BYTE模式
);


//MIPI数据类型
//DT 00 帧起始包
//DT 01 帧结束包
//DT 02 行起始包
//DT 03 行结束包
//DT 2a 8BIT模式下的数据长包
//DT 2b 10BIT模式下的数据长包

localparam FRAME_DATA_DT  = 8'h2B;   //RAW10
//localparam FRAME_DATA_DT  = 8'h2A;     //RAW8
localparam FRAME_START_DT = 8'h00;
localparam FRAME_END_DT   = 8'h01;


// A single countdown replaces the old length, elapsed count and subtract/compare.
// The CSI word count is 16-bit bytes: at most 32767 two-lane transfers.
reg        S_hs_valid_1d;
reg [15:0] S_hs_data_1d;
reg        S_head_en_1d;
reg [14:0] S_payload_left;
reg        csi_valid_r;
wire S_head_en = !S_hs_valid_1d && I_hs_valid;
wire [15:0] S_word_count = {I_hs_data[15:8],S_hs_data_1d[7:0]};
// This interface emits complete 32-bit words. Reject empty/partial-word packets.
wire S_length_ok = (|S_word_count[15:2]) && (S_word_count[1:0] == 2'b00);
wire S_payload_active = (|S_payload_left) && I_hs_valid;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        // A reset in the middle of HS must wait for idle and a fresh packet.
        S_hs_valid_1d <= 1'b1;
        S_head_en_1d <= 1'b0;
    end else begin
        S_hs_valid_1d <= I_hs_valid;
        S_head_en_1d <= S_head_en;
    end
end
always @(posedge I_clk) S_hs_data_1d <= I_hs_data;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        O_csi_frame_start <= 1'b0;
        O_csi_frame_end <= 1'b0;
    end else begin
        O_csi_frame_start <= I_hs_valid && S_head_en_1d &&
                            S_hs_data_1d[15:8] == FRAME_START_DT;
        O_csi_frame_end <= I_hs_valid && S_head_en_1d &&
                          S_hs_data_1d[15:8] == FRAME_END_DT;
    end
end

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n)
        S_payload_left <= 15'd0;
    else if(!I_hs_valid)
        // Abort on the first missing HS transfer, without counter wraparound.
        S_payload_left <= 15'd0;
    else if(S_head_en_1d)
        S_payload_left <= (S_hs_data_1d[15:8] == FRAME_DATA_DT && S_length_ok)
                          ? S_word_count[15:1] : 15'd0;
    else if(|S_payload_left)
        S_payload_left <= S_payload_left - 15'd1;
end

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        csi_valid_r <= 1'b0;
        O_csi_valid <= 1'b0;
    end else begin
        csi_valid_r <= S_payload_active ? !csi_valid_r : 1'b0;
        // Discard an orphan half-word when a packet ends early. The valid
        // complete pair still appears on the same cycle as the old parser.
        O_csi_valid <= S_payload_active && csi_valid_r;
    end
end
always @(posedge I_clk) begin
    O_csi_hs <= I_hs_valid;
    // The preceding transfer is already registered for header decoding. Reuse
    // it for pair assembly; invalid data is ignored by O_csi_valid consumers.
    O_csi_data <= {S_hs_data_1d,I_hs_data};
end
endmodule
