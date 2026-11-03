

module design_top_wrapper (
    output wire O_phy_rst,output wire[3:0]O_a_rgmii_txd,
    output wire O_a_rgmii_txc,O_a_rgmii_tx_ctl,
    input wire[3:0]I_a_rgmii_rxd,input wire I_a_rgmii_rxc,I_a_rgmii_rx_ctl,
    input wire        I_sys_clk,
    output wire O_servo_pan,O_servo_tilt,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    input wire [3:0]  I_button,
    input wire        I_switch1,
    input wire        I_switch2,
    input wire        I_switch3,
    input wire        I_switch4,

    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
    wire            S_cam_path_rst_n;
    wire            S_cam_reset_release;
    wire            S_cam_lp_rst_n,S_cam_csi_rst_n,S_cam_ddr_rst_n;
    reg [18:0]      S_cam_startup_cnt;
    reg             S_cam_startup_done;
    reg [1:0]       S_cam_lp_release_sync;
    reg [1:0]       S_cam_csi_release_sync;
    reg [1:0]       S_cam_ddr_release_sync;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire [3:0]  S_video_mode;
    wire [3:0]  S_pen_video_mode;
    wire signed [12:0] S_pen_exposure_offset;
    wire S_pen_exposure_begin,S_pen_exposure_toggle,S_pen_exposure_ack;
    wire [3:0]  S_ae_button;
    wire        S_exposure_key_mode;
    wire        S_key1_trig;
    wire        S_key4_trig;
    wire S_export_lock,S_photo_dma_busy,S_photo_dma_read,S_photo_response;
    wire[24:0]S_photo_dma_address;
    wire[1:0]S_snapshot_bank;
    wire[127:0]S_photo_stickers;
    wire S_photo_send_toggle,S_photo_short_toggle;
    reg[2:0]S_photo_short_sync,S_export_lock_sync;
    wire S_export_cam_lock=S_export_lock_sync[2];
    always @(posedge S_24m_clk or negedge S_rst_n)begin
      if(!S_rst_n)begin S_photo_short_sync<=0;S_export_lock_sync<=0;end
      else begin S_photo_short_sync<={S_photo_short_sync[1:0],S_photo_short_toggle};
        S_export_lock_sync<={S_export_lock_sync[1:0],S_export_lock};end
    end
    assign S_key4_trig=S_photo_short_sync[2]^S_photo_short_sync[1];
    photo_key4 photo_send_key(.clk(I_sys_clk),.rst_n(S_rst_n),.pressed(!I_button[3]),
      .exposure_mode(S_exposure_key_mode),.short_toggle(S_photo_short_toggle),.long_toggle(S_photo_send_toggle));

    wire        S_snapshot_capture;
    wire        S_pen_capture_toggle;
    wire        S_pen_view_toggle,S_pen_view_target;
    wire [1:0]  S_snapshot_status;
    wire S_snapshot_capture_event;
    reg [2:0]   S_pen_capture_sync;
    wire        S_pen_capture_pulse=S_pen_capture_sync[2]^S_pen_capture_sync[1];
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) S_pen_capture_sync<=0;
        else S_pen_capture_sync<={S_pen_capture_sync[1:0],S_pen_capture_toggle};
    end
    wire        S_snapshot_view_toggle;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
    wire            S_auth_valid,S_auth_event,S_auth_variant;
    wire [1:0]      S_auth_status;
    wire S_servo_auth,S_servo_event,S_servo_valid,S_servo_update;
    wire [2:0] S_servo_color;
    wire [11:0] S_servo_left,S_servo_right,S_servo_top,S_servo_bottom;
    wire [5:0] S_servo_status;
    purple_led_servo #(.PAN_REVERSE(0),.TILT_REVERSE(0),
        .PAN_HOME_US(1500),.PAN_MIN_US(1000),.PAN_MAX_US(2000),
        .TILT_HOME_US(1500),.TILT_MIN_US(1167),.TILT_MAX_US(1833)) u_purple_servo (
        .cam_clk(S_csi_rx_clk),.clk(I_sys_clk),.rst_n(S_rst_n),
        .detect_update(S_servo_update),.detect_valid(S_servo_valid),
        .auth_valid(S_servo_auth),.auth_event(S_servo_event),
        .detect_color(S_servo_color),.lamp_left(S_servo_left),
        .lamp_right(S_servo_right),.lamp_top(S_servo_top),.lamp_bottom(S_servo_bottom),
        .pan_pwm(O_servo_pan),.tilt_pwm(O_servo_tilt),.status(S_servo_status)
    );

    wire [171:0] S_roi_payload;wire S_roi_request,S_roi_ack;
    wire [171:0] S_sticker_payload;
    wire S_sticker_request,S_sticker_ack;
    wire            S_detect_valid;
    wire [2:0]      S_detect_color;
    wire [11:0]     S_detect_left;
    wire [11:0]     S_detect_right;
    wire [11:0]     S_detect_top;
    wire [11:0]     S_detect_bottom;
    wire [29:0]     S_detect_history;
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    // 720p input-format diagnostics.  One RAW10 line from the factory
    // 1280-pixel mode contains 1600 bytes, i.e. 400 valid 32-bit CSI words.
    reg         S_dbg_hs_valid_d;
    reg [10:0]  S_dbg_csi_words;
    reg [10:0]  S_dbg_good_lines;
    reg         S_dbg_frame_seen_once;
    reg         S_dbg_frame_repeat_seen;
    reg         S_dbg_width_1280_seen;
    reg         S_dbg_height_720_seen;
    reg         S_mipi_frame_error;
    reg         S_lane_error_seen_frame;
    reg         S_dbg_isp_frame_seen_once;
    reg         S_dbg_isp_frame_repeat_seen;
    reg [1:0]   S_dbg_frame_repeat_sync;
    reg [1:0]   S_dbg_width_1280_sync;
    reg [1:0]   S_dbg_height_720_sync;
    reg [1:0]   S_dbg_isp_frame_repeat_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;


    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;
    assign S_cam_reset_release = S_cam_startup_cnt[18];
    assign S_cam_path_rst_n = S_rst_n && S_cam_startup_done;
    assign S_cam_lp_rst_n = S_cam_lp_release_sync[1];
    assign S_cam_csi_rst_n = S_cam_csi_release_sync[1];
    assign S_cam_ddr_rst_n = S_cam_ddr_release_sync[1];

    // Deterministic camera startup after every FPGA configuration:
    // reset low for about 11 ms, then wait another 11 ms before I2C/MIPI start.
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_cam_startup_cnt <= 19'd0;
            S_cam_startup_done <= 1'b0;
        end else begin
            if(!(&S_cam_startup_cnt))
                S_cam_startup_cnt <= S_cam_startup_cnt + 19'd1;
            if(&S_cam_startup_cnt)
                S_cam_startup_done <= 1'b1;
        end
    end

    // Cross the registered startup flag as data.  Only a local two-register
    // synchronizer drives reset release in each clock domain; the 19-input
    // startup decoder no longer fans out to thousands of asynchronous pins.
    always @(posedge S_100m_clk or negedge S_rst_n) begin
        if(!S_rst_n) S_cam_lp_release_sync<=0;
        else S_cam_lp_release_sync<={S_cam_lp_release_sync[0],S_cam_startup_done};
    end
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) S_cam_csi_release_sync<=0;
        else S_cam_csi_release_sync<={S_cam_csi_release_sync[0],S_cam_startup_done};
    end
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) S_cam_ddr_release_sync<=0;
        else S_cam_ddr_release_sync<={S_cam_ddr_release_sync[0],S_cam_startup_done};
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    // Count CSI payload words between HS packet boundaries.  This avoids
    // probing an internal net of csi_unpacket_2lane (which ChipWatcher cannot
    // legally connect to) and verifies the received line length externally.
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_dbg_hs_valid_d          <= 1'b0;
            S_dbg_csi_words           <= 11'd0;
            S_dbg_good_lines          <= 11'd0;
            S_dbg_frame_seen_once     <= 1'b0;
            S_dbg_frame_repeat_seen   <= 1'b0;
            S_dbg_width_1280_seen     <= 1'b0;
            S_dbg_height_720_seen     <= 1'b0;
            S_mipi_frame_error        <= 1'b0;
            S_lane_error_seen_frame   <= 1'b0;
            S_dbg_isp_frame_seen_once <= 1'b0;
            S_dbg_isp_frame_repeat_seen <= 1'b0;
        end
        else begin
            S_dbg_hs_valid_d <= S_hs_rx_valid;

            if(S_csi_frame_start) begin
                S_mipi_frame_error <= S_dbg_frame_seen_once &&
                                      ((S_dbg_good_lines != 11'd720) ||
                                       S_lane_error_seen_frame);
                S_lane_error_seen_frame <= 1'b0;
            end else if(S_lane_error_any) begin
                S_lane_error_seen_frame <= 1'b1;
            end

            if(!S_dbg_hs_valid_d && S_hs_rx_valid)
                S_dbg_csi_words <= 11'd0;
            else if(S_csi_valid)
                S_dbg_csi_words <= S_dbg_csi_words + 11'd1;

            // A packet with CSI payload is an image line.  Ignore short
            // frame-start/frame-end packets, whose payload count is zero.
            if(S_dbg_hs_valid_d && !S_hs_rx_valid && (S_dbg_csi_words != 0)) begin
                if(S_dbg_csi_words == 11'd400) begin
                    S_dbg_width_1280_seen <= 1'b1;
                    S_dbg_good_lines <= S_dbg_good_lines + 11'd1;
                end
            end

            if(S_csi_frame_start) begin
                if(S_dbg_frame_seen_once) begin
                    S_dbg_frame_repeat_seen <= 1'b1;
                    if(S_dbg_good_lines == 11'd720)
                        S_dbg_height_720_seen <= 1'b1;
                end
                else
                    S_dbg_frame_seen_once <= 1'b1;
                S_dbg_good_lines <= 11'd0;
            end

            if(S_ISP_O_tuser) begin
                if(S_dbg_isp_frame_seen_once)
                    S_dbg_isp_frame_repeat_seen <= 1'b1;
                else
                    S_dbg_isp_frame_seen_once <= 1'b1;
            end
        end
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
            S_dbg_frame_repeat_sync <= 2'b00;
            S_dbg_width_1280_sync <= 2'b00;
            S_dbg_height_720_sync <= 2'b00;
            S_dbg_isp_frame_repeat_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            S_dbg_frame_repeat_sync <= {S_dbg_frame_repeat_sync[0], S_dbg_frame_repeat_seen};
            S_dbg_width_1280_sync <= {S_dbg_width_1280_sync[0], S_dbg_width_1280_seen};
            S_dbg_height_720_sync <= {S_dbg_height_720_sync[0], S_dbg_height_720_seen};
            S_dbg_isp_frame_repeat_sync <= {S_dbg_isp_frame_repeat_sync[0], S_dbg_isp_frame_repeat_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    // On-screen bring-up status, from left to right in DEBUG_MODE=3:
    // I2C configuration completed, MIPI HS activity seen, repeated CSI frames,
    // and a 1280-pixel RAW10 line (400 x 32-bit CSI payload words) seen.
    assign S_hdmi_debug_status = {
        S_dbg_width_1280_sync[1],
        S_dbg_frame_repeat_sync[1],
        S_dbg_hs_seen_sync[1],
        S_dbg_cam_cfg_seen_sync[1]
    };
	
	assign O_cam_rst 	= S_cam_reset_release;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( 1'b0              ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  assign S_video_mode = {~I_switch4,~I_switch3,~I_switch2,~I_switch1};
  assign S_exposure_key_mode = (S_video_mode == 4'b0011);
  assign S_ae_button = {
      I_button[2],
      I_button[1],
      S_exposure_key_mode ? I_button[3] : 1'b1,
      S_exposure_key_mode ? I_button[0] : 1'b1
  };
  assign S_snapshot_capture = !S_export_cam_lock && ((S_key1_trig && !S_exposure_key_mode) || S_pen_capture_pulse);
  assign S_snapshot_view_toggle = S_key4_trig && !S_exposure_key_mode;

  key_remove_shakes u_snapshot_key1 (
      .I_clk          (S_24m_clk),
      .I_rst_n        (S_rst_n),
      .I_key_in       (I_button[0]),
      .O_key_trig_out (S_key1_trig)
  );



  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_cam_path_rst_n),
      .I_btn(S_ae_button),
      .I_pen_offset(S_pen_exposure_offset),.I_pen_begin(S_pen_exposure_begin),
      .I_pen_toggle(S_pen_exposure_toggle),.O_pen_ack(S_pen_exposure_ack),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_path_rst_n),  //系统复位输入
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done)  //AE配置完成
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_cam_lp_rst_n),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_cam_csi_rst_n),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_cam_csi_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_cam_csi_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// SC500 factory HD mode already outputs native 1280x720 RAW10.
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


//ISP算法顶层模块
wire [16:0] S_speed_payload;wire S_speed_request,S_speed_ack;
isp_top u_isp_top (
.O_speed_payload(S_speed_payload),.O_speed_request(S_speed_request),.I_speed_ack(S_speed_ack),
.O_servo_auth(S_servo_auth),.O_servo_event(S_servo_event),
.O_servo_valid(S_servo_valid),.O_servo_color(S_servo_color),
.O_servo_left(S_servo_left),.O_servo_right(S_servo_right),
.O_servo_top(S_servo_top),.O_servo_bottom(S_servo_bottom),.O_servo_update(S_servo_update),
.O_roi_payload(S_roi_payload),.O_roi_request(S_roi_request),.I_roi_ack(S_roi_ack),
.O_pen_exposure_offset(S_pen_exposure_offset),.O_pen_exposure_begin(S_pen_exposure_begin),
.O_pen_exposure_toggle(S_pen_exposure_toggle),.I_pen_exposure_ack(S_pen_exposure_ack),
.O_sticker_payload(S_sticker_payload),.O_sticker_request(S_sticker_request),.I_sticker_ack(S_sticker_ack),
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_cam_csi_rst_n),
.I_mode          (S_pen_video_mode),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_auth_revoke_toggle(S_pen_capture_toggle),
.O_auth_valid(S_auth_valid),.O_auth_event(S_auth_event),.O_auth_variant(S_auth_variant),.O_auth_status(S_auth_status),
.O_detect_valid  (S_detect_valid),
.O_detect_color  (S_detect_color),
.O_detect_left   (S_detect_left),
.O_detect_right  (S_detect_right),
.O_detect_top    (S_detect_top),
.O_detect_bottom (S_detect_bottom),
.O_detect_history(),
.I_tready        ()
  );


    wire [31:0] S_latency_now_gray,S_latency_bank_stamp,S_latency_display_stamp;
    wire S_latency_bank_valid,S_latency_display_valid;
    video_in u_video_in(
        .I_latency_start(S_axis_tuser),
        .O_latency_now_gray(S_latency_now_gray),.O_latency_stamp(S_latency_bank_stamp),
        .O_latency_valid(S_latency_bank_valid),
        .I_rst_n              (  S_cam_ddr_rst_n     ),
        .I_camera_rst_n       (  S_cam_csi_rst_n     ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( S_mipi_frame_error     ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_snapshot_capture    ( S_snapshot_capture    ),
        .I_snapshot_view_toggle( S_snapshot_view_toggle),
        .I_pen_view_toggle ( S_pen_view_toggle ),
        .I_pen_view_target ( S_pen_view_target ),
        .O_snapshot_status ( S_snapshot_status ),
        .O_snapshot_bank(S_snapshot_bank),
        .O_snapshot_capture_event(S_snapshot_capture_event),
        .I_video_out_rd_busy  ( S_video_out_rd_busy || S_photo_dma_busy ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en = S_vo_ddr_rd_en || S_photo_dma_read;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : S_photo_dma_read ? S_photo_dma_address : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .O_photo_safe(S_photo_display_safe),
        .I_latency_stamp(S_latency_bank_stamp),.I_latency_valid(S_latency_bank_valid),
        .O_latency_stamp(S_latency_display_stamp),.O_latency_valid(S_latency_display_valid),
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy || S_vi_ddr_wr_en || S_photo_dma_busy ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid && !S_photo_response ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    wire S_mc_reads_idle,S_photo_display_safe;
    photo_ethernet photo_network(.sys_clk(I_sys_clk),.rst_n(S_rst_n),.ddr_clk(S_ddr_clk),.ddr_rst_n(S_cam_ddr_rst_n),
      .trigger(S_photo_send_toggle),.snapshot_valid(S_snapshot_status[0]),.snapshot_bank(S_snapshot_bank),.stickers(S_photo_stickers),
      .write_busy(S_video_in_wr_busy || S_vi_ddr_wr_en),.display_busy(S_video_out_rd_busy),.display_outstanding(10'd0),.read_idle(S_mc_reads_idle),.display_safe(S_photo_display_safe),
      .ready(S_ddr_user_ready),.data_valid(S_ddr_user_rd_valid),.data(S_ddr_user_rd_data),
      .locked(S_export_lock),.ddr_busy(S_photo_dma_busy),.ddr_read(S_photo_dma_read),.photo_response(S_photo_response),.ddr_address(S_photo_dma_address),
      .phy_reset_n(O_phy_rst),.rgmii_rxd(I_a_rgmii_rxd),.rgmii_rxc(I_a_rgmii_rxc),.rgmii_rx_ctl(I_a_rgmii_rx_ctl),
      .rgmii_txd(O_a_rgmii_txd),.rgmii_txc(O_a_rgmii_txc),.rgmii_tx_ctl(O_a_rgmii_tx_ctl));

    mc_to_user_interface u_mc_to_user_interface(
        .O_read_idle(S_mc_reads_idle),
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    ) // Normal SC500 1280x720 camera image
    )u_hdmi_mixer(
        .I_speed_payload(S_speed_payload),.I_speed_request(S_speed_request),.O_speed_ack(S_speed_ack),
        .I_roi_payload(S_roi_payload),.I_roi_request(S_roi_request),.O_roi_ack(S_roi_ack),
        .I_sticker_payload(S_sticker_payload),.I_sticker_request(S_sticker_request),.O_sticker_ack(S_sticker_ack),
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .I_switch_mode   ( S_video_mode ),
        .O_filter_mode   ( S_pen_video_mode ),
        .O_pen_exposure_offset(),.O_pen_exposure_begin(),
        .O_pen_exposure_toggle(),.I_pen_exposure_ack(S_pen_exposure_ack),
        .I_pen_gain      ( S_ag[6:0] ),
        .O_pen_capture_toggle ( S_pen_capture_toggle ),
        .O_pen_view_toggle ( S_pen_view_toggle ),
        .O_pen_view_target ( S_pen_view_target ),
        .I_snapshot_status ( S_snapshot_status ),
        .I_snapshot_capture_event(S_snapshot_capture_event),
        .O_photo_stickers(S_photo_stickers),
        .I_auth_valid(S_auth_valid),.I_auth_event(S_auth_event),.I_auth_variant(S_auth_variant),.I_auth_status(S_auth_status),
        .I_detect_valid  ( S_detect_valid      ),
        .I_detect_color  ( S_detect_color      ),
        .I_detect_left   ( S_detect_left       ),
        .I_detect_right  ( S_detect_right      ),
        .I_detect_top    ( S_detect_top        ),
        .I_detect_bottom ( S_detect_bottom     ),
        .I_detect_history( 30'd0 ),
        .I_latency_now_gray(S_latency_now_gray),.I_latency_stamp(S_latency_display_stamp),
        .I_latency_valid(S_latency_display_valid),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_out_data   ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


    
endmodule
