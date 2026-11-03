module isp_top (
    output [16:0] O_speed_payload,output O_speed_request,input I_speed_ack,
    output [171:0] O_roi_payload,output O_roi_request,input I_roi_ack,
    output signed [12:0] O_pen_exposure_offset,
    output O_pen_exposure_begin,O_pen_exposure_toggle,input I_pen_exposure_ack,
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input [3:0]     I_mode          ,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    // Fresh, authenticated normal-PURPLE observations for the servo mailbox.
    output reg O_servo_auth,O_servo_event,O_servo_valid,
    output reg [2:0] O_servo_color,
    output reg [11:0] O_servo_left,O_servo_right,O_servo_top,O_servo_bottom,
    output O_servo_update,
    output [171:0] O_sticker_payload,
    output O_sticker_request,input I_sticker_ack,
    input              I_auth_revoke_toggle,
    output             O_auth_valid,O_auth_event,O_auth_variant,
    output [1:0]       O_auth_status,
    output             O_detect_valid  ,
    output [2:0]       O_detect_color  ,
    output [11:0]      O_detect_left   ,
    output [11:0]      O_detect_right  ,
    output [11:0]      O_detect_top    ,
    output [11:0]      O_detect_bottom ,
    output reg [29:0]  O_detect_history,
    output 			I_tready
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  wire         edge_O_tlast;
  wire         edge_O_tuser;
  wire [95:0]  edge_O_tdata;
  wire         edge_O_tvalid;
  wire lamp_valid;
  wire [11:0] lamp_left, lamp_right, lamp_top, lamp_bottom;
  wire [2:0] lamp_color;
  wire lamp_obs_valid, lamp_obs_present;
  wire [2:0] lamp_obs_color;
  wire [11:0] lamp_obs_left, lamp_obs_right, lamp_obs_top, lamp_obs_bottom;
  wire lamp_candidate_valid;
  wire [2:0] lamp_candidate_color;
  wire [11:0] lamp_candidate_left,lamp_candidate_right;
  wire [11:0] lamp_candidate_top,lamp_candidate_bottom;
  wire auth_target_present;
  wire [2:0] auth_target_color;
  wire [11:0] auth_target_left,auth_target_right;
  wire [11:0] auth_target_top,auth_target_bottom;
  reg [29:0] S_detect_history_shift;
  reg [4:0] S_detect_history_count;
  // Four-candidate detector retains the lamp/nearby-PCB union box.
  // Before authentication publish its strongest candidate; afterwards publish
  // only the authenticated spatial track.
  assign O_detect_valid = O_auth_valid ? auth_target_present : lamp_valid;
  assign O_detect_color = O_auth_valid ? auth_target_color : lamp_color;
  assign O_detect_left = O_auth_valid ? auth_target_left : lamp_left;
  assign O_detect_right = O_auth_valid ? auth_target_right : lamp_right;
  assign O_detect_top = O_auth_valid ? auth_target_top : lamp_top;
  assign O_detect_bottom = O_auth_valid ? auth_target_bottom : lamp_bottom;

  led_lamp_detector u_led_lamp_detector (
      .clk(axi4s_video_aclk), .rst_n(I_rst_n),
      .data(awb_O_tdata), .valid(awb_O_tvalid), .user(awb_O_tuser),
      .found(lamp_valid), .color(lamp_color),
      .left(lamp_left), .right(lamp_right),
      .top(lamp_top), .bottom(lamp_bottom),
      .obs_valid(lamp_obs_valid), .obs_present(lamp_obs_present),
      .obs_color(lamp_obs_color),
      .obs_left(lamp_obs_left), .obs_right(lamp_obs_right),
      .obs_top(lamp_obs_top), .obs_bottom(lamp_obs_bottom),
      .candidate_valid(lamp_candidate_valid),
      .candidate_color(lamp_candidate_color),
      .candidate_left(lamp_candidate_left),.candidate_right(lamp_candidate_right),
      .candidate_top(lamp_candidate_top),.candidate_bottom(lamp_candidate_bottom)
  );

  pen_code_auth_multi #(.PURPLE_RECOVERY(1),.PURPLE_LOST_FRAMES(20)) u_pen_flash_auth(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .frame_valid(lamp_obs_valid),
      .candidate_valid(lamp_candidate_valid),.candidate_color(lamp_candidate_color),
      .candidate_left(lamp_candidate_left),.candidate_right(lamp_candidate_right),
      .candidate_top(lamp_candidate_top),.candidate_bottom(lamp_candidate_bottom),
      .revoke_toggle(I_auth_revoke_toggle),.granted(O_auth_valid),
      .event_toggle(O_auth_event),.status(O_auth_status),
      .target_present(auth_target_present),.target_color(auth_target_color),
      .target_variant(O_auth_variant),
      .target_left(auth_target_left),.target_right(auth_target_right),
      .target_top(auth_target_top),.target_bottom(auth_target_bottom)
  );

  // Adapt authenticated BLUE/BLUE1 to the tested editor's BLUE/YELLOW inputs.
  // Fresh raw frame presence prevents held display coordinates extending a hold.
  wire [2:0] sticker_input_color=(O_auth_valid && auth_target_color==3) ?
                                    (O_auth_variant ? 3'd4:3'd3):3'd0;
  wire [171:0] sticker_config;
  reg [1:0] sticker_frame_pipe;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n) sticker_frame_pipe<=0;
      else sticker_frame_pipe<={sticker_frame_pipe[0],lamp_obs_valid};
  end
  sticker_editor u_sticker_editor(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),.frame_valid(sticker_frame_pipe[1]),
      .frame_present(O_auth_valid && auth_target_present && sticker_input_color!=0),
      .color(sticker_input_color),.left(auth_target_left),.right(auth_target_right),
      .top(auth_target_top),.bottom(auth_target_bottom),
      .config_bus(sticker_config),.beep(),.buzzer_n()
  );
  sticker_config_tx u_sticker_config_tx(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),.config_bus(sticker_config),
      .ack(I_sticker_ack),.payload(O_sticker_payload),.request(O_sticker_request));

  // The serial four-track matcher completes within 22 clocks. Capture the
  // live authenticated target at clock 31 and send one update at clock 32.
  // Display-held boxes must never be integrated as new servo measurements.
  reg [31:0] servo_update_pipe;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n) begin
          servo_update_pipe<=0;O_servo_auth<=0;O_servo_event<=0;
          O_servo_valid<=0;O_servo_color<=0;
          O_servo_left<=0;O_servo_right<=0;O_servo_top<=0;O_servo_bottom<=0;
      end else begin
          servo_update_pipe<={servo_update_pipe[30:0],lamp_obs_valid};
          if(servo_update_pipe[30]) begin
              O_servo_auth<=O_auth_valid && auth_target_color==5 && !O_auth_variant;
              O_servo_event<=O_auth_event;
              O_servo_valid<=O_auth_valid && auth_target_color==5 &&
                             !O_auth_variant && auth_target_present;
              O_servo_color<=auth_target_color;
              O_servo_left<=auth_target_left;O_servo_right<=auth_target_right;
              O_servo_top<=auth_target_top;O_servo_bottom<=auth_target_bottom;
          end
      end
  end
  assign O_servo_update=servo_update_pipe[31];

  wire speed_valid;wire [15:0] speed_bcd;
  led_speed_estimator u_led_speed(
    .clk(axi4s_video_aclk),.rst_n(I_rst_n),.sample(servo_update_pipe[30]),
    .auth_valid(O_auth_valid),.auth_event(O_auth_event),.variant(O_auth_variant),
    .present(auth_target_present),.color(auth_target_color),
    .left(auth_target_left),.right(auth_target_right),.top(auth_target_top),.bottom(auth_target_bottom),
    .valid(speed_valid),.bcd(speed_bcd));
  led_speed_mailbox_tx u_speed_tx(.clk(axi4s_video_aclk),.rst_n(I_rst_n),
    .value({speed_valid,speed_bcd}),.ack(I_speed_ack),
    .payload(O_speed_payload),.request(O_speed_request));


  // Record exactly 30 camera-frame decisions.  The detector's unheld result
  // is used, so each bit describes that camera frame rather than an HDMI
  // refresh or the two-frame-smoothed visible box.  Bit 29 is oldest.
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n) begin
          S_detect_history_shift <= 30'd0;
          S_detect_history_count <= 5'd0;
          O_detect_history <= 30'd0;
      end else if(lamp_obs_valid) begin
          if(S_detect_history_count==5'd29) begin
              O_detect_history <= {S_detect_history_shift[28:0],
                                   lamp_obs_present && lamp_obs_color!=0};
              S_detect_history_shift <= 30'd0;
              S_detect_history_count <= 5'd0;
          end else begin
              S_detect_history_shift <= {S_detect_history_shift[28:0],
                                         lamp_obs_present && lamp_obs_color!=0};
              S_detect_history_count <= S_detect_history_count+1'b1;
          end
      end
  end

  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = edge_O_tlast   ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ), // 图像高度
    .IMG_WIDTH           (1280), // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR") // Restore the sensor format verified on the board; mirror control stays enabled
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

    green_roi_system #(.EXTERNAL_SWITCHES(1)) u_green_roi(
        .auth_valid(O_auth_valid),.auth_variant(O_auth_variant),.auth_color(auth_target_color),
        .clk(axi4s_video_aclk),.rst_n(I_rst_n),.switch_mode(I_mode),
        .data(awb_O_tdata),.valid(awb_O_tvalid),.user(awb_O_tuser),.last(awb_O_tlast),
        .frame_end(lamp_obs_valid),.candidate_valid(lamp_candidate_valid),.candidate_color(lamp_candidate_color),
        .candidate_left(lamp_candidate_left),.candidate_right(lamp_candidate_right),
        .candidate_top(lamp_candidate_top),.candidate_bottom(lamp_candidate_bottom),
        .lamp_valid(O_detect_valid),.lamp_color(O_detect_color),.lamp_left(O_detect_left),.lamp_right(O_detect_right),
        .lamp_top(O_detect_top),.lamp_bottom(O_detect_bottom),
        .ui_payload(O_roi_payload),.ui_request(O_roi_request),.ui_ack(I_roi_ack),
        .out_data(edge_O_tdata),.out_valid(edge_O_tvalid),.out_user(edge_O_tuser),.out_last(edge_O_tlast),
        .exposure_offset(O_pen_exposure_offset),.exposure_begin(O_pen_exposure_begin),
        .exposure_toggle(O_pen_exposure_toggle),.exposure_ack(I_pen_exposure_ack));

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( edge_O_tuser	    ),
        .I_96b_valid        ( edge_O_tvalid 		),
        .I_96b_data         ( edge_O_tdata		),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule


