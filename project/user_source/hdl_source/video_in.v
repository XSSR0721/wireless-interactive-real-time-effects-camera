

module video_in (
    input wire         I_rst_n,
    input wire         I_camera_rst_n,

    input wire         I_latency_start,
    output wire [31:0] O_latency_now_gray,O_latency_stamp,
    output wire O_latency_valid,
    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_snapshot_capture,
    input wire         I_snapshot_view_toggle,
    input wire         I_pen_view_toggle,I_pen_view_target,
    output wire[1:0] O_snapshot_bank,
    output wire[1:0]   O_snapshot_status,
    output reg         O_snapshot_capture_event,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    reg [2:0] S_pen_view_sync;
    reg [1:0] S_pen_target_sync;
    wire S_pen_view_pulse=S_pen_view_sync[2]^S_pen_view_sync[1];
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin S_pen_view_sync<=0;S_pen_target_sync<=0;end
        else begin
            S_pen_view_sync<={S_pen_view_sync[1:0],I_pen_view_toggle};
            S_pen_target_sync<={S_pen_target_sync[0],I_pen_view_target};
        end
    end
    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_last_started_wp;
    reg[1:0]    S_live_rp;
    reg[1:0]    S_snapshot_rp;
    reg         S_have_completed_frame;
    reg         S_snapshot_valid;
    reg         S_snapshot_view;
    assign O_snapshot_bank=S_snapshot_rp;
    assign O_snapshot_status={S_snapshot_view,S_snapshot_valid};
    reg         S_capture_sync_1d;
    reg         S_capture_sync_2d;
    reg         S_capture_sync_3d;
    reg         S_view_sync_1d;
    reg         S_view_sync_2d;
    reg         S_view_sync_3d;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;

    frame_latency_banks u_latency_banks(
      .clk(I_ddr_clk),.rst_n(I_rst_n),.cam_clk(I_camera_clk),.cam_rst_n(I_camera_rst_n),
      .ingress(I_latency_start),.frame_start(S_frame_start),.pause(I_display_pause),
      .frame_error(I_mipi_rx_error),.write_bank(S_video_in_wp),.last_bank(S_last_started_wp),
      .read_bank(O_video_out_rp),.photo_view(S_snapshot_view),
      .now_gray(O_latency_now_gray),.read_stamp(O_latency_stamp),.read_valid(O_latency_valid));

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;

    wire S_capture_pulse = S_capture_sync_2d & ~S_capture_sync_3d;
    wire S_view_pulse = S_view_sync_2d & ~S_view_sync_3d;
    wire S_lock_valid = S_snapshot_valid ||
                        (S_capture_pulse && S_have_completed_frame);
    wire [1:0] S_lock_rp = (S_capture_pulse && S_have_completed_frame) ?
                           S_live_rp : S_snapshot_rp;

    function [1:0] next_write_pointer;
        input [1:0] current_pointer;
        input       lock_valid;
        input [1:0] lock_pointer;
        reg   [1:0] candidate;
        begin
            candidate = current_pointer + 2'd1;
            if(lock_valid && (candidate == lock_pointer))
                candidate = candidate + 2'd1;
            next_write_pointer = candidate;
        end
    endfunction


    assign S_fifo_rst = S_camera_frame_start_extend_3d;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_capture_sync_1d <= 1'b0;
            S_capture_sync_2d <= 1'b0;
            S_capture_sync_3d <= 1'b0;
            S_view_sync_1d <= 1'b0;
            S_view_sync_2d <= 1'b0;
            S_view_sync_3d <= 1'b0;
        end else begin
            S_capture_sync_1d <= I_snapshot_capture;
            S_capture_sync_2d <= S_capture_sync_1d;
            S_capture_sync_3d <= S_capture_sync_2d;
            S_view_sync_1d <= I_snapshot_view_toggle;
            S_view_sync_2d <= S_view_sync_1d;
            S_view_sync_3d <= S_view_sync_2d;
        end
    end

    // S_ddr_wr_valid owns the requested burst, while O_ddr_user_wr_en is the
    // registered final command actually presented to the shared DDR port.
    // On the last beat S_ddr_wr_valid drops one clock before wr_en; keep busy
    // asserted for that tail clock so video_out cannot count a read command
    // that the top-level write-priority mux silently replaces with a write.
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( I_camera_data      ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_camera_rst_n) begin
        if(!I_camera_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @(posedge I_camera_clk or negedge I_camera_rst_n) begin
        if(!I_camera_rst_n)
            S_extend_cnt <= 'd0;
        else if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_camera_frame_start_extend_1d <= 1'b0;
            S_camera_frame_start_extend_2d <= 1'b0;
            S_camera_frame_start_extend_3d <= 1'b0;
        end else begin
            S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
            S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
            S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
        end
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_in_wp <= 2'd0;
            S_last_started_wp <= 2'd0;
            S_live_rp <= 2'd0;
            S_have_completed_frame <= 1'b0;
        end else if(!I_display_pause && S_frame_start && !I_mipi_rx_error) begin
            if(S_have_completed_frame)
                S_live_rp <= S_last_started_wp;
            S_last_started_wp <= S_video_in_wp;
            S_have_completed_frame <= 1'b1;
            S_video_in_wp <= next_write_pointer(S_video_in_wp,
                                                 S_lock_valid,
                                                 S_lock_rp);
        end
    end

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_snapshot_rp <= 2'd0;
            S_snapshot_valid <= 1'b0;
            O_snapshot_capture_event <= 1'b0;
            S_snapshot_view <= 1'b0;
        end else begin
            if(S_capture_pulse && S_have_completed_frame) begin
                S_snapshot_rp <= S_live_rp;
                O_snapshot_capture_event <= ~O_snapshot_capture_event;
                S_snapshot_valid <= 1'b1;
            end
            if(S_pen_view_pulse) begin
                if(!S_pen_target_sync[1]) S_snapshot_view<=0;
                else if(S_snapshot_valid) S_snapshot_view<=1;
            end else if(S_view_pulse && S_snapshot_valid)
                S_snapshot_view <= ~S_snapshot_view;
        end
    end

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 2'd0;
        else if(S_snapshot_view && S_snapshot_valid)
            O_video_out_rp <= S_snapshot_rp;
        else
            O_video_out_rp <= S_live_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_wr_en <= 1'b0;
        else
            O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_last_started_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule
// Frame metadata only: image transport and DDR arbitration remain unchanged.
// 66 2/3 MHz DDR user clock, 1 ms resolution. 32-bit modulo subtraction
// handles normal wraparound; a stale ingress or >999 ms frame is not reported.
module frame_latency_banks #(parameter TICKS_PER_MS=66667)(
 input clk,rst_n,cam_clk,cam_rst_n,ingress,frame_start,pause,frame_error,
 input [1:0] write_bank,last_bank,read_bank,input photo_view,
 output reg [31:0] now_gray,output [31:0] read_stamp,output read_valid);
 reg [16:0] prescale;
 reg [31:0] now_ms,ingress_ms;
 reg ingress_toggle;
 (* async_reg="true" *) reg [2:0] ingress_sync;
 reg [31:0] stamps[0:3];
 reg [3:0] bank_valid;
 reg ingress_seen,started;
 integer b;
 always @(posedge cam_clk or negedge cam_rst_n)begin
   if(!cam_rst_n)ingress_toggle<=0;
   else if(ingress)ingress_toggle<=~ingress_toggle;
 end
 wire ingress_pulse=ingress_sync[2]^ingress_sync[1];
 wire [31:0] ingress_age=now_ms-ingress_ms;
 assign read_stamp=stamps[read_bank];
 assign read_valid=bank_valid[read_bank] && !photo_view;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     prescale<=0;now_ms<=0;now_gray<=0;ingress_ms<=0;ingress_seen<=0;
     ingress_sync<=0;bank_valid<=0;started<=0;
     for(b=0;b<4;b=b+1)stamps[b]<=0;
   end else begin
     ingress_sync<={ingress_sync[1:0],ingress_toggle};
     if(prescale==TICKS_PER_MS-1)begin
       prescale<=0;now_ms<=now_ms+1'b1;
       now_gray<=((now_ms+32'd1)>>1)^(now_ms+32'd1);
     end else prescale<=prescale+1'b1;
     if(ingress_pulse)begin ingress_ms<=now_ms;ingress_seen<=1;end
     if(frame_start && !pause)begin
       if(frame_error)begin bank_valid[last_bank]<=0;started<=0;end
       else begin
         if(started)bank_valid[last_bank]<=1;
         stamps[write_bank]<=ingress_pulse?now_ms:ingress_ms;
         bank_valid[write_bank]<=0;
         started<=(ingress_seen && ingress_age<1000) || ingress_pulse;
       end
     end
   end
 end
endmodule

// Gray time crosses continuously; the timestamp/valid bundle is latched at
// display VS and stable well before first active pixel. Synchronize and require
// two matching samples; never subtract unrelated camera/display frame starts.
module frame_latency_display(input clk,rst_n,tick,
 input [31:0] now_gray,stamp,input valid,photo,
 output reg [11:0] bcd,output reg show);
 (* async_reg="true" *) reg [31:0] gray_meta,gray_sync;
 (* async_reg="true" *) reg [32:0] stamp_meta,stamp_sync;
 reg [32:0] stamp_settled;
 reg [31:0] now_binary;
 integer bitnum;
 always @*begin
   now_binary[31]=gray_sync[31];
   for(bitnum=30;bitnum>=0;bitnum=bitnum-1)
     now_binary[bitnum]=now_binary[bitnum+1]^gray_sync[bitnum];
 end
 wire [31:0] age=now_binary-stamp_settled[31:0];
 reg [9:0] remainder;
 reg [3:0] hundreds,tens;
 reg busy;
 reg [4:0] refresh;
 wire usable=stamp_sync==stamp_settled && stamp_settled[32] && age<1000 && !photo;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     gray_meta<=0;gray_sync<=0;stamp_meta<=0;stamp_sync<=0;stamp_settled<=0;
     bcd<=0;show<=0;remainder<=0;hundreds<=0;tens<=0;busy<=0;refresh<=0;
   end else begin
     gray_meta<=now_gray;gray_sync<=gray_meta;
     stamp_meta<={valid,stamp};stamp_sync<=stamp_meta;stamp_settled<=stamp_sync;
     if(photo)begin show<=0;refresh<=0;busy<=0;end
     else if(tick)begin
       if(!usable)begin show<=0;refresh<=0;busy<=0;end
       else if(refresh==0 || !show)begin
         remainder<=age[9:0];hundreds<=0;tens<=0;busy<=1;refresh<=29;
       end else refresh<=refresh-1'b1;
     end else if(busy)begin
       if(remainder>=100)begin remainder<=remainder-100;hundreds<=hundreds+1'b1;end
       else if(remainder>=10)begin remainder<=remainder-10;tens<=tens+1'b1;end
       else begin bcd<={hundreds,tens,remainder[3:0]};show<=1;busy<=0;end
     end
   end
 end
endmodule
