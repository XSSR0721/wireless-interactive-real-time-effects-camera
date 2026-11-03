module visual_follow_axis #(
    parameter HOME_US=1500, MIN_US=1000, MAX_US=2000,
    parameter START_PX=16, STOP_PX=8,
    parameter GAIN_SHIFT=6, MAX_STEP_Q4=48, ACCEL_Q4=2
)(
    input wire clk,rst_n,enable,sample,
    input wire signed [12:0] error_px,
    output wire [11:0] pulse
);
    // Q12.4 position, Q4 pulse increment per observation. At 30 fps the
    // default maximum is 90 us/s; gain is 1/64 us per pixel per observation.
    reg [15:0] position_q4;
    reg signed [17:0] filtered_q4;
    reg signed [9:0] velocity_q4;
    reg seeded,active,pending,pending_negative;
    wire signed [17:0] sample_q4={{1{error_px[12]}},error_px,4'b0};
    wire signed [18:0] filter_sum=
        $signed({filtered_q4[17],filtered_q4})+
        $signed({sample_q4[17],sample_q4});
    wire signed [17:0] filtered_next=seeded ? (filter_sum>>>1) : sample_q4;
    wire [17:0] magnitude=filtered_next<0 ? -filtered_next : filtered_next;
    wire [12:0] raw_magnitude=error_px<0 ? -error_px : error_px;
    wire negative=filtered_next[17];
    wire direction_matches=(negative==error_px[12]);
    wire [17:0] proportional=magnitude>>GAIN_SHIFT;
    wire [9:0] speed=proportional>MAX_STEP_Q4 ? MAX_STEP_Q4 :
        (proportional==0 ? 10'd1 : proportional[9:0]);
    wire signed [9:0] desired=negative ? -$signed(speed) : $signed(speed);
    reg signed [10:0] delta_velocity;
    reg signed [9:0] next_velocity;
    reg signed [18:0] proposed;
    reg [15:0] next_position;
    always @* begin
        delta_velocity=$signed({desired[9],desired})-
                       $signed({velocity_q4[9],velocity_q4});
        if(delta_velocity>ACCEL_Q4) next_velocity=velocity_q4+ACCEL_Q4;
        else if(delta_velocity < -ACCEL_Q4) next_velocity=velocity_q4-ACCEL_Q4;
        else next_velocity=desired;
        proposed=$signed({3'b000,position_q4})+next_velocity;
        if(proposed<MIN_US*16) begin
            next_position=MIN_US*16;next_velocity=0;
        end else if(proposed>MAX_US*16) begin
            next_position=MAX_US*16;next_velocity=0;
        end else next_position=proposed[15:0];
    end
    assign pulse=(position_q4+16'd8)>>4;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            position_q4<=HOME_US*16;filtered_q4<=0;velocity_q4<=0;
            seeded<=0;active<=0;pending<=0;pending_negative<=0;
        end else if(!enable) begin
            // Hold commanded position, discard stale filter and velocity.
            filtered_q4<=0;velocity_q4<=0;seeded<=0;active<=0;pending<=0;
        end else if(sample) begin
            filtered_q4<=filtered_next;seeded<=1;
            if(raw_magnitude<=STOP_PX) begin
                // Stop from the current raw observation, not a delayed filter.
                filtered_q4<=0;seeded<=0;active<=0;pending<=0;velocity_q4<=0;
            end else if(!direction_matches) begin
                active<=0;pending<=0;velocity_q4<=0;
            end else if((active && pending_negative==negative) ||
                        (magnitude>=START_PX*16 && pending &&
                         pending_negative==negative)) begin
                active<=1;pending<=1;pending_negative<=negative;
                position_q4<=next_position;velocity_q4<=next_velocity;
            end else begin
                active<=0;velocity_q4<=0;
                pending<=magnitude>=START_PX*16;
                pending_negative<=negative;
            end
        end
    end
endmodule

module pan_feedback_guard #(
    parameter WINDOW_SAMPLES=24, GROWTH_PX=24, TRAVEL_US=8, START_PX=16
)(
    input wire clk,rst_n,clear,enable,sample,
    input wire signed [12:0] error_px,
    input wire [11:0] pulse,
    output reg fault
);
    reg watching,reference_negative,strike;
    reg [7:0] count;
    reg [12:0] baseline_error;
    reg [11:0] baseline_pulse;
    wire [12:0] magnitude=error_px<0 ? -error_px : error_px;
    wire [12:0] travel=pulse>=baseline_pulse ?
        {1'b0,pulse}-{1'b0,baseline_pulse} :
        {1'b0,baseline_pulse}-{1'b0,pulse};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            fault<=0;watching<=0;reference_negative<=0;strike<=0;
            count<=0;baseline_error<=0;baseline_pulse<=0;
        end else if(clear) begin
            fault<=0;watching<=0;strike<=0;count<=0;
        end else if(!enable) begin
            watching<=0;strike<=0;count<=0;
        end else if(sample && !fault) begin
            if(magnitude<START_PX) begin
                watching<=0;strike<=0;count<=0;
            end else if(!watching || reference_negative!=error_px[12]) begin
                watching<=1;reference_negative<=error_px[12];strike<=0;
                count<=0;baseline_error<=magnitude;baseline_pulse<=pulse;
            end else if(count==WINDOW_SAMPLES-1) begin
                count<=0;baseline_error<=magnitude;baseline_pulse<=pulse;
                if(travel>=TRAVEL_US &&
                   {1'b0,magnitude}>={1'b0,baseline_error}+GROWTH_PX) begin
                    if(strike) fault<=1;
                    strike<=1;
                end else strike<=0;
            end else count<=count+1'b1;
        end
    end
endmodule

module purple_led_servo #(
    parameter CLK_HZ=50000000,
    parameter IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter PAN_REVERSE=1, TILT_REVERSE=0,
    parameter LOST_US=2200000, FRESH_US=120000,
    parameter PAN_START_PX=16,PAN_STOP_PX=8,
    parameter TILT_START_PX=12,TILT_STOP_PX=6,
    parameter GAIN_SHIFT=6,MAX_STEP_Q4=32,ACCEL_Q4=2,
    parameter PAN_HOME_US=1500,PAN_MIN_US=1000,PAN_MAX_US=2000,
    parameter TILT_HOME_US=1500,TILT_MIN_US=1167,TILT_MAX_US=1833
)(
    input wire cam_clk,clk,rst_n,
    input wire detect_update,detect_valid,auth_valid,auth_event,
    input wire [2:0] detect_color,
    input wire [11:0] lamp_left,lamp_right,lamp_top,lamp_bottom,
    output reg pan_pwm,tilt_pwm,
    output wire [5:0] status
);
    reg [1:0] cam_release,sys_release;
    always @(posedge cam_clk or negedge rst_n)
        if(!rst_n) cam_release<=0;else cam_release<={cam_release[0],1'b1};
    always @(posedge clk or negedge rst_n)
        if(!rst_n) sys_release<=0;else sys_release<={sys_release[0],1'b1};

    // Stable request/ack mailbox: a busy mailbox drops, never overwrites data.
    reg request,acknowledge;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,req_sync;
    reg [24:0] mailbox;
    wire [12:0] sum_x={1'b0,lamp_left}+{1'b0,lamp_right};
    wire [12:0] sum_y={1'b0,lamp_top}+{1'b0,lamp_bottom};
    wire target_good=detect_valid && detect_color==3'd5 &&
        lamp_left<=lamp_right && lamp_top<=lamp_bottom &&
        lamp_right<IMG_WIDTH && lamp_bottom<IMG_HEIGHT;
    always @(posedge cam_clk or negedge rst_n) begin
        if(!rst_n) begin request<=0;ack_sync<=0;mailbox<=0;end
        else if(!cam_release[1]) begin request<=0;ack_sync<=0;mailbox<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(detect_update && request==ack_sync[1]) begin
                mailbox<={auth_event,auth_valid,target_good,sum_x[11:1],sum_y[11:1]};
                request<=~request;
            end
        end
    end
    always @(posedge clk or negedge rst_n)
        if(!rst_n) req_sync<=0;
        else if(!sys_release[1]) req_sync<=0;
        else req_sync<={req_sync[0],request};

    localparam US_DIV=CLK_HZ/1000000;
    localparam DIV_BITS=(US_DIV>1)?$clog2(US_DIV):1;
    localparam AGE_BITS=$clog2(LOST_US+1);
    reg [DIV_BITS-1:0] us_divider;
    reg [14:0] frame_us;
    reg [AGE_BITS-1:0] age_us,rx_age_us;
    wire us_tick=us_divider==US_DIV-1;
    wire frame_tick=us_tick && frame_us==19999;
    reg anchor_valid,target_present,event_seen,reauth_required;
    reg [10:0] origin_x,origin_y;
    reg [2:0] reference_count;
    reg [10:0] reference_x,reference_y;
    reg [13:0] reference_sum_x,reference_sum_y;
    wire [10:0] current_x=mailbox[21:11],current_y=mailbox[10:0];
    wire signed [12:0] dx=$signed({2'b00,current_x})-$signed({2'b00,origin_x});
    wire signed [12:0] dy=$signed({2'b00,current_y})-$signed({2'b00,origin_y});
    reg signed [12:0] error_pan,error_tilt;
    reg axis_sample;
    // No new observation means no position integration. Keep filter/velocity
    // through brief gaps only; FRESH_US still clears them after 120ms.
    wire enabled=anchor_valid && age_us<FRESH_US;
    wire reference_stable=
        (current_x>=reference_x ? current_x-reference_x : reference_x-current_x)<=8 &&
        (current_y>=reference_y ? current_y-reference_y : reference_y-current_y)<=8;
    wire [11:0] pulse_pan,pulse_tilt;
    wire pan_fault;
    pan_feedback_guard #(.START_PX(PAN_START_PX)) pan_guard(
        .clk(clk),.rst_n(rst_n && sys_release[1]),.clear(!anchor_valid),
        .enable(enabled),.sample(axis_sample),.error_px(error_pan),
        .pulse(pulse_pan),.fault(pan_fault));
    reg [11:0] pwm_pan_us,pwm_tilt_us;
    visual_follow_axis #(
        .HOME_US(PAN_HOME_US),.MIN_US(PAN_MIN_US),.MAX_US(PAN_MAX_US),
        .START_PX(PAN_START_PX),.STOP_PX(PAN_STOP_PX),
        .GAIN_SHIFT(GAIN_SHIFT),.MAX_STEP_Q4(MAX_STEP_Q4),.ACCEL_Q4(ACCEL_Q4)
    ) pan_motion(
        .clk(clk),.rst_n(rst_n && sys_release[1]),.enable(enabled && !pan_fault),
        .sample(axis_sample),.error_px(error_pan),.pulse(pulse_pan));
    visual_follow_axis #(
        .HOME_US(TILT_HOME_US),.MIN_US(TILT_MIN_US),.MAX_US(TILT_MAX_US),
        .START_PX(TILT_START_PX),.STOP_PX(TILT_STOP_PX),
        .GAIN_SHIFT(GAIN_SHIFT),.MAX_STEP_Q4(MAX_STEP_Q4),.ACCEL_Q4(ACCEL_Q4)
    ) tilt_motion(
        .clk(clk),.rst_n(rst_n && sys_release[1]),.enable(enabled),
        .sample(axis_sample),.error_px(error_tilt),.pulse(pulse_tilt));
    // Status bit 5: latched pan divergence fault (previously tilt-away-home).
    assign status={pan_fault,pulse_pan!=PAN_HOME_US,
                   enabled && target_present,anchor_valid,target_present && age_us<FRESH_US,
                   rx_age_us<FRESH_US};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            acknowledge<=0;us_divider<=0;frame_us<=0;
            age_us<=LOST_US;rx_age_us<=LOST_US;
            anchor_valid<=0;target_present<=0;event_seen<=0;reauth_required<=0;
            origin_x<=0;origin_y<=0;error_pan<=0;error_tilt<=0;axis_sample<=0;
            reference_count<=0;reference_x<=0;reference_y<=0;
            reference_sum_x<=0;reference_sum_y<=0;
            pwm_pan_us<=PAN_HOME_US;pwm_tilt_us<=TILT_HOME_US;
            pan_pwm<=0;tilt_pwm<=0;
        end else if(!sys_release[1]) begin
            acknowledge<=0;us_divider<=0;frame_us<=0;
            age_us<=LOST_US;rx_age_us<=LOST_US;
            anchor_valid<=0;target_present<=0;event_seen<=0;reauth_required<=0;
            origin_x<=0;origin_y<=0;error_pan<=0;error_tilt<=0;axis_sample<=0;
            reference_count<=0;reference_x<=0;reference_y<=0;
            reference_sum_x<=0;reference_sum_y<=0;
            pwm_pan_us<=PAN_HOME_US;pwm_tilt_us<=TILT_HOME_US;
            pan_pwm<=0;tilt_pwm<=0;
        end else begin
            axis_sample<=0;
            // Latch widths only at the PWM frame boundary, including tilt.
            pan_pwm<=frame_us<pwm_pan_us;
            tilt_pwm<=frame_us>=10000 && frame_us<10000+pwm_tilt_us;
            if(us_tick) begin
                us_divider<=0;
                if(age_us<LOST_US) age_us<=age_us+1'b1;
                else begin
                    if(anchor_valid) reauth_required<=1;
                    anchor_valid<=0;target_present<=0;reference_count<=0;
                end
                if(rx_age_us<LOST_US) rx_age_us<=rx_age_us+1'b1;
                if(frame_tick) begin
                    frame_us<=0;pwm_pan_us<=pulse_pan;pwm_tilt_us<=pulse_tilt;
                end else frame_us<=frame_us+1'b1;
            end else us_divider<=us_divider+1'b1;

            if(req_sync[1]!=acknowledge) begin
                acknowledge<=req_sync[1];rx_age_us<=0;
                if(!mailbox[23]) begin
                    anchor_valid<=0;target_present<=0;reference_count<=0;
                    event_seen<=mailbox[24];reauth_required<=0;
                end else if(reauth_required && mailbox[24]==event_seen) begin
                    anchor_valid<=0;target_present<=0;
                end else if(mailbox[22]) begin
                    age_us<=0;target_present<=1;
                    if(!anchor_valid || mailbox[24]!=event_seen) begin
                        // Average four consecutive stable observations before
                        // enabling movement. Never rebase during normal tracking.
                        target_present<=0;error_pan<=0;error_tilt<=0;
                        event_seen<=mailbox[24];reauth_required<=0;
                        if(mailbox[24]!=event_seen || reference_count==0 ||
                           !reference_stable) begin
                            anchor_valid<=0;reference_count<=1;
                            reference_x<=current_x;reference_y<=current_y;
                            reference_sum_x<=current_x;reference_sum_y<=current_y;
                        end else if(reference_count==3) begin
                            origin_x<=(reference_sum_x+current_x+14'd2)>>2;
                            origin_y<=(reference_sum_y+current_y+14'd2)>>2;
                            reference_count<=0;anchor_valid<=1;
                        end else begin
                            reference_count<=reference_count+1'b1;
                            reference_sum_x<=reference_sum_x+current_x;
                            reference_sum_y<=reference_sum_y+current_y;
                        end
                    end else begin
                        error_pan<=PAN_REVERSE ? -dx : dx;
                        error_tilt<=TILT_REVERSE ? -dy : dy;
                        axis_sample<=1;
                    end
                end else begin
                    // Hold position without consuming stale error. Brief gaps
                    // retain motion state; a long gap is cleared by freshness.
                    target_present<=0;
                    if(!anchor_valid) reference_count<=0;
                end
            end
        end
    end
endmodule