// One-shot pen code for the measured 25..30 camera decisions per second:
// ON 330 ms, OFF 200 ms, ON 200 ms, OFF 200 ms, then steady ON.
// It uses one decision per camera frame and tolerates one isolated wrong
// decision.  No pixel ROI accumulator, divider or general multiplier is used.
module pen_code_auth #(
    parameter IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter LEAD_MIN=4, LEAD_MAX=6,
    parameter SYMBOL_MIN=2, SYMBOL_MAX=4,
    parameter LOST_FRAMES=20
)(
    input clk,rst_n,
    input frame_valid,input frame_present,
    input [2:0] raw_color,
    input [11:0] raw_left,raw_right,raw_top,raw_bottom,
    input revoke_toggle,
    output reg granted,event_toggle,
    output [1:0] status
);
    localparam SEARCH=3'd0,LEAD=3'd1,OFF_ONE=3'd2,
               ON_GAP=3'd3,OFF_TWO=3'd4,FINAL_ON=3'd5,
               TRACK=3'd6;
    reg [2:0] state;
    reg level;
    reg [3:0] run_len;
    reg pending_change;
    reg [2:0] pen_color;
    reg [1:0] foreign_count;
    reg [6:0] lost_count;
    reg [11:0] box_l,box_r,box_t,box_b;
    reg [2:0] revoke_sync;

    wire revoke=revoke_sync[2]^revoke_sync[1];
    wire [12:0] rw={1'b0,raw_right}-{1'b0,raw_left}+13'd1;
    wire [12:0] rh={1'b0,raw_bottom}-{1'b0,raw_top}+13'd1;
    wire [12:0] bw={1'b0,box_r}-{1'b0,box_l}+13'd1;
    wire [12:0] bh={1'b0,box_b}-{1'b0,box_t}+13'd1;
    wire [12:0] raw_cx2={1'b0,raw_left}+{1'b0,raw_right};
    wire [12:0] raw_cy2={1'b0,raw_top}+{1'b0,raw_bottom};
    wire [12:0] box_cx2={1'b0,box_l}+{1'b0,box_r};
    wire [12:0] box_cy2={1'b0,box_t}+{1'b0,box_b};
    wire [11:0] raw_cx=raw_cx2[12:1],raw_cy=raw_cy2[12:1];
    wire [11:0] box_cx=box_cx2[12:1],box_cy=box_cy2[12:1];
    wire [11:0] dx=raw_cx>=box_cx?raw_cx-box_cx:box_cx-raw_cx;
    wire [11:0] dy=raw_cy>=box_cy?raw_cy-box_cy:box_cy-raw_cy;

    wire candidate=frame_present && raw_color!=0 &&
        raw_right>=raw_left && raw_bottom>=raw_top &&
        rw>=6 && rh>=6 && rw<=600 && rh<=600 &&
        raw_right<IMG_WIDTH && raw_bottom<IMG_HEIGHT;
    // Box dimensions vary strongly with exposure.  During the code only the
    // centre must stay nearby; after authentication the pen may move freely.
    wire near_box=dx<=(bw>>1)+13'd48 && dy<=(bh>>1)+13'd48;
    wire code_on=candidate && raw_color==pen_color && near_box;
    wire track_on=candidate && raw_color==pen_color;

    assign status=state==TRACK ? 2'd2 : state==SEARCH ? 2'd0:2'd1;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            revoke_sync<=0;state<=SEARCH;level<=0;run_len<=0;
            pending_change<=0;pen_color<=0;foreign_count<=0;lost_count<=0;
            box_l<=0;box_r<=0;box_t<=0;box_b<=0;
            granted<=0;event_toggle<=0;
        end else begin
            revoke_sync<={revoke_sync[1:0],revoke_toggle};
            if(revoke) begin
                state<=SEARCH;level<=0;run_len<=0;pending_change<=0;
                foreign_count<=0;lost_count<=0;granted<=0;
            end else if(frame_valid) begin
                case(state)
                SEARCH: begin
                    granted<=0;level<=0;run_len<=0;pending_change<=0;
                    foreign_count<=0;lost_count<=0;
                    if(candidate) begin
                        state<=LEAD;level<=1;run_len<=1;
                        pen_color<=raw_color;
                        box_l<=raw_left;box_r<=raw_right;
                        box_t<=raw_top;box_b<=raw_bottom;
                    end
                end
                TRACK: begin
                    granted<=1;pending_change<=0;
                    if(track_on) begin
                        lost_count<=0;foreign_count<=0;
                        box_l<=raw_left;box_r<=raw_right;
                        box_t<=raw_top;box_b<=raw_bottom;
                    end else if(candidate) begin
                        lost_count<=0;
                        if(foreign_count>=2) begin
                            state<=SEARCH;granted<=0;foreign_count<=0;
                        end else foreign_count<=foreign_count+1'b1;
                    end else begin
                        foreign_count<=0;
                        if(lost_count>=LOST_FRAMES-1) begin
                            state<=SEARCH;granted<=0;lost_count<=0;
                        end else lost_count<=lost_count+1'b1;
                    end
                end
                FINAL_ON: begin
                    granted<=0;
                    if(code_on) begin
                        pending_change<=0;
                        box_l<=raw_left;box_r<=raw_right;
                        box_t<=raw_top;box_b<=raw_bottom;
                        if(run_len>=2) begin
                            state<=TRACK;granted<=1;
                            event_toggle<=~event_toggle;
                            lost_count<=0;foreign_count<=0;
                        end else run_len<=run_len+1'b1;
                    end else if(!pending_change)
                        pending_change<=1;
                    else begin
                        state<=SEARCH;run_len<=0;pending_change<=0;
                    end
                end
                default: begin
                    granted<=0;
                    if(code_on==level) begin
                        pending_change<=0;
                        if(code_on) begin
                            box_l<=raw_left;box_r<=raw_right;
                            box_t<=raw_top;box_b<=raw_bottom;
                        end
                        if((state==LEAD && run_len>=LEAD_MAX) ||
                           (state!=LEAD && run_len>=SYMBOL_MAX)) begin
                            state<=SEARCH;run_len<=0;
                        end else run_len<=run_len+1'b1;
                    end else if(!pending_change)
                        pending_change<=1;
                    else begin
                        // Two consecutive opposite samples confirm a change.
                        pending_change<=0;level<=code_on;run_len<=2;
                        if(code_on) begin
                            box_l<=raw_left;box_r<=raw_right;
                            box_t<=raw_top;box_b<=raw_bottom;
                        end
                        case(state)
                        LEAD: begin
                            if(level && !code_on && run_len>=LEAD_MIN && run_len<=LEAD_MAX)
                                state<=OFF_ONE;
                            else begin state<=SEARCH;run_len<=0;end
                        end
                        OFF_ONE: begin
                            if(!level && code_on && run_len>=SYMBOL_MIN && run_len<=SYMBOL_MAX)
                                state<=ON_GAP;
                            else begin state<=SEARCH;run_len<=0;end
                        end
                        ON_GAP: begin
                            if(level && !code_on && run_len>=SYMBOL_MIN && run_len<=SYMBOL_MAX)
                                state<=OFF_TWO;
                            else begin state<=SEARCH;run_len<=0;end
                        end
                        OFF_TWO: begin
                            if(!level && code_on && run_len>=SYMBOL_MIN && run_len<=SYMBOL_MAX)
                                state<=FINAL_ON;
                            else begin state<=SEARCH;run_len<=0;end
                        end
                        default: begin state<=SEARCH;run_len<=0;end
                        endcase
                    end
                end
                endcase
            end
        end
    end
endmodule

