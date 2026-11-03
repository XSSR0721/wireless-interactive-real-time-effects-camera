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
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set #(
    parameter integer EXPOSURE_MIN=3,
    parameter integer EXPOSURE_MAX=3990,
    parameter integer IMAGE_HEIGHT=720,
    parameter integer GAIN_MIN=16, GAIN_MAX=112
)
(
input wire I_clk,
input wire I_rst,
input wire [3:0]I_btn,
input wire signed [12:0] I_pen_offset,
input wire I_pen_begin,I_pen_toggle,
output reg O_pen_ack,
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag
);
	

reg 	[19:0] 	rc_ae_tick = 0; 
reg 			r_ae_tick = 0; 
reg 	[4:0] 	rc_ag_tick = 0; 
reg 			r_ag_tick = 0; 
	
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		rc_ae_tick <= 0; 
		r_ae_tick <= 0; 
		rc_ag_tick <= 0; 
		r_ag_tick <= 0; 
	end else begin
	//	Trigger AE Inc / Dec per 1 ms. 
		rc_ae_tick <= rc_ae_tick + 1; 
		r_ae_tick <= 0; 
		if(rc_ae_tick >= 99999) begin
			rc_ae_tick <= 0; 
			r_ae_tick <= 1; 
		end 
	//	Trigger AG Inc / Dec per 32 ms. 
		rc_ag_tick <= rc_ag_tick + r_ae_tick; 
		r_ag_tick <= (&rc_ag_tick) && r_ae_tick; 
	end
end
	
//	Use button to add / sub idelay values. I_button[0]:IncDatDly, [1]DecDatDly, [2]IncI_clkDly, [3]DecI_clkDly
reg 	[3:0] 	r_button_0 = 0, r_button_1 = 0; 
// 30 fps, VTS=2000, maximum exposure=3990 half-lines.
// Default analogue-gain index is 90; KEY2/KEY3 keep the same 16..112 range.
// KEY3 may increase analogue gain up to 8x (AG index 112).
// Green vertical gestures use the SAME analogue gain index as KEY3.
localparam [15:0] GAIN_SPAN=GAIN_MAX-GAIN_MIN;
reg [15:0] r_ae_set=EXPOSURE_MAX, r_ag_set=90;
reg [2:0] pen_sync;
// The request payload is held until O_pen_ack changes.  Synchronize the
// complete payload for two camera-clock cycles; the three-stage toggle then
// arrives one cycle later and consumes an already settled value.
(* async_reg = "true" *) reg signed [12:0] pen_offset_meta,pen_offset_sync;
(* async_reg = "true" *) reg pen_begin_meta,pen_begin_sync;
reg [15:0] pen_base;
reg [1:0] pen_state;
reg pen_sign,pen_request;
reg [11:0] pen_pixels;
reg [23:0] pen_accum,pen_factor,pen_dividend;
reg [12:0] pen_remainder;
reg [4:0] pen_count;
wire [13:0] pen_trial={pen_remainder,pen_dividend[23]};
wire pen_subtract=pen_trial>=IMAGE_HEIGHT;
wire [13:0] pen_next_remainder=pen_subtract ? pen_trial-IMAGE_HEIGHT : pen_trial;
wire [23:0] pen_quotient={pen_dividend[22:0],pen_subtract};
wire [16:0] pen_sum={1'b0,pen_base}+{1'b0,pen_quotient[15:0]};
wire [16:0] pen_room={1'b0,pen_base}-GAIN_MIN;
wire [12:0] pen_magnitude=pen_offset_sync[12] ? -pen_offset_sync : pen_offset_sync;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        r_button_0<=0;r_button_1<=0;
        r_ae_set<=EXPOSURE_MAX;r_ag_set<=90;
        pen_offset_meta<=0;pen_offset_sync<=0;
        pen_begin_meta<=0;pen_begin_sync<=0;
        pen_sync<=0;O_pen_ack<=0;pen_base<=90;pen_state<=0;
        pen_sign<=0;pen_request<=0;pen_pixels<=0;pen_accum<=0;
        pen_factor<=0;pen_dividend<=0;pen_remainder<=0;pen_count<=0;
    end else begin
        r_button_0<=~I_btn;r_button_1<=r_button_0;
        pen_offset_meta<=I_pen_offset;pen_offset_sync<=pen_offset_meta;
        pen_begin_meta<=I_pen_begin;pen_begin_sync<=pen_begin_meta;
        pen_sync<={pen_sync[1:0],I_pen_toggle};
        // Original manual controls; a new pen target wins on its completion cycle.
        if(r_button_1[0])
            r_ae_set<=(r_ae_set>EXPOSURE_MIN) ? r_ae_set-r_ae_tick:r_ae_set;
        else if(r_button_1[1])
            r_ae_set<=(r_ae_set<EXPOSURE_MAX) ? r_ae_set+r_ae_tick:r_ae_set;
        if(r_button_1[2])
            r_ag_set<=(r_ag_set>GAIN_MIN) ? r_ag_set-r_ag_tick:r_ag_set;
        else if(r_button_1[3])
            r_ag_set<=(r_ag_set<GAIN_MAX) ? r_ag_set+r_ag_tick:r_ag_set;
        case(pen_state)
        0: if(pen_sync[2]!=O_pen_ack) begin
            pen_request<=pen_sync[2];
            if(pen_begin_sync) begin
                pen_base<=r_ag_set;O_pen_ack<=pen_sync[2];
            end else begin
                pen_sign<=pen_offset_sync[12];
                pen_pixels<=pen_magnitude>IMAGE_HEIGHT ? IMAGE_HEIGHT:pen_magnitude;
                pen_factor<={8'd0,GAIN_SPAN};pen_accum<=0;pen_count<=0;
                pen_state<=1;
            end
        end
        // Serial multiply and divide avoid a parallel multiplier/divider.
        1: begin
            if(pen_pixels[0]) pen_accum<=pen_accum+pen_factor;
            pen_pixels<=pen_pixels>>1;pen_factor<=pen_factor<<1;
            if(pen_count==11) begin
                pen_dividend<=pen_pixels[0] ? pen_accum+pen_factor:pen_accum;
                pen_remainder<=0;pen_count<=0;pen_state<=2;
            end else pen_count<=pen_count+1'b1;
        end
        2: begin
            pen_remainder<=pen_next_remainder[12:0];pen_dividend<=pen_quotient;
            if(pen_count==23) begin
                if(pen_sign)
                    r_ag_set<=pen_quotient>=pen_room ? GAIN_MIN:pen_base-pen_quotient[15:0];
                else
                    r_ag_set<=pen_sum>=GAIN_MAX ? GAIN_MAX:pen_sum[15:0];
                O_pen_ack<=pen_request;pen_state<=0;
            end else pen_count<=pen_count+1'b1;
        end
        default: pen_state<=0;
        endcase
    end
end

//	Update AG / AE when changed. 
reg 	[15:0] 	r_ae ; 
reg 	[15:0] 	r_ag ; 
reg 			r_ae_req = 0; //synthesis keep
assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_req <= 0; 
		r_ae     <= EXPOSURE_MAX; 
		r_ag     <= 90; 
	end else if(r_ae_req) begin
		r_ae_req <= 0; 
	end else if(((r_ae != r_ae_set) || (r_ag != r_ag_set))&&(I_cam_cfg_done==1'b1)&&(I_ae_cfg_done==1'b1)) begin
		r_ae     <= r_ae_set; 
		r_ag     <= r_ag_set; 
		r_ae_req <= 1; 
	end
end


endmodule


	