// Four candidates are buffered, spatially matched and temporally updated by
// one shared engine during the long interval between camera frames.
module pen_code_auth_multi #(
    parameter LEAD_MIN=4,LEAD_MAX=6,
    parameter SYMBOL_MIN=2,SYMBOL_MAX=4,
    parameter LOST_FRAMES=20,
    parameter PURPLE_RECOVERY=0,PURPLE_LOST_FRAMES=20
)(
    input clk,rst_n,input frame_valid,
    input candidate_valid,input [2:0] candidate_color,
    input [11:0] candidate_left,candidate_right,
    input [11:0] candidate_top,candidate_bottom,
    input revoke_toggle,
    output reg granted,event_toggle,output [1:0] status,
    output reg target_present,output reg [2:0] target_color,
    output reg target_variant,
    output reg [11:0] target_left,target_right,target_top,target_bottom
);
    localparam LEAD=3'd1,OFF_ONE=3'd2,ON_GAP=3'd3,
               OFF_TWO=3'd4,TAIL_ON=3'd5,EXTRA_OFF=3'd6,B_FINAL=3'd7;
    localparam E_IDLE=0,E_MATCH=1,E_UPDATE=2;
    reg [3:0] track_used,track_level,track_pending,track_seen;
    reg [2:0] track_state[0:3],track_color[0:3];
    reg [3:0] track_run[0:3];
    reg [11:0] track_left[0:3],track_right[0:3];
    reg [11:0] track_top[0:3],track_bottom[0:3];
    reg [3:0] frame_candidate_valid;
    reg [2:0] frame_candidate_color[0:3];
    reg [11:0] frame_left[0:3],frame_right[0:3];
    reg [11:0] frame_top[0:3],frame_bottom[0:3];
    reg [2:0] candidate_count,revoke_sync;
    reg [1:0] engine_state,candidate_index,track_index,update_index;
    reg frame_pending,target_seen;
    reg [6:0] lost_count;
    reg recovery_seen,recovery_ambiguous;
    reg [1:0] recovery_run;
    reg [47:0] recovery_box,recovery_previous;
    function recovery_near;
        input [47:0] a,b;
        input [11:0] pad;
        reg [12:0] ax,ay,bx,by,aw,ah,bw,bh,dx,dy;
        begin
            ax={1'b0,a[47:36]}+{1'b0,a[35:24]};
            ay={1'b0,a[23:12]}+{1'b0,a[11:0]};
            bx={1'b0,b[47:36]}+{1'b0,b[35:24]};
            by={1'b0,b[23:12]}+{1'b0,b[11:0]};
            dx=ax>bx ? ax-bx : bx-ax;dy=ay>by ? ay-by : by-ay;
            aw={1'b0,a[35:24]}-{1'b0,a[47:36]}+1;
            ah={1'b0,a[11:0]}-{1'b0,a[23:12]}+1;
            bw={1'b0,b[35:24]}-{1'b0,b[47:36]}+1;
            bh={1'b0,b[11:0]}-{1'b0,b[23:12]}+1;
            // Width/height ratio must be within 1/2..2, no global search.
            recovery_near=dx<=({1'b0,pad}<<1) && dy<=({1'b0,pad}<<1) &&
                aw<=(bw<<1) && bw<=(aw<<1) && ah<=(bh<<1) && bh<=(ah<<1);
        end
    endfunction
    wire [47:0] candidate_box={candidate_left,candidate_right,candidate_top,candidate_bottom};
    wire [47:0] target_box={target_left,target_right,target_top,target_bottom};
    // Candidate samples precede the end-of-frame pending update. Share the
    // distance/size arithmetic between candidate admission and final consistency.
    // The actual detector emits its last candidate with frame_valid, then goes
    // idle before frame_pending is consumed on the next cycle.
    wire check_consistency=frame_pending;
    wire recovery_geometry=recovery_near(
        check_consistency ? recovery_box : candidate_box,
        check_consistency ? recovery_previous : target_box,
        check_consistency ? 12'd24 : 12'd144);
    wire recovery_candidate=PURPLE_RECOVERY && granted && target_color==5 && !target_variant &&
        candidate_color==5 && recovery_geometry;
    wire recovery_consistent=recovery_geometry;
    integer mi;

    function near_candidate;
        input [11:0] al,ar,at,ab,bl,br,bt,bb;
        reg [12:0] acx2,acy2,bcx2,bcy2,bw,bh;
        reg [11:0] acx,acy,bcx,bcy,dx,dy;
        begin
            acx2={1'b0,al}+{1'b0,ar};acy2={1'b0,at}+{1'b0,ab};
            bcx2={1'b0,bl}+{1'b0,br};bcy2={1'b0,bt}+{1'b0,bb};
            acx=acx2[12:1];acy=acy2[12:1];bcx=bcx2[12:1];bcy=bcy2[12:1];
            dx=acx>=bcx?acx-bcx:bcx-acx;dy=acy>=bcy?acy-bcy:bcy-acy;
            bw={1'b0,br}-{1'b0,bl}+13'd1;bh={1'b0,bb}-{1'b0,bt}+13'd1;
            near_candidate=dx<=(bw>>1)+13'd48 && dy<=(bh>>1)+13'd48;
        end
    endfunction
    wire current_match=track_used[track_index] &&
        frame_candidate_color[candidate_index]==track_color[track_index] &&
        near_candidate(frame_left[candidate_index],frame_right[candidate_index],
                       frame_top[candidate_index],frame_bottom[candidate_index],
                       track_left[track_index],track_right[track_index],
                       track_top[track_index],track_bottom[track_index]);
    wire have_free=~track_used[0]|~track_used[1]|~track_used[2]|~track_used[3];
    wire [1:0] free_index=!track_used[0]?0:!track_used[1]?1:!track_used[2]?2:3;
    wire target_match=granted && candidate_color==target_color &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       target_left,target_right,target_top,target_bottom);
    wire revoke=revoke_sync[2]^revoke_sync[1];
    assign status=granted?2'd2:(|track_used)?2'd1:2'd0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            track_used<=0;track_level<=0;track_pending<=0;track_seen<=0;
            frame_candidate_valid<=0;candidate_count<=0;revoke_sync<=0;
            engine_state<=E_IDLE;candidate_index<=0;track_index<=0;update_index<=0;
            frame_pending<=0;target_seen<=0;lost_count<=0;
            recovery_seen<=0;recovery_ambiguous<=0;recovery_run<=0;
            recovery_box<=0;recovery_previous<=0;
            granted<=0;event_toggle<=0;target_present<=0;target_color<=0;
            target_variant<=0;
            target_left<=0;target_right<=0;target_top<=0;target_bottom<=0;
            for(mi=0;mi<4;mi=mi+1) begin
                track_state[mi]<=LEAD;track_color[mi]<=0;track_run[mi]<=0;
                track_left[mi]<=0;track_right[mi]<=0;
                track_top[mi]<=0;track_bottom[mi]<=0;
                frame_candidate_color[mi]<=0;frame_left[mi]<=0;frame_right[mi]<=0;
                frame_top[mi]<=0;frame_bottom[mi]<=0;
            end
        end else begin
            revoke_sync<={revoke_sync[1:0],revoke_toggle};
            if(revoke) begin
                track_used<=0;track_level<=0;track_pending<=0;track_seen<=0;
                frame_candidate_valid<=0;candidate_count<=0;engine_state<=E_IDLE;
                frame_pending<=0;target_seen<=0;lost_count<=0;
                granted<=0;target_present<=0;target_variant<=0;
                recovery_seen<=0;recovery_ambiguous<=0;recovery_run<=0;
            end else begin
                if(candidate_valid && candidate_count<4 && candidate_color!=0 &&
                   candidate_right>=candidate_left && candidate_bottom>=candidate_top) begin
                    if(granted) begin
                        // A normal match always wins. Recovery is deliberately
                        // slower: one unique, size-compatible candidate in three
                        // consecutive frames, all within a bounded local window.
                        if(recovery_candidate) begin
                            if(recovery_seen) recovery_ambiguous<=1;
                            else begin recovery_seen<=1;recovery_box<=candidate_box;end
                        end
                        if(target_match) begin
                            target_seen<=1;target_present<=1;
                            target_left<=candidate_left;target_right<=candidate_right;
                            target_top<=candidate_top;target_bottom<=candidate_bottom;
                        end
                    end else begin
                        frame_candidate_valid[candidate_count[1:0]]<=1;
                        frame_candidate_color[candidate_count[1:0]]<=candidate_color;
                        frame_left[candidate_count[1:0]]<=candidate_left;
                        frame_right[candidate_count[1:0]]<=candidate_right;
                        frame_top[candidate_count[1:0]]<=candidate_top;
                        frame_bottom[candidate_count[1:0]]<=candidate_bottom;
                        candidate_count<=candidate_count+1'b1;
                    end
                end
                if(frame_valid) frame_pending<=1;

                if(granted && frame_pending) begin
                    frame_pending<=0;target_seen<=0;
                    recovery_seen<=0;recovery_ambiguous<=0;
                    if(target_seen) recovery_run<=0;
                    else if(recovery_seen && !recovery_ambiguous) begin
                        recovery_previous<=recovery_box;
                        if(recovery_run==0 || !recovery_consistent) recovery_run<=1;
                        else if(recovery_run<3) recovery_run<=recovery_run+1'b1;
                    end else recovery_run<=0;
                    if(target_seen) begin target_present<=1;lost_count<=0;end
                    else if(recovery_seen && !recovery_ambiguous &&
                            recovery_run>=2 && recovery_consistent) begin
                        {target_left,target_right,target_top,target_bottom}<=recovery_box;
                        target_present<=1;lost_count<=0;recovery_run<=0;
                    end
                    else begin
                        target_present<=0;
                        if(lost_count>=((PURPLE_RECOVERY && target_color==5 && !target_variant) ? PURPLE_LOST_FRAMES : LOST_FRAMES)-1) begin
                            granted<=0;target_variant<=0;track_used<=0;lost_count<=0;
                        end else lost_count<=lost_count+1'b1;
                    end
                end else if(!granted && frame_pending && engine_state==E_IDLE) begin
                    frame_pending<=0;track_seen<=0;
                    candidate_index<=0;track_index<=0;engine_state<=E_MATCH;
                end else if(engine_state==E_MATCH) begin
                    if(!frame_candidate_valid[candidate_index]) begin
                        if(candidate_index==3) begin update_index<=0;engine_state<=E_UPDATE;end
                        else begin candidate_index<=candidate_index+1'b1;track_index<=0;end
                    end else if(current_match) begin
                        track_seen[track_index]<=1;
                        track_left[track_index]<=frame_left[candidate_index];
                        track_right[track_index]<=frame_right[candidate_index];
                        track_top[track_index]<=frame_top[candidate_index];
                        track_bottom[track_index]<=frame_bottom[candidate_index];
                        if(candidate_index==3) begin update_index<=0;engine_state<=E_UPDATE;end
                        else begin candidate_index<=candidate_index+1'b1;track_index<=0;end
                    end else if(track_index==3) begin
                        if(have_free) begin
                            track_used[free_index]<=1;track_level[free_index]<=1;
                            track_pending[free_index]<=0;track_seen[free_index]<=1;
                            track_state[free_index]<=LEAD;track_run[free_index]<=0;
                            track_color[free_index]<=frame_candidate_color[candidate_index];
                            track_left[free_index]<=frame_left[candidate_index];
                            track_right[free_index]<=frame_right[candidate_index];
                            track_top[free_index]<=frame_top[candidate_index];
                            track_bottom[free_index]<=frame_bottom[candidate_index];
                        end
                        if(candidate_index==3) begin update_index<=0;engine_state<=E_UPDATE;end
                        else begin candidate_index<=candidate_index+1'b1;track_index<=0;end
                    end else track_index<=track_index+1'b1;
                end else if(engine_state==E_UPDATE) begin
                    if(track_used[update_index]) begin
                        if(track_state[update_index]==B_FINAL) begin
                            if(track_seen[update_index]) begin
                                track_pending[update_index]<=0;
                                if(track_run[update_index]>=2) begin
                                    granted<=1;event_toggle<=~event_toggle;
                                    target_present<=1;target_seen<=0;lost_count<=0;
                                    target_color<=track_color[update_index];
                                    target_variant<=1;
                                    target_left<=track_left[update_index];
                                    target_right<=track_right[update_index];
                                    target_top<=track_top[update_index];
                                    target_bottom<=track_bottom[update_index];
                                    track_used<=0;engine_state<=E_IDLE;
                                    frame_candidate_valid<=0;candidate_count<=0;
                                end else track_run[update_index]<=track_run[update_index]+1'b1;
                            end else if(!track_pending[update_index])
                                track_pending[update_index]<=1;
                            else begin track_used[update_index]<=0;track_pending[update_index]<=0;end
                        end else if(track_state[update_index]==TAIL_ON) begin
                            if(track_seen[update_index]) begin
                                track_pending[update_index]<=0;
                                // Staying ON beyond a normal 2..4 frame symbol
                                // identifies code A.  A short ON followed by
                                // another OFF continues as code B.
                                if(track_run[update_index]>=SYMBOL_MAX) begin
                                    granted<=1;event_toggle<=~event_toggle;
                                    target_present<=1;target_seen<=0;lost_count<=0;
                                    target_color<=track_color[update_index];
                                    target_variant<=0;
                                    target_left<=track_left[update_index];
                                    target_right<=track_right[update_index];
                                    target_top<=track_top[update_index];
                                    target_bottom<=track_bottom[update_index];
                                    track_used<=0;engine_state<=E_IDLE;
                                    frame_candidate_valid<=0;candidate_count<=0;
                                end else track_run[update_index]<=track_run[update_index]+1'b1;
                            end else if(!track_pending[update_index])
                                track_pending[update_index]<=1;
                            else begin
                                track_pending[update_index]<=0;
                                if(track_run[update_index]>=SYMBOL_MIN &&
                                   track_run[update_index]<=SYMBOL_MAX) begin
                                    track_level[update_index]<=0;
                                    track_run[update_index]<=2;
                                    track_state[update_index]<=EXTRA_OFF;
                                end else begin
                                    track_used[update_index]<=0;track_run[update_index]<=0;
                                end
                            end
                        end else if(track_seen[update_index]==track_level[update_index]) begin
                            track_pending[update_index]<=0;
                            if((track_state[update_index]==LEAD && track_run[update_index]>=LEAD_MAX) ||
                               (track_state[update_index]!=LEAD && track_run[update_index]>=SYMBOL_MAX)) begin
                                track_used[update_index]<=0;track_run[update_index]<=0;
                            end else track_run[update_index]<=track_run[update_index]+1'b1;
                        end else if(!track_pending[update_index])
                            track_pending[update_index]<=1;
                        else begin
                            track_pending[update_index]<=0;
                            track_level[update_index]<=track_seen[update_index];
                            track_run[update_index]<=2;
                            case(track_state[update_index])
                              LEAD:if(track_level[update_index] && !track_seen[update_index] &&
                                      track_run[update_index]>=LEAD_MIN && track_run[update_index]<=LEAD_MAX)
                                       track_state[update_index]<=OFF_ONE;
                                   else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              OFF_ONE:if(!track_level[update_index] && track_seen[update_index] &&
                                         track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                          track_state[update_index]<=ON_GAP;
                                      else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              ON_GAP:if(track_level[update_index] && !track_seen[update_index] &&
                                        track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                         track_state[update_index]<=OFF_TWO;
                                     else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              OFF_TWO:if(!track_level[update_index] && track_seen[update_index] &&
                                         track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                          track_state[update_index]<=TAIL_ON;
                                      else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              EXTRA_OFF:if(!track_level[update_index] && track_seen[update_index] &&
                                           track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                            track_state[update_index]<=B_FINAL;
                                      else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              default:begin track_used[update_index]<=0;track_run[update_index]<=0;end
                            endcase
                        end
                    end
                    track_seen[update_index]<=0;
                    if(update_index==3) begin
                        engine_state<=E_IDLE;frame_candidate_valid<=0;candidate_count<=0;
                        track_seen<=0;
                    end else update_index<=update_index+1'b1;
                end
            end
        end
    end
endmodule

// Parallel-matcher reference retained for rollback and resource comparison.
// Four independent temporal tracks share one small update engine.  Static
// objects remain ON and time out in LEAD; only an object that follows the
// complete ON/OFF/ON/OFF/ON code can become the authenticated target.
module pen_code_auth_multi_parallel_reference #(
    parameter LEAD_MIN=4,LEAD_MAX=6,
    parameter SYMBOL_MIN=2,SYMBOL_MAX=4,
    parameter LOST_FRAMES=20
)(
    input clk,rst_n,
    input frame_valid,
    input candidate_valid,input [2:0] candidate_color,
    input [11:0] candidate_left,candidate_right,
    input [11:0] candidate_top,candidate_bottom,
    input revoke_toggle,
    output reg granted,event_toggle,
    output [1:0] status,
    output reg target_present,output reg [2:0] target_color,
    output reg [11:0] target_left,target_right,
    output reg [11:0] target_top,target_bottom
);
    localparam LEAD=3'd1,OFF_ONE=3'd2,ON_GAP=3'd3,
               OFF_TWO=3'd4,FINAL_ON=3'd5;
    reg [3:0] track_used,track_level,track_pending,track_seen;
    reg [2:0] track_state[0:3],track_color[0:3];
    reg [3:0] track_run[0:3];
    reg [11:0] track_left[0:3],track_right[0:3];
    reg [11:0] track_top[0:3],track_bottom[0:3];
    reg frame_pending,updating,target_seen;
    reg [1:0] update_index;
    reg [6:0] lost_count;
    reg [2:0] revoke_sync;
    integer ti;

    function near_candidate;
        input [11:0] al,ar,at,ab,bl,br,bt,bb;
        reg [12:0] acx2,acy2,bcx2,bcy2,bw,bh;
        reg [11:0] acx,acy,bcx,bcy,dx,dy;
        begin
            acx2={1'b0,al}+{1'b0,ar};acy2={1'b0,at}+{1'b0,ab};
            bcx2={1'b0,bl}+{1'b0,br};bcy2={1'b0,bt}+{1'b0,bb};
            acx=acx2[12:1];acy=acy2[12:1];bcx=bcx2[12:1];bcy=bcy2[12:1];
            dx=acx>=bcx?acx-bcx:bcx-acx;dy=acy>=bcy?acy-bcy:bcy-acy;
            bw={1'b0,br}-{1'b0,bl}+13'd1;
            bh={1'b0,bb}-{1'b0,bt}+13'd1;
            near_candidate=dx<=(bw>>1)+13'd48 && dy<=(bh>>1)+13'd48;
        end
    endfunction

    wire match0=track_used[0] && candidate_color==track_color[0] &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       track_left[0],track_right[0],track_top[0],track_bottom[0]);
    wire match1=track_used[1] && candidate_color==track_color[1] &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       track_left[1],track_right[1],track_top[1],track_bottom[1]);
    wire match2=track_used[2] && candidate_color==track_color[2] &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       track_left[2],track_right[2],track_top[2],track_bottom[2]);
    wire match3=track_used[3] && candidate_color==track_color[3] &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       track_left[3],track_right[3],track_top[3],track_bottom[3]);
    wire any_match=match0|match1|match2|match3;
    wire [1:0] match_index=match0?0:match1?1:match2?2:3;
    wire have_free=~track_used[0]|~track_used[1]|~track_used[2]|~track_used[3];
    wire [1:0] free_index=!track_used[0]?0:!track_used[1]?1:!track_used[2]?2:3;
    wire target_match=granted && candidate_color==target_color &&
        near_candidate(candidate_left,candidate_right,candidate_top,candidate_bottom,
                       target_left,target_right,target_top,target_bottom);
    wire revoke=revoke_sync[2]^revoke_sync[1];
    assign status=granted?2'd2:(|track_used)?2'd1:2'd0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            track_used<=0;track_level<=0;track_pending<=0;track_seen<=0;
            frame_pending<=0;updating<=0;update_index<=0;
            target_seen<=0;lost_count<=0;revoke_sync<=0;
            granted<=0;event_toggle<=0;target_present<=0;target_color<=0;
            target_left<=0;target_right<=0;target_top<=0;target_bottom<=0;
            for(ti=0;ti<4;ti=ti+1) begin
                track_state[ti]<=LEAD;track_run[ti]<=0;track_color[ti]<=0;
                track_left[ti]<=0;track_right[ti]<=0;
                track_top[ti]<=0;track_bottom[ti]<=0;
            end
        end else begin
            revoke_sync<={revoke_sync[1:0],revoke_toggle};
            if(revoke) begin
                track_used<=0;track_level<=0;track_pending<=0;track_seen<=0;
                frame_pending<=0;updating<=0;target_seen<=0;lost_count<=0;
                granted<=0;target_present<=0;
            end else begin
                // Candidate events occur on four consecutive scan clocks.
                if(candidate_valid && candidate_color!=0 &&
                   candidate_right>=candidate_left && candidate_bottom>=candidate_top) begin
                    if(granted) begin
                        if(target_match) begin
                            target_seen<=1;target_present<=1;
                            target_left<=candidate_left;target_right<=candidate_right;
                            target_top<=candidate_top;target_bottom<=candidate_bottom;
                        end
                    end else if(any_match) begin
                        track_seen[match_index]<=1;
                        track_left[match_index]<=candidate_left;
                        track_right[match_index]<=candidate_right;
                        track_top[match_index]<=candidate_top;
                        track_bottom[match_index]<=candidate_bottom;
                    end else if(have_free) begin
                        track_used[free_index]<=1;track_level[free_index]<=1;
                        track_pending[free_index]<=0;track_seen[free_index]<=1;
                        track_state[free_index]<=LEAD;track_run[free_index]<=0;
                        track_color[free_index]<=candidate_color;
                        track_left[free_index]<=candidate_left;
                        track_right[free_index]<=candidate_right;
                        track_top[free_index]<=candidate_top;
                        track_bottom[free_index]<=candidate_bottom;
                    end
                end
                if(frame_valid) frame_pending<=1;

                if(granted && frame_pending) begin
                    frame_pending<=0;target_seen<=0;
                    if(target_seen) begin target_present<=1;lost_count<=0;end
                    else begin
                        target_present<=0;
                        if(lost_count>=LOST_FRAMES-1) begin
                            granted<=0;track_used<=0;lost_count<=0;
                        end else lost_count<=lost_count+1'b1;
                    end
                end else if(!granted && frame_pending && !updating) begin
                    frame_pending<=0;updating<=1;update_index<=0;
                end else if(updating) begin
                    if(track_used[update_index]) begin
                        if(track_state[update_index]==FINAL_ON) begin
                            if(track_seen[update_index]) begin
                                track_pending[update_index]<=0;
                                if(track_run[update_index]>=2) begin
                                    granted<=1;event_toggle<=~event_toggle;
                                    target_present<=1;target_seen<=0;lost_count<=0;
                                    target_color<=track_color[update_index];
                                    target_left<=track_left[update_index];
                                    target_right<=track_right[update_index];
                                    target_top<=track_top[update_index];
                                    target_bottom<=track_bottom[update_index];
                                    track_used<=0;updating<=0;
                                end else track_run[update_index]<=track_run[update_index]+1'b1;
                            end else if(!track_pending[update_index])
                                track_pending[update_index]<=1;
                            else begin
                                track_used[update_index]<=0;
                                track_pending[update_index]<=0;
                            end
                        end else if(track_seen[update_index]==track_level[update_index]) begin
                            track_pending[update_index]<=0;
                            if((track_state[update_index]==LEAD && track_run[update_index]>=LEAD_MAX) ||
                               (track_state[update_index]!=LEAD && track_run[update_index]>=SYMBOL_MAX)) begin
                                track_used[update_index]<=0;track_run[update_index]<=0;
                            end else track_run[update_index]<=track_run[update_index]+1'b1;
                        end else if(!track_pending[update_index])
                            track_pending[update_index]<=1;
                        else begin
                            track_pending[update_index]<=0;
                            track_level[update_index]<=track_seen[update_index];
                            track_run[update_index]<=2;
                            case(track_state[update_index])
                              LEAD:if(track_level[update_index] && !track_seen[update_index] &&
                                      track_run[update_index]>=LEAD_MIN && track_run[update_index]<=LEAD_MAX)
                                       track_state[update_index]<=OFF_ONE;
                                   else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              OFF_ONE:if(!track_level[update_index] && track_seen[update_index] &&
                                         track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                          track_state[update_index]<=ON_GAP;
                                      else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              ON_GAP:if(track_level[update_index] && !track_seen[update_index] &&
                                        track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                         track_state[update_index]<=OFF_TWO;
                                     else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              OFF_TWO:if(!track_level[update_index] && track_seen[update_index] &&
                                         track_run[update_index]>=SYMBOL_MIN && track_run[update_index]<=SYMBOL_MAX)
                                          track_state[update_index]<=FINAL_ON;
                                      else begin track_used[update_index]<=0;track_run[update_index]<=0;end
                              default:begin track_used[update_index]<=0;track_run[update_index]<=0;end
                            endcase
                        end
                    end
                    track_seen[update_index]<=0;
                    if(update_index==3) begin updating<=0;track_seen<=0;end
                    else update_index<=update_index+1'b1;
                end
            end
        end
    end
endmodule


module edge_detect_4pixel #(
    parameter IMG_WIDTH = 1280,
    parameter EDGE_THRESHOLD = 16
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [3:0]  I_mode,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    output reg         O_detect_valid,
    output reg [11:0]  O_detect_left,
    output reg [11:0]  O_detect_right,
    output reg [11:0]  O_detect_top,
    output reg [11:0]  O_detect_bottom
);

    localparam WORDS_PER_LINE = IMG_WIDTH / 4;

    // Synchronous read-before-write line RAM; prefetch alongside input register.
    (* ram_style = "block" *) reg [31:0] S_line_a [0:WORDS_PER_LINE-1];

    reg [8:0]  S_word_col;
    reg [9:0]  S_line_count;
    reg [7:0]  S_left_gray;
    reg [3:0]  S_mode_sync_1d;
    reg [3:0]  S_mode_sync_2d;
    reg [3:0]  S_mode;
    reg [3:0] S_input_mode;
    reg [95:0] S_input_data;
    wire [31:0] S_gray_in = {rgb_to_gray(I_tdata[95:72]),
        rgb_to_gray(I_tdata[71:48]),rgb_to_gray(I_tdata[47:24]),
        rgb_to_gray(I_tdata[23:0])};
    reg [31:0] S_input_gray;
    reg        S_input_valid;
    reg        S_input_user;
    reg        S_input_last;

    function [7:0] rgb_to_gray;
        input [23:0] rgb;
        reg [9:0] sum;
        begin
            // Y ~= (R + 2G + B) / 4, implemented without multipliers.
            sum = {2'b0,rgb[23:16]} +
                  ({2'b0,rgb[15:8]} << 1) +
                  {2'b0,rgb[7:0]};
            rgb_to_gray = sum[9:2];
        end
    endfunction

    function [7:0] abs_diff;
        input [7:0] a;
        input [7:0] b;
        begin
            abs_diff = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    function [7:0] clip8;
        input signed [12:0] value;
        begin
            if(value < 0)
                clip8 = 8'd0;
            else if(value > 13'sd255)
                clip8 = 8'd255;
            else
                clip8 = value[7:0];
        end
    endfunction



    function [23:0] vintage_filter;
        input [23:0] rgb;
        reg [9:0] r2g;
        reg [8:0] rg,gb;
        reg [13:0] rs,gs,bs;
        begin
            // Exact factorization of the /32 sepia matrix. Shared partial
            // sums reduce adders without changing rounding or saturation.
            r2g={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0};
            rg={1'b0,rgb[23:16]}+{1'b0,rgb[15:8]};
            gb={1'b0,rgb[15:8]}+{1'b0,rgb[7:0]};
            bs=({4'd0,r2g}<<3)+{5'd0,rg}+({6'd0,rgb[7:0]}<<2);
            gs=bs+({4'd0,r2g}<<1)+{5'd0,gb};
            rs=gs+({5'd0,rg}<<1)+{5'd0,gb};
            vintage_filter={clip8($signed({4'd0,rs[13:5]})),
                            clip8($signed({4'd0,gs[13:5]})),
                            clip8($signed({4'd0,bs[13:5]}))};
        end
    endfunction



    // Eight evenly distributed colour levels per channel.  Repeating the
    // retained top three bits maps 0..7 onto approximately 0..255 without a
    // multiplier, divider, RAM or DSP.
    function [7:0] cartoon_channel;
        input [7:0] value;
        begin cartoon_channel={value[7:5],value[7:5],value[7:6]}; end
    endfunction
    function [23:0] cartoon_colour;
        input [23:0] rgb;
        begin cartoon_colour={cartoon_channel(rgb[23:16]),
                              cartoon_channel(rgb[15:8]),
                              cartoon_channel(rgb[7:0])}; end
    endfunction

    function [23:0] apply_filter;
        input [23:0] rgb;
        input [7:0] gray;
        input [7:0] left_gray;
        input [7:0] up_gray;
        input [3:0] mode;
        begin
            case(mode)
                4'd8,4'd10:  apply_filter = vintage_filter(rgb);
                default:    apply_filter = rgb;
            endcase
        end
    endfunction



    wire [7:0] S_gray0 = S_input_gray[7:0];
    wire [7:0] S_gray1 = S_input_gray[15:8];
    wire [7:0] S_gray2 = S_input_gray[23:16];
    wire [7:0] S_gray3 = S_input_gray[31:24];

    // A single previous-line buffer serves the BW gradient and cartoon outlines.
    reg [31:0] S_previous_line;
    // Predict the column the existing processing stage will use next cycle.
    wire [8:0] S_ram_col = S_input_valid ?
        ((S_input_last || S_word_col == WORDS_PER_LINE-1) ? 9'd0 : S_word_col+9'd1) :
        (S_input_user ? 9'd0 : S_word_col);
    always @(posedge I_clk) begin
        if(I_rst_n && I_tvalid) begin
            S_previous_line <= S_line_a[S_ram_col];
            S_line_a[S_ram_col] <= S_gray_in;
        end
    end
    wire S_first_line = S_input_user || (S_line_count == 0);
    wire [7:0] S_mid0 = S_first_line ? S_gray0 : S_previous_line[7:0];
    wire [7:0] S_mid1 = S_first_line ? S_gray1 : S_previous_line[15:8];
    wire [7:0] S_mid2 = S_first_line ? S_gray2 : S_previous_line[23:16];
    wire [7:0] S_mid3 = S_first_line ? S_gray3 : S_previous_line[31:24];

    wire [7:0] S_up0 = S_mid0;
    wire [7:0] S_up1 = S_mid1;
    wire [7:0] S_up2 = S_mid2;
    wire [7:0] S_up3 = S_mid3;
    wire [7:0] S_lft0 = (S_word_col == 0) ? S_gray0 : S_left_gray;

    wire [8:0] S_mag0 = {1'b0,abs_diff(S_gray0,S_lft0)} + {1'b0,abs_diff(S_gray0,S_up0)};
    wire [8:0] S_mag1 = {1'b0,abs_diff(S_gray1,S_gray0)} + {1'b0,abs_diff(S_gray1,S_up1)};
    wire [8:0] S_mag2 = {1'b0,abs_diff(S_gray2,S_gray1)} + {1'b0,abs_diff(S_gray2,S_up2)};
    wire [8:0] S_mag3 = {1'b0,abs_diff(S_gray3,S_gray2)} + {1'b0,abs_diff(S_gray3,S_up3)};

    wire [23:0] S_edge0 = (S_mag0 >= EDGE_THRESHOLD) ? 24'hFFFFFF : 24'h000000;
    wire [23:0] S_edge1 = (S_mag1 >= EDGE_THRESHOLD) ? 24'hFFFFFF : 24'h000000;
    wire [23:0] S_edge2 = (S_mag2 >= EDGE_THRESHOLD) ? 24'hFFFFFF : 24'h000000;
    wire [23:0] S_edge3 = (S_mag3 >= EDGE_THRESHOLD) ? 24'hFFFFFF : 24'h000000;
    // A higher threshold than BW EDGE suppresses small texture/noise and keeps
    // only the stronger dark outlines expected from a cartoon effect.
    localparam [8:0] CARTOON_EDGE_THRESHOLD=9'd36;
    wire [23:0] S_cartoon0=(S_mag0>=CARTOON_EDGE_THRESHOLD) ? 24'h000000:
                            cartoon_colour(S_input_data[23:0]);
    wire [23:0] S_cartoon1=(S_mag1>=CARTOON_EDGE_THRESHOLD) ? 24'h000000:
                            cartoon_colour(S_input_data[47:24]);
    wire [23:0] S_cartoon2=(S_mag2>=CARTOON_EDGE_THRESHOLD) ? 24'h000000:
                            cartoon_colour(S_input_data[71:48]);
    wire [23:0] S_cartoon3=(S_mag3>=CARTOON_EDGE_THRESHOLD) ? 24'h000000:
                            cartoon_colour(S_input_data[95:72]);
    // ROM reads run beside S_input_data/S_input_mode. Preserve exact
    // arithmetic and one sample per cycle, including mode aliases and gaps.
    wire input_cool=I_mode==4 || I_mode==6;
    wire input_warm=I_mode==5 || I_mode==7;
    wire input_contrast=I_mode==13 || I_mode==15;
    wire [2:0] class_r=input_cool?3'd1:input_warm?3'd2:input_contrast?3'd5:3'd0;
    wire [2:0] class_g=input_cool?3'd3:input_warm?3'd4:input_contrast?3'd5:3'd0;
    wire [2:0] class_b=input_cool?3'd2:input_warm?3'd1:input_contrast?3'd5:3'd0;
    wire [95:0] S_lookup_data;
    genvar rom_pair;
    generate for(rom_pair=0;rom_pair<6;rom_pair=rom_pair+1)begin:channel_table
      localparam C0=(rom_pair*2)%3,C1=(rom_pair*2+1)%3;
      localparam L0=(rom_pair*2)/3,L1=(rom_pair*2+1)/3;
      wire [2:0] c0=C0==0?class_r:C0==1?class_g:class_b;
      wire [2:0] c1=C1==0?class_r:C1==1?class_g:class_b;
      filter_channel_rom table_pair(.clk(I_clk),
        .a({c0,I_tdata[L0*24+(2-C0)*8+:8]}),.b({c1,I_tdata[L1*24+(2-C1)*8+:8]}),
        .qa(S_lookup_data[L0*24+(2-C0)*8+:8]),.qb(S_lookup_data[L1*24+(2-C1)*8+:8]));
    end endgenerate
    wire [3:0]  S_mode_for_pixel = S_input_mode;

    wire [23:0] S_filter0 = apply_filter(S_input_data[23:0], S_gray0,S_lft0, S_up0,S_mode_for_pixel);
    wire [23:0] S_filter1 = apply_filter(S_input_data[47:24],S_gray1,S_gray0,S_up1,S_mode_for_pixel);
    wire [23:0] S_filter2 = apply_filter(S_input_data[71:48],S_gray2,S_gray1,S_up2,S_mode_for_pixel);
    wire [23:0] S_filter3 = apply_filter(S_input_data[95:72],S_gray3,S_gray2,S_up3,S_mode_for_pixel);

    wire S_lookup_mode=S_mode_for_pixel==4 || S_mode_for_pixel==6 ||
                       S_mode_for_pixel==5 || S_mode_for_pixel==7 ||
                       S_mode_for_pixel==13 || S_mode_for_pixel==15;
    wire S_fast_edge_mode = (S_mode_for_pixel == 4'd1);
    wire S_cartoon_mode = (S_mode_for_pixel == 4'd2);
    // Legacy board-detector ports retained for source compatibility only.
    always @(posedge I_clk) begin
        O_detect_valid=0;O_detect_left=0;O_detect_right=0;
        O_detect_top=0;O_detect_bottom=0;
    end

    // Break the long AWB -> filter path with one registered input stage.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_input_data  <= 96'd0;
            S_input_mode <= 0;
            S_input_gray  <= 32'd0;
            S_input_valid <= 1'b0;
            S_input_user  <= 1'b0;
            S_input_last  <= 1'b0;
        end else begin
            S_input_data  <= I_tdata;
            S_input_mode <= I_mode;
            S_input_gray  <= S_gray_in;
            S_input_valid <= I_tvalid;
            S_input_user  <= I_tuser;
            S_input_last  <= I_tlast;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_word_col    <= 0;
            S_line_count  <= 0;
            S_left_gray   <= 0;
            S_mode_sync_1d <= 4'd0;
            S_mode_sync_2d <= 4'd0;
            S_mode         <= 4'd0;
            O_tlast       <= 1'b0;
            O_tuser       <= 1'b0;
            O_tdata       <= 96'd0;
            O_tvalid      <= 1'b0;
        end else begin
            S_mode_sync_1d <= I_mode;
            S_mode_sync_2d <= S_mode_sync_1d;
            if(S_input_user) begin
                S_mode       <= S_mode_sync_2d;
                S_word_col   <= 0;
                S_line_count <= 0;
                S_left_gray  <= 0;
            end

            O_tlast  <= S_input_last;
            O_tuser  <= S_input_user;
            O_tvalid <= S_input_valid;

            if(S_input_valid) begin
                S_left_gray <= S_gray3;

                if(S_fast_edge_mode)
                    O_tdata <= {S_edge3,S_edge2,S_edge1,S_edge0};
                else if(S_cartoon_mode)
                    O_tdata <= {S_cartoon3,S_cartoon2,S_cartoon1,S_cartoon0};
                else if(S_lookup_mode)
                    O_tdata <= S_lookup_data;
                else
                    O_tdata <= {S_filter3,S_filter2,S_filter1,S_filter0};

                if(S_input_last || (S_word_col == WORDS_PER_LINE-1)) begin
                    S_word_col   <= 0;
                    S_line_count <= S_line_count + 1'b1;
                    S_left_gray  <= 0;
                end else begin
                    S_word_col <= S_word_col + 1'b1;
                end
            end else begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule

module led_lamp_detector #(
    parameter IMG_WIDTH = 1280
)(
    input wire clk, rst_n,
    input wire [95:0] data,
    input wire valid, user,
    output reg found,
    output reg [2:0] color,
    output reg [11:0] left, right, top, bottom,
    output wire obs_valid, obs_present,
    output wire [2:0] obs_color,
    output wire [11:0] obs_left, obs_right, obs_top, obs_bottom,
    // All valid regions are emitted one per clock while the four stored
    // candidates are scanned.  obs_valid still marks the end of that frame.
    output wire candidate_valid,
    output wire [2:0] candidate_color,
    output wire [11:0] candidate_left,candidate_right,
    output wire [11:0] candidate_top,candidate_bottom
);
    // Active lamp colours: 2 green, 3 blue, 4 yellow, 5 purple.
    // Red/cyan lamp classes are disabled; red PCB detection remains separate.
    // Registered RGB isolates this branch from the AWB combinational path.
    reg [95:0] rgb;
    reg v, fs;
    reg [11:0] x, y;
    wire [11:0] px = fs ? 12'd0 : x;
    wire [11:0] py = fs ? 12'd0 : y;
    function [2:0] hue_vote;
        input [23:0] p;
        reg [9:0] r,g,b;
        begin
            r={2'b0,p[23:16]};g={2'b0,p[15:8]};b={2'b0,p[7:0]};
            hue_vote=0;
            // Paired channels must coexist in ONE pixel, not separate PCB/halo pixels.
            // Mixed-colour evidence excludes the existing all-channel bright core.
            if(!(r>=235 && g>=235 && b>=235)) begin
                // Tight yellow: balanced R/G, low B.  This runs before the
                // relaxed red test so a true balanced yellow remains yellow.
                if(r>=90 && g>=90 && b<120 && r>b+28 && g>b+28 &&
                   r+(r>>3)>=g && g+(g>>3)>=r &&
                   b+(b>>1)<r && b+(b>>1)<g) hue_vote=4;
                else if(r>=80 && b>=80 && g<150 && r>g+20 && b>g+20 &&
                        r+(r>>1)>=b && b+(b>>1)>=r) hue_vote=5;
                else if(g>=80 && g>r+16 && g>b+12 &&
                        r<g-(g>>2)-(g>>3)) hue_vote=2;
                // Keep the existing tolerance for cyan-tinted blue halos.
                else if(b>=80 && b>r+20 && b+8>=g &&
                        r<b-(b>>2)-(b>>3)) hue_vote=3;
            end
        end
    endfunction
    function bright_core;
        input [23:0] p;
        begin
            bright_core=(p[23:16]>=150 && p[15:8]>=150 && p[7:0]>=150);
        end
    endfunction
    // PCB under blue light becomes magenta; under green light becomes yellow.
    // This looser test is permitted only close to a compact bright lamp core.
    function pcb_support;
        input [23:0] p;
        reg [9:0] r,g,b;
        begin
            r={2'b0,p[23:16]};g={2'b0,p[15:8]};b={2'b0,p[7:0]};
            pcb_support=r>=35 && !(r>=220 && g>=220 && b>=220) &&
                ((r>g+(g>>3) && r+r+r>b) ||
                 (g>r && g<r+r && b+(b>>2)<r));
        end
    endfunction
    function [2:0] count4;
        input [3:0] m;
        begin count4={2'b0,m[0]}+{2'b0,m[1]}+{2'b0,m[2]}+{2'b0,m[3]}; end
    endfunction
    wire [3:0] core={bright_core(rgb[95:72]),bright_core(rgb[71:48]),
                      bright_core(rgb[47:24]),bright_core(rgb[23:0])};
    wire [2:0] hits=count4(core);
    wire [11:0] gx0=px+(core[0]?12'd0:core[1]?12'd1:core[2]?12'd2:12'd3);
    wire [11:0] gx1=px+(core[3]?12'd3:core[2]?12'd2:core[1]?12'd1:12'd0);
    wire [2:0] hue0=hue_vote(rgb[23:0]);
    wire [2:0] hue1=hue_vote(rgb[47:24]);
    wire [2:0] hue2=hue_vote(rgb[71:48]);
    wire [2:0] hue3=hue_vote(rgb[95:72]);

    reg [3:0] used, roi_used;
    reg [11:0] lx[0:3], rx[0:3], ty[0:3], by[0:3];
    reg [19:0] area_count[0:3];
    reg [11:0] ql[0:3], qr[0:3], qt[0:3], qb[0:3];
    // A valid core is at most 300x300. Colour ROI is at most 380x380.
    // Add a full image row for the old ROI during frame-start scan updates:
    // 380*380+1280=145680 < 2^18. Support counters are deliberately unchanged.
    localparam COLOR_BITS=$clog2(380*380+IMG_WIDTH+1);
    reg [COLOR_BITS-1:0] ng[0:3], nb[0:3], ny[0:3], np[0:3];
    reg [19:0] support_count[0:3];
    reg [11:0] sl[0:3],sr[0:3],st[0:3],sb[0:3];
    reg [2:0] add_support[0:3];
    reg [11:0] group_left[0:3],group_right[0:3];
    reg rim_inside;
    reg [3:0] support_mask[0:3];
    reg [2:0] add_g[0:3], add_b[0:3], add_y[0:3], add_p[0:3];
    integer i,j,k;
    reg [2:0] match_slot,free_slot;
    reg inside;
    reg [1:0] misses;
    reg [2:0] stable_color,pending_color;
    reg pending_seen;
    wire [12:0] lane_x[0:3];
    assign lane_x[0]={1'b0,px};
    assign lane_x[1]={1'b0,px}+13'd1;
    assign lane_x[2]={1'b0,px}+13'd2;
    assign lane_x[3]={1'b0,px}+13'd3;
    wire [2:0] lane_hue[0:3];
    assign lane_hue[0]=hue0;assign lane_hue[1]=hue1;
    assign lane_hue[2]=hue2;assign lane_hue[3]=hue3;
    wire [3:0] pcb_mask,green_pair,blue_pair,yellow_pair,purple_pair;
    // Cached boundaries are committed with the corresponding ROI on vv4.
    reg [12:0] mixed_l[0:3],mixed_r[0:3],mixed_t[0:3],mixed_b[0:3];
    reg [12:0] outer_l[0:3],outer_r[0:3],outer_t[0:3],outer_b[0:3];
    reg [12:0] inner_l[0:3],inner_r[0:3],inner_t[0:3],inner_b[0:3];
    genvar c;
    generate for(c=0;c<4;c=c+1) begin: shared_classification
        assign pcb_mask[c]=pcb_support(rgb[c*24 +:24]);
        wire [2:0] previous_hue,next_hue;
        if(c==0) assign previous_hue=0;
        else assign previous_hue=lane_hue[c-1];
        if(c==3) assign next_hue=0;
        else assign next_hue=lane_hue[c+1];
        assign green_pair[c]=lane_hue[c]==2 && (previous_hue==2 || next_hue==2);
        assign blue_pair[c]=lane_hue[c]==3 && (previous_hue==3 || next_hue==3);
        assign yellow_pair[c]=lane_hue[c]==4 && (previous_hue==4 || next_hue==4);
        assign purple_pair[c]=lane_hue[c]==5 && (previous_hue==5 || next_hue==5);
    end endgenerate
    always @(*) begin
        match_slot=3'd4; free_slot=3'd4; inside=0; rim_inside=0;
        for(i=0;i<4;i=i+1) begin
            if((!used[i] || (area_count[i]<20 && py>by[i]+3)) && free_slot==4)
                free_slot=i;
            if(used[i] && match_slot==4 && py<=by[i]+2 &&
               gx0<=rx[i]+2 && gx1+2>=lx[i]) match_slot=i;
            add_g[i]=0; add_b[i]=0;
            add_y[i]=0; add_p[i]=0;
            support_mask[i]=0;
            for(k=0;k<4;k=k+1) begin
                inside=roi_used[i] && lane_x[k]>=outer_l[i] &&
                       lane_x[k]<=outer_r[i] && {1'b0,py}>=outer_t[i] &&
                       {1'b0,py}<=outer_b[i];
                if(inside) begin
                    if(pcb_mask[k]) begin
                        support_mask[i][k]=1'b1;
                    end
                    // Colour is sampled at/near the lamp, not across the PCB.
                    rim_inside=lane_x[k]>=inner_l[i] && lane_x[k]<=inner_r[i] &&
                        {1'b0,py}>=inner_t[i] && {1'b0,py}<=inner_b[i];
                    if(rim_inside) begin
                        // Require an adjacent same-colour pixel in the group.
                        // Sparse blue/green rims count, isolated noise does not.
                        if(green_pair[k])
                            add_g[i]=add_g[i]+1'b1;
                        if(blue_pair[k])
                            add_b[i]=add_b[i]+1'b1;
                        if(lane_x[k]>=mixed_l[i] && lane_x[k]<=mixed_r[i] &&
                           {1'b0,py}>=mixed_t[i] && {1'b0,py}<=mixed_b[i]) begin
                            if(yellow_pair[k]) add_y[i]=add_y[i]+1'b1;
                            if(purple_pair[k]) add_p[i]=add_p[i]+1'b1;
                        end
                    end
                end
            end
            add_support[i]=count4(support_mask[i]);
            group_left[i]=12'd4095;
            if(support_mask[i][0]) group_left[i]=lane_x[0]<13'd4095 ? lane_x[0][11:0]:12'd4095;
            else if(support_mask[i][1]) group_left[i]=lane_x[1]<13'd4095 ? lane_x[1][11:0]:12'd4095;
            else if(support_mask[i][2]) group_left[i]=lane_x[2]<13'd4095 ? lane_x[2][11:0]:12'd4095;
            else if(support_mask[i][3]) group_left[i]=lane_x[3]<13'd4095 ? lane_x[3][11:0]:12'd4095;
            group_right[i]=support_mask[i][3] ? lane_x[3][11:0]:
                           support_mask[i][2] ? lane_x[2][11:0]:
                           support_mask[i][1] ? lane_x[1][11:0]:
                           support_mask[i][0] ? lane_x[0][11:0]:12'd0;
        end
    end

    function [22:0] choose_hue;
        input [19:0] g,b,y,p;
        reg [20:0] gg,bb,yy,pp;
        begin
            gg={1'b0,g};bb={1'b0,b};yy={1'b0,y};pp={1'b0,p};
            choose_hue=0;
            if(y>=4 && yy>gg+(gg>>2) && yy>bb+(bb>>2) && yy>pp+(pp>>2))
                choose_hue={3'd4,y};
            else if(p>=4 && pp>gg+(gg>>2) && pp>bb+(bb>>2) && pp>yy+(yy>>2))
                choose_hue={3'd5,p};
            else if(b>=2 && bb>gg+(gg>>2) && bb>yy+(yy>>2) && bb>pp+(pp>>2))
                choose_hue={3'd3,b};
            else if(g>=2 && gg>bb+(bb>>2) && gg>yy+(yy>>2) && gg>pp+(pp>>2))
                choose_hue={3'd2,g};
        end
    endfunction
    reg [285:0] snap[0:3];
    reg scan_busy, vv1,vv2,vv3,vv4;
    reg [1:0] scan_idx,id1,id2,id3,id4;
    reg [285:0] ss1;
    reg [12:0] ww2,hh2,ww3,hh3;
    reg [19:0] ac2,ac3;
    reg core2,core3,roi2,roi3;
    reg [47:0] corebox2,corebox3,corebox4,roibox2,roibox3,roibox4;
    reg [22:0] vote2,vote3,vote4;
    reg [25:0] product3;
    reg ok4,old_roi4;
    reg win_valid;
    reg [19:0] win_score;
    reg [2:0] win_color;
    reg [47:0] win_box;
    wire [12:0] next_l={1'b0,corebox4[47:36]};
    wire [12:0] next_r={1'b0,corebox4[35:24]};
    wire [12:0] next_t={1'b0,corebox4[23:12]};
    wire [12:0] next_b={1'b0,corebox4[11:0]};
    wire [12:0] next_width=next_r-next_l+13'd1;
    wire [12:0] next_mixed=(next_width>>4)+13'd1;
    wire [12:0] next_pad=(next_width>>1)+13'd4;
    wire [12:0] next_rim=(next_width>>3)+13'd3;
    integer boundary_slot;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // Match the combinational boundaries produced by zero ROI coords.
            for(boundary_slot=0;boundary_slot<4;boundary_slot=boundary_slot+1) begin
                mixed_l[boundary_slot]<=0;mixed_t[boundary_slot]<=0;
                mixed_r[boundary_slot]<=13'd1;mixed_b[boundary_slot]<=13'd1;
                outer_l[boundary_slot]<=0;outer_t[boundary_slot]<=0;
                outer_r[boundary_slot]<=13'd4;outer_b[boundary_slot]<=13'd4;
                inner_l[boundary_slot]<=0;inner_t[boundary_slot]<=0;
                inner_r[boundary_slot]<=13'd3;inner_b[boundary_slot]<=13'd3;
            end
        end else if(vv4) begin
            mixed_l[id4]<=next_l>next_mixed ? next_l-next_mixed:13'd0;
            mixed_t[id4]<=next_t>next_mixed ? next_t-next_mixed:13'd0;
            mixed_r[id4]<=next_r+next_mixed;mixed_b[id4]<=next_b+next_mixed;
            outer_l[id4]<=next_l>next_pad ? next_l-next_pad:13'd0;
            outer_t[id4]<=next_t>next_pad ? next_t-next_pad:13'd0;
            outer_r[id4]<=next_r+next_pad;outer_b[id4]<=next_b+next_pad;
            inner_l[id4]<=next_l>next_rim ? next_l-next_rim:13'd0;
            inner_t[id4]<=next_t>next_rim ? next_t-next_rim:13'd0;
            inner_r[id4]<=next_r+next_rim;inner_b[id4]<=next_b+next_rim;
        end
    end
    wire take=old_roi4 && vote4[22:20]!=0 &&
              (!win_valid || vote4[19:0]>win_score);
    wire [2:0] frame_color=take ? vote4[22:20] : win_color;
    // Unheld result of exactly one camera frame.  The visible box below is
    // deliberately held for two missed frames, but 5 Hz authentication must
    // see the real on/off rhythm rather than that display smoothing.
    assign obs_valid   = vv4 && id4==3;
    assign obs_present = win_valid || take;
    assign obs_color   = take ? vote4[22:20] : win_color;
    assign {obs_left,obs_right,obs_top,obs_bottom} =
        take ? roibox4 : win_box;
    assign candidate_valid = vv4 && old_roi4 && vote4[22:20]!=0;
    assign candidate_color = vote4[22:20];
    assign {candidate_left,candidate_right,candidate_top,candidate_bottom}=roibox4;
    integer si;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scan_busy<=0; scan_idx<=0; vv1<=0; vv2<=0; vv3<=0; vv4<=0;
            id1<=0;id2<=0;id3<=0;id4<=0;ss1<=0;
            ww2<=0;hh2<=0;ww3<=0;hh3<=0;ac2<=0;ac3<=0;
            core2<=0;core3<=0;roi2<=0;roi3<=0;ok4<=0;old_roi4<=0;
            corebox2<=0;corebox3<=0;corebox4<=0;
            roibox2<=0;roibox3<=0;roibox4<=0;
            vote2<=0;vote3<=0;vote4<=0;product3<=0;
            win_valid<=0;win_score<=0;win_color<=0;win_box<=0;
            found<=0;color<=0;left<=0;right<=0;top<=0;bottom<=0;misses<=0;
            stable_color<=0;pending_color<=0;pending_seen<=0;
            for(si=0;si<4;si=si+1) snap[si]<=0;
        end else begin
            vv1<=scan_busy;vv2<=vv1;vv3<=vv2;vv4<=vv3;
            if(fs) begin
                for(si=0;si<4;si=si+1)
                    snap[si]<={{{(20-COLOR_BITS){1'b0}},ny[si]},{{(20-COLOR_BITS){1'b0}},np[si]},support_count[si],sl[si],sr[si],st[si],sb[si],
                               used[si],area_count[si],lx[si],rx[si],ty[si],by[si],
                               roi_used[si],ql[si],qr[si],qt[si],qb[si],20'd0,{{(20-COLOR_BITS){1'b0}},ng[si]},{{(20-COLOR_BITS){1'b0}},nb[si]}};
                scan_busy<=1;scan_idx<=0;win_valid<=0;win_score<=0;
            end
            if(scan_busy) begin
                ss1<=snap[scan_idx];id1<=scan_idx;
                if(scan_idx==3) scan_busy<=0;
                else scan_idx<=scan_idx+1'b1;
            end
            if(vv1) begin
                id2<=id1; core2<=ss1[177];ac2<=ss1[176:157];corebox2<=ss1[156:109];
                roi2<=ss1[108] && ss1[245:226]>=8 &&
                       ss1[213:202]>ss1[225:214]+12'd2 &&
                       ss1[189:178]>ss1[201:190]+12'd2;
                roibox2<={
                    ss1[225:214]<ss1[107:96] ? ss1[225:214] : ss1[107:96],
                    ss1[213:202]>ss1[95:84] ? ss1[213:202] : ss1[95:84],
                    ss1[201:190]<ss1[83:72] ? ss1[201:190] : ss1[83:72],
                    ss1[189:178]>ss1[71:60] ? ss1[189:178] : ss1[71:60]};
                ww2<={1'b0,ss1[144:133]}-{1'b0,ss1[156:145]}+13'd1;
                hh2<={1'b0,ss1[120:109]}-{1'b0,ss1[132:121]}+13'd1;
                vote2<=choose_hue(ss1[39:20],ss1[19:0],ss1[285:266],ss1[265:246]);
            end
            if(vv2) begin
                id3<=id2; core3<=core2;ac3<=ac2;corebox3<=corebox2;
                roi3<=roi2;roibox3<=roibox2;vote3<=vote2;ww3<=ww2;hh3<=hh2;
                product3<=ww2*hh2;
            end
            if(vv3) begin
                id4<=id3;corebox4<=corebox3;roibox4<=roibox3;vote4<=vote3;old_roi4<=roi3;
                ok4<=core3 && ac3>=20 && ww3>=6 && hh3>=6 && ww3<=300 && hh3<=300 &&
                     ww3<=(hh3+(hh3>>1)) && hh3<=(ww3+(ww3>>1)) &&
                     ({6'b0,ac3}<<2)>=product3 &&
                     corebox3[47:36]>4 && corebox3[35:24]<IMG_WIDTH-5 &&
                     corebox3[23:12]>4 && corebox3[11:0]<715;
            end
            if(vv4) begin
                if(take) begin win_valid<=1;win_score<=vote4[19:0];
                    win_color<=vote4[22:20];win_box<=roibox4; end
                if(id4==3) begin
                    if(win_valid || take) begin
                        found<=1;misses<=0;
                        if(frame_color==stable_color) begin color<=frame_color;pending_seen<=0;end
                        else if(pending_seen && pending_color==frame_color) begin
                            color<=frame_color;stable_color<=frame_color;pending_seen<=0;
                        end else begin color<=0;pending_color<=frame_color;pending_seen<=1;end
                        {left,right,top,bottom}<=take ? roibox4 : win_box;
                    end else begin
                        pending_seen<=0;
                        // No reliable hue: retain the box briefly, publish UNKNOWN so no gesture fires.
                        color<=0;
                        if(misses<2) misses<=misses+1'b1;
                        else begin found<=0;stable_color<=0;end
                    end
                end
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb<=0; v<=0; fs<=0;
        end else begin rgb<=data; v<=valid; fs<=user; end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0; y<=0; used<=0; roi_used<=0;
            for(j=0;j<4;j=j+1) begin
                lx[j]<=0; rx[j]<=0; ty[j]<=0; by[j]<=0; area_count[j]<=0;
                ql[j]<=0; qr[j]<=0; qt[j]<=0; qb[j]<=0;
                ng[j]<=0; nb[j]<=0; ny[j]<=0; np[j]<=0;
                support_count[j]<=0;sl[j]<=4095;sr[j]<=0;st[j]<=4095;sb[j]<=0;
            end
        end else begin
            if(fs) begin
                x<=0; y<=0; used<=0;
                for(j=0;j<4;j=j+1) begin
                    ng[j]<=0; nb[j]<=0; ny[j]<=0; np[j]<=0;
                    support_count[j]<=0;sl[j]<=4095;sr[j]<=0;st[j]<=4095;sb[j]<=0;
                end
                if(v && hits>=2) begin
                    used[0]<=1; lx[0]<=gx0; rx[0]<=gx1;
                    ty[0]<=0; by[0]<=0; area_count[0]<=hits;
                end
            end else if(v) begin
                for(j=0;j<4;j=j+1) begin
                    ng[j]<=ng[j]+add_g[j]; nb[j]<=nb[j]+add_b[j];
                    ny[j]<=ny[j]+add_y[j]; np[j]<=np[j]+add_p[j];
                    support_count[j]<=support_count[j]+add_support[j];
                    if(add_support[j]!=0) begin
                        if(group_left[j]<sl[j]) sl[j]<=group_left[j];
                        if(group_right[j]>sr[j]) sr[j]<=group_right[j];
                        if(py<st[j]) st[j]<=py;
                        sb[j]<=py;
                    end
                end
                if(hits>=2) begin
                    if(match_slot!=3'd4) begin
                        if(gx0<lx[match_slot]) lx[match_slot]<=gx0;
                        if(gx1>rx[match_slot]) rx[match_slot]<=gx1;
                        by[match_slot]<=py;
                        area_count[match_slot]<=area_count[match_slot]+hits;
                    end else if(free_slot!=3'd4) begin
                        used[free_slot]<=1; lx[free_slot]<=gx0; rx[free_slot]<=gx1;
                        ty[free_slot]<=py; by[free_slot]<=py; area_count[free_slot]<=hits;
                    end
                end
            end
            if(v) begin
                if(px==IMG_WIDTH-4) begin x<=0; y<=py+1'b1; end
                else x<=px+4;
            end
            if(vv4) begin
                roi_used[id4]<=ok4;
                {ql[id4],qr[id4],qt[id4],qb[id4]}<=corebox4;
            end
        end
    end
endmodule



// LED image-plane speed. The measured target box height represents 25 mm.
// Coordinates are compared across fresh CAMERA observations, never HDMI frames.
// Distance approximation max(dx,dy)+3/8*min(dx,dy), error below about 7%.
// All products/division/BCD conversion are serial; no image RAM or DSP required.
module led_speed_estimator #(
 parameter CLK_HZ=60000000, WINDOW_MS=200, LOST_MS=120,
 parameter IMG_WIDTH=1280, IMG_HEIGHT=720, BOX_MM=25, DEAD_PX=2
)(input clk,rst_n,sample,auth_valid,auth_event,variant,present,
 input [2:0] color,input [11:0] left,right,top,bottom,
 output reg valid,output reg [15:0] bcd);
 localparam MS_DIV=CLK_HZ/1000;
 localparam MS_BITS=$clog2(MS_DIV+1);
 reg [MS_BITS-1:0] ms_div;
 reg [15:0] now_ms,last_seen,anchor_ms;
 reg anchored;reg [4:0] identity;
 reg [11:0] anchor_x,anchor_y,anchor_h;
 wire [12:0] sx={1'b0,left}+right,sy={1'b0,top}+bottom;
 wire [11:0] cx=sx[12:1],cy=sy[12:1];
 wire [12:0] height={1'b0,bottom}-{1'b0,top}+1'b1;
 wire good=auth_valid && present && color!=0 && right>=left && bottom>=top &&
   right<IMG_WIDTH && bottom<IMG_HEIGHT && height>=4 && height<=300;
 wire [4:0] current_id={auth_event,variant,color};
 wire [15:0] elapsed=now_ms-anchor_ms,age=now_ms-last_seen;
 wire [11:0] dx=cx>=anchor_x?cx-anchor_x:anchor_x-cx;
 wire [11:0] dy=cy>=anchor_y?cy-anchor_y:anchor_y-cy;
 wire [11:0] hi=dx>=dy?dx:dy,lo=dx>=dy?dy:dx;
 wire [14:0] lo3={3'b0,lo}+({3'b0,lo}<<1);
 wire [12:0] distance=(dx<=DEAD_PX && dy<=DEAD_PX)?13'd0:
   {1'b0,hi}+{1'b0,lo3[14:3]};
 wire [13:0] height_sum={1'b0,height}+{2'b0,anchor_h};
 wire [12:0] mean_height=height_sum[13:1];
 reg [2:0] state;reg [5:0] count;
 reg [31:0] n_acc,n_factor,d_acc,d_factor;
 reg [15:0] n_bits,d_bits;
 reg [31:0] denominator,division;
 reg [32:0] remainder;
 wire [31:0] n_next=n_acc+(n_bits[0]?n_factor:32'd0);
 wire [31:0] d_next=d_acc+(d_bits[0]?d_factor:32'd0);
 wire [32:0] trial={remainder[31:0],division[31]};
 wire subtract=trial>={1'b0,denominator};
 wire [32:0] rem_next=subtract?trial-{1'b0,denominator}:trial;
 reg [13:0] binary,previous;
 reg [15:0] decimal;
 reg have_previous;
 reg [15:0] adjusted;
 integer k;
 always @*begin
   adjusted=decimal;
   for(k=0;k<4;k=k+1)if(decimal[k*4+:4]>=5)adjusted[k*4+:4]=decimal[k*4+:4]+4'd3;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ms_div<=0;now_ms<=0;end
  else if(ms_div==MS_DIV-1)begin ms_div<=0;now_ms<=now_ms+1'b1;end
  else ms_div<=ms_div+1'b1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   last_seen<=0;anchor_ms<=0;anchored<=0;identity<=0;
   anchor_x<=0;anchor_y<=0;anchor_h<=0;valid<=0;bcd<=0;
   state<=0;count<=0;n_acc<=0;n_factor<=0;d_acc<=0;d_factor<=0;n_bits<=0;d_bits<=0;
   denominator<=0;division<=0;remainder<=0;binary<=0;previous<=0;decimal<=0;have_previous<=0;
  end else if(!auth_valid || (sample && (!good || (anchored && current_id!=identity))) ||
      (anchored && age>=LOST_MS && !(sample && good)))begin
   anchored<=0;valid<=0;bcd<=0;state<=0;have_previous<=0;
  end else begin
   if(sample && good)begin
    last_seen<=now_ms;
    if(!anchored)begin
     anchored<=1;identity<=current_id;anchor_x<=cx;anchor_y<=cy;anchor_h<=height;
     anchor_ms<=now_ms;valid<=0;have_previous<=0;
    end else if(elapsed>=WINDOW_MS && state==0)begin
     // speed in 0.1 cm/s = pixels * BOX_MM * 1000 / (height * milliseconds).
     n_acc<=0;n_factor<={19'd0,distance};n_bits<=BOX_MM*1000;
     d_acc<=0;d_factor<={19'd0,mean_height};d_bits<=elapsed;
     count<=0;state<=1;
     anchor_x<=cx;anchor_y<=cy;anchor_h<=height;anchor_ms<=now_ms;
    end
   end
   case(state)
    1:begin
     n_acc<=n_next;d_acc<=d_next;n_factor<=n_factor<<1;d_factor<=d_factor<<1;
     n_bits<=n_bits>>1;d_bits<=d_bits>>1;
     if(count==15)begin denominator<=d_next;division<=n_next;remainder<=0;count<=0;state<=2;end
     else count<=count+1'b1;
    end
    2:begin
     remainder<=rem_next;division<={division[30:0],subtract};
     if(count==31)begin count<=0;state<=3;end else count<=count+1'b1;
    end
    3:begin
     // Clamp at 999.9 cm/s; a stationary interval immediately reads zero.
     if(division==0)begin binary<=0;previous<=0;end
     else if(division>9999)begin binary<=9999;previous<=9999;end
     else begin
      binary<=have_previous?({1'b0,previous}+division[13:0])>>1:division[13:0];
      previous<=have_previous?({1'b0,previous}+division[13:0])>>1:division[13:0];
     end
     have_previous<=1;decimal<=0;count<=0;state<=4;
    end
    4:begin
     decimal<={adjusted[14:0],binary[13]};binary<=binary<<1;
     if(count==13)state<=5;else count<=count+1'b1;
    end
    5:begin bcd<=decimal;valid<=1;state<=0;end
    default:begin end
   endcase
  end
 end
endmodule

// Source holds the complete display result until the HDMI SOF acknowledges it.
module led_speed_mailbox_tx(input clk,rst_n,input [16:0] value,input ack,
 output reg [16:0] payload,output reg request);
 (* ASYNC_REG="TRUE" *)reg[2:0] ack_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ack_sync<=0;payload<=0;request<=0;end
  else begin
   ack_sync<={ack_sync[1:0],ack};
   if(ack_sync[2]==request && value!=payload)begin payload<=value;request<=~request;end
  end
 end
endmodule
module led_speed_mailbox_rx(input clk,rst_n,tick,input [16:0] payload,input request,
 output reg ack,output reg [16:0] value);
 (* ASYNC_REG="TRUE" *)reg[2:0] req_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin req_sync<=0;ack<=0;value<=0;end
  else begin
   req_sync<={req_sync[1:0],request};
   if(tick && req_sync[2]!=ack)begin value<=payload;ack<=req_sync[2];end
  end
 end
endmodule
