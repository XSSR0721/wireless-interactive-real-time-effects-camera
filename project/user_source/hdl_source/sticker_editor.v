// Camera-domain editor. Gestures and yellow confirmation use fresh RAW frames.
// UI state: 0 idle, 1 menu, 2 size, 3 position, 4 new, 5 select, 6 return.
// Slot: used[31], asset[2]=[30], size[29:23], left[22:12], top[11:2], asset[1:0].
module sticker_editor #(
    parameter CLK_HZ=60000000, IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter HOLD_MS=400, ACQUIRE_MS=100, LOST_MS=3000,
    parameter SETTLE_MS=100, ASSET_COUNT=4, DELETE_HOLD_MS=500
)(
    input clk,rst_n,frame_valid,frame_present,input [2:0] color,
    input [11:0] left,right,top,bottom,
    output reg [171:0] config_bus,output reg beep,
    output wire buzzer_n
);
    localparam IDLE=0,MENU=1,SIZE=2,POSITION=3,NEW=4,SELECT=5,RETURN=6;
    reg [2:0] state;
    reg [31:0] saved[0:3],work[0:3];
    reg [1:0] selected,old_selected;
    reg selected_valid,old_selected_valid;
    reg [11:0] menu_x,menu_y,op_x,op_y,last_x,last_y,dwell_x,dwell_y;
    reg [11:0] base_x,base_y,size_prev_y;
    reg [6:0] base_size;
    reg [15:0] now_ms,last_good,entered,dwell_start;
    reg [15:0] acquisition_start;
    reg acquiring,dwell,armed,rebase;
    reg [2:0] dwell_direction;
    reg [9:0] progress;
    reg [2:0] notice; // 1 empty, 2 full, 3 confirmed, 4 cancelled, 5 delete pending
    reg [15:0] notice_start;
    wire confirming,confirm_pulse;
    wire editing=(state>=SIZE && state<=SELECT);
    reg [15:0] tone_ms;
    localparam MS_DIV=CLK_HZ/1000;
    localparam MS_BITS=$clog2(MS_DIV+1);
    reg [MS_BITS-1:0] ms_count;
    wire ms_tick=ms_count==MS_DIV-1;
    wire [12:0] sum_x={1'b0,left}+{1'b0,right};
    wire [12:0] sum_y={1'b0,top}+{1'b0,bottom};
    wire [11:0] cx=sum_x[12:1],cy=sum_y[12:1];
    wire blue=frame_present && color==3 && right>=left && bottom>=top &&
              right<IMG_WIDTH && bottom<IMG_HEIGHT && right-left>=5 && bottom-top>=5;
    wire yellow=frame_present && color==4 && right>=left && bottom>=top &&
              right<IMG_WIDTH && bottom<IMG_HEIGHT && right-left>=5 && bottom-top>=5;
    wire [11:0] mdx=cx>=menu_x ? cx-menu_x:menu_x-cx;
    wire [11:0] mdy=cy>=menu_y ? cy-menu_y:menu_y-cy;
    wire at_menu=mdx<=24 && mdy<=24;
    wire [11:0] odx=cx>=op_x ? cx-op_x:op_x-cx;
    wire [11:0] ody=cy>=op_y ? cy-op_y:op_y-cy;
    wire at_op=odx<=24 && ody<=24;
    wire [11:0] hold_dx=cx>=dwell_x ? cx-dwell_x:dwell_x-cx;
    wire [11:0] hold_dy=cy>=dwell_y ? cy-dwell_y:dwell_y-cy;
    // Require blue in this edit session, then sustained yellow. No blink code.
    yellow_sticker_confirm u_yellow_confirm(
        .clk(clk),.rst_n(rst_n),.enable(editing),.now_ms(now_ms),
        .frame_valid(frame_valid),.blue(blue),.yellow(yellow),
        .busy(confirming),.confirmed(confirm_pulse)
    );
    function [15:0] elapsed;
        input [15:0] current_time,previous_time;
        begin elapsed=current_time-previous_time;end
    endfunction
    // Dominant axis with a 16 pixel margin avoids diagonal ambiguity.
    wire [2:0] menu_direction=mdx>=64 && {1'b0,mdx}>={1'b0,mdy}+14'd16 ?
                             (cx<menu_x ? 3'd1:3'd2):
                             mdy>=64 && {1'b0,mdy}>={1'b0,mdx}+14'd16 ?
                             (cy<menu_y ? 3'd3:3'd4):3'd0;
    wire [2:0] op_direction=odx>=48 && {1'b0,odx}>={1'b0,ody}+14'd12 ?
                           (cx<op_x ? 3'd1:3'd2):
                           ody>=48 && {1'b0,ody}>={1'b0,odx}+14'd12 ?
                           (cy<op_y ? 3'd3:3'd4):3'd0;
    function [11:0] width_for;
        input [6:0] s;
        begin width_for=s>112 ? 12'd256:12'd32+{4'd0,s,1'b0};end
    endfunction
    function [11:0] height_for;
        input [11:0] width;
        input [2:0] asset;
        begin height_for=asset<2 ? width:((asset==2 || asset==3) ? (width>>1):(width<<1));end
    endfunction
    function [11:0] clamp_start;
        input signed [14:0] value;
        input [11:0] span,screen;
        begin
            if(value<0) clamp_start=0;
            else if(value>$signed({3'b0,screen-span})) clamp_start=screen-span;
            else clamp_start=value[11:0];
        end
    endfunction
    reg [1:0] free_slot,next_slot;
    reg has_free,has_next;
    reg [6:0] resized;
    // Two-fresh-blue-frame mean: one observation of lag, no recursive tail.
    wire [12:0] smooth_sum={1'b0,size_prev_y}+{1'b0,cy};
    wire [11:0] smooth_y=smooth_sum[12:1];
    wire signed [14:0] size_delta=$signed({3'b0,op_y})-$signed({3'b0,smooth_y});
    wire signed [14:0] size_target=$signed({8'd0,base_size})+((size_delta+15'sd2)>>>2);
    reg [11:0] nw,nh,ow,oh;
    wire [2:0] current_asset={work[selected][30],work[selected][1:0]};
    reg [2:0] switched_asset;
    reg [11:0] switched_height;
    reg signed [14:0] switched_y;
    reg signed [14:0] nx,ny;
    integer i,k;
    always @* begin
        has_free=0;free_slot=0;
        for(k=3;k>=0;k=k-1) if(!saved[k][31]) begin has_free=1;free_slot=k;end
        next_slot=selected;has_next=0;
        // Search in the requested direction, skipping empty (not hidden) slots.
        for(k=3;k>=1;k=k-1) begin
            if(op_direction==1) begin
                if(work[(selected-k)&3][31]) begin next_slot=(selected-k)&3;has_next=1;end
            end else if(work[(selected+k)&3][31]) begin next_slot=(selected+k)&3;has_next=1;end
        end
        if(size_target<0) resized=0;
        else if(size_target>112) resized=112;
        else resized=size_target[6:0];
        nw=width_for(resized);nh=height_for(nw,current_asset);
        ow=width_for(work[selected][29:23]);oh=height_for(ow,current_asset);
        switched_asset=current_asset;
        if(op_direction==1) switched_asset=switched_asset==0 ? ASSET_COUNT-1:switched_asset-1'b1;
        if(op_direction==2) switched_asset=switched_asset==ASSET_COUNT-1 ? 0:switched_asset+1'b1;
        switched_height=height_for(ow,switched_asset);
        switched_y=$signed({5'b0,work[selected][11:2]})+$signed({3'b0,(oh>>1)})-$signed({3'b0,(switched_height>>1)});
        // Always resize about the ENTRY center, not the previously clamped edge.
        nx=$signed({3'b0,base_x})+$signed({3'b0,(width_for(base_size)>>1)})-$signed({3'b0,(nw>>1)});
        ny=$signed({3'b0,base_y})+$signed({3'b0,(height_for(width_for(base_size),current_asset)>>1)})-$signed({3'b0,(nh>>1)});
        config_bus=0;
        for(k=0;k<4;k=k+1) config_bus[k*32+:32]=work[k];
        config_bus[130:128]=state;config_bus[132:131]=selected;
        // Reuse the displayed-origin fields; the stored menu origin never moves.
        config_bus[133]=selected_valid;
        config_bus[145:134]=(state==SIZE || state==SELECT || state==NEW) ? op_x:menu_x;
        config_bus[157:146]=(state==SIZE || state==SELECT || state==NEW) ? op_y:menu_y;
        config_bus[167:158]=progress;
        config_bus[168]=confirming;config_bus[171:169]=notice;
    end
    assign buzzer_n=(tone_ms==0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ms_count<=0;now_ms<=0;tone_ms<=0;end
        else begin
            if(ms_tick) begin ms_count<=0;now_ms<=now_ms+1'b1;end
            else ms_count<=ms_count+1'b1;
            if(beep) tone_ms<=80;
            else if(ms_tick && tone_ms!=0) tone_ms<=tone_ms-1'b1;
        end
    end
    // Commit once after stable yellow; temporary detections never mutate saved[].
    task commit_edit;
        integer j;
        begin
            for(j=0;j<4;j=j+1) saved[j]<=work[j];
            state<=RETURN;
            progress<=0;dwell<=0;beep<=1;notice<=3;notice_start<=now_ms;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0;i<4;i=i+1) begin saved[i]<=0;work[i]<=0;end
            state<=IDLE;selected<=0;selected_valid<=0;old_selected<=0;old_selected_valid<=0;
            menu_x<=0;menu_y<=0;op_x<=0;op_y<=0;last_x<=0;last_y<=0;dwell_x<=0;dwell_y<=0;
            base_size<=0;size_prev_y<=0;
            base_x<=0;base_y<=0;last_good<=0;entered<=0;dwell_start<=0;
            acquisition_start<=0;acquiring<=0;dwell<=0;armed<=0;rebase<=0;
            dwell_direction<=0;progress<=0;notice<=0;notice_start<=0;
            beep<=0;
        end else begin
            beep<=0;
            if(notice!=0 && elapsed(now_ms,notice_start)>=16'd1500) notice<=0;
            if(ms_tick && state!=IDLE && elapsed(now_ms,last_good)>=LOST_MS) begin
                for(i=0;i<4;i=i+1) work[i]<=saved[i];
                if(state>=SIZE && state<=SELECT) begin selected<=old_selected;selected_valid<=old_selected_valid;end
                state<=IDLE;acquiring<=0;dwell<=0;progress<=0;
                notice<=4;notice_start<=now_ms;
            end else if(confirm_pulse && editing) begin
                commit_edit;
            end else if(frame_valid) begin
                if(blue || (editing && yellow)) last_good<=now_ms;
                if(state==IDLE) begin
                    if(blue && cx>=128 && cx<IMG_WIDTH-128 && cy>=128 && cy<IMG_HEIGHT-128) begin
                        if(!acquiring || odx>18 || ody>18) begin
                            acquiring<=1;acquisition_start<=now_ms;op_x<=cx;op_y<=cy;
                        end else if(elapsed(now_ms,acquisition_start)>=ACQUIRE_MS) begin
                            menu_x<=op_x;menu_y<=op_y;state<=MENU;acquiring<=0;
                            dwell<=0;progress<=0;beep<=1;notice<=0;
                        end
                    end else acquiring<=0;
                end else if(state==MENU || state==RETURN) begin
                    if(!blue) begin dwell<=0;progress<=0;end
                    else if(state==RETURN) begin
                        if(at_menu) begin
                            if(!dwell) begin dwell<=1;dwell_start<=now_ms;end
                            else if(elapsed(now_ms,dwell_start)>=HOLD_MS) begin
                                state<=MENU;dwell<=0;progress<=0;beep<=1;notice<=0;
                            end else progress<=now_ms-dwell_start;
                        end else begin dwell<=0;progress<=0;end
                    end else if(menu_direction!=0) begin
                        if(!dwell || dwell_direction!=menu_direction || hold_dx>18 || hold_dy>18) begin
                            dwell<=1;dwell_direction<=menu_direction;dwell_start<=now_ms;progress<=0;dwell_x<=cx;dwell_y<=cy;
                        end else if(elapsed(now_ms,dwell_start)>=HOLD_MS) begin
                            dwell<=0;progress<=0;
                            if(menu_direction!=3 && !selected_valid) begin notice<=1;notice_start<=now_ms;end
                            else if(menu_direction==3 && !has_free) begin notice<=2;notice_start<=now_ms;end
                            else begin
                                state<=menu_direction==1 ? SIZE:menu_direction==2 ? POSITION:menu_direction==3 ? NEW:SELECT;
                                old_selected<=selected;old_selected_valid<=selected_valid;
                                entered<=now_ms;armed<=0;rebase<=1;
                                op_x<=cx;op_y<=cy;last_x<=cx;last_y<=cy;
                                base_x<=work[selected][22:12];base_y<=work[selected][11:2];
                                beep<=1;notice<=0;
                                if(menu_direction==3) begin
                                    selected<=free_slot;selected_valid<=1;
                                    work[free_slot]<={1'b1,1'b0,7'd16,11'd608,10'd296,2'd0};
                                end
                            end
                        end else progress<=now_ms-dwell_start;
                    end else begin dwell<=0;progress<=0;end
                end else begin
                    // Short RAW misses hold the last coordinate only. Never reset the
                    // position anchor or restart SETTLE_MS after a missing frame.
                    // Yellow holds the last blue position; blue resumes immediately.
                    if(!blue) begin dwell<=0;progress<=0;end
                    if(blue && !confirming) begin
                        last_x<=cx;last_y<=cy;
                        size_prev_y<=cy;
                        if(rebase) begin
                            rebase<=0;op_x<=cx;op_y<=cy;last_x<=cx;last_y<=cy;
                            base_size<=work[selected][29:23];
                            base_x<=work[selected][22:12];base_y<=work[selected][11:2];
                            entered<=now_ms;armed<=0;dwell<=0;
                        end else if(elapsed(now_ms,entered)>=SETTLE_MS) begin
                            if(state==POSITION) begin
                                work[selected][22:12]<=clamp_start($signed({3'b0,base_x})+$signed({3'b0,cx})-$signed({3'b0,op_x}),ow,IMG_WIDTH);
                                work[selected][11:2]<=clamp_start($signed({3'b0,base_y})+$signed({3'b0,cy})-$signed({3'b0,op_y}),oh,IMG_HEIGHT);
                            end else if(state==SIZE) begin
                                // 4 pixels of vertical pen travel = 2 pixels width.
                                // No dwell/re-arm; horizontal travel is ignored.
                                work[selected][29:23]<=resized;
                                work[selected][22:12]<=clamp_start(nx,nw,IMG_WIDTH);
                                work[selected][11:2]<=clamp_start(ny,nh,IMG_HEIGHT);
                            end else if(!armed) begin
                                if(at_op) begin
                                    if(!dwell) begin dwell<=1;dwell_start<=now_ms;end
                                    else if(elapsed(now_ms,dwell_start)>=100) begin armed<=1;dwell<=0;end
                                end else dwell<=0;
                            end else if(op_direction!=0) begin
                                if(!dwell || dwell_direction!=op_direction ||
                                   (state==SELECT && op_direction==4 &&
                                    (hold_dx>18 || hold_dy>18 || elapsed(now_ms,last_good)>100))) begin
                                    dwell<=1;dwell_direction<=op_direction;dwell_start<=now_ms;
                                    dwell_x<=cx;dwell_y<=cy;progress<=0;
                                end else if(elapsed(now_ms,dwell_start)>=
                                            ((state==SELECT && op_direction==4) ? DELETE_HOLD_MS:100)) begin
                                    armed<=0;dwell<=0;progress<=0;
                                    if(state==NEW && ASSET_COUNT>1) begin
                                        if(op_direction==1 || op_direction==2) begin
                                            work[selected][30]<=switched_asset[2];
                                            work[selected][1:0]<=switched_asset[1:0];
                                            work[selected][11:2]<=clamp_start(switched_y,switched_height,IMG_HEIGHT);
                                        end
                                    end else if(state==SELECT) begin
                                        if((op_direction==1 || op_direction==2) && has_next) selected<=next_slot;
                                        if(op_direction==4 && selected_valid && work[selected][31]) begin
                                            // Preview deletion, committed only by yellow confirmation.
                                            work[selected]<=0;
                                            if(has_next) begin selected<=next_slot;selected_valid<=1;end
                                            else selected_valid<=0;
                                            notice<=5;notice_start<=now_ms;beep<=1;
                                        end
                                    end
                                end else if(state==SELECT && op_direction==4) progress<=now_ms-dwell_start;
                            end else begin dwell<=0;progress<=0;end
                        end
                    end
                end
            end
        end
    end
endmodule

// One-shot yellow confirmation. An edit must first see blue, then >=200ms
// of yellow spanning at least three fresh observations. Missing/wrong-colour
// frames or a camera gap >100ms reset the candidate, never extrapolate it.
module yellow_sticker_confirm #(
    parameter HOLD_MS=200, MAX_GAP_MS=100
)(
    input clk,rst_n,enable,input [15:0] now_ms,
    input frame_valid,blue,yellow,
    output reg busy,confirmed
);
    reg armed,done;
    reg [1:0] samples;
    reg [15:0] started,last_sample;
    wire [15:0] duration=now_ms-started;
    wire [15:0] gap=now_ms-last_sample;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            armed<=0;done<=0;busy<=0;confirmed<=0;
            samples<=0;started<=0;last_sample<=0;
        end else begin
            confirmed<=0;
            if(!enable) begin
                armed<=0;done<=0;busy<=0;samples<=0;
            end else if(!done) begin
                if(busy && gap>MAX_GAP_MS) begin busy<=0;samples<=0;end
                if(frame_valid) begin
                    if(blue) armed<=1;
                    if(!yellow || !armed) begin busy<=0;samples<=0;end
                    else begin
                        last_sample<=now_ms;
                        if(!busy || gap>MAX_GAP_MS) begin
                            busy<=1;started<=now_ms;samples<=1;
                        end else begin
                            if(samples<3) samples<=samples+1'b1;
                            if(samples>=2 && duration>=HOLD_MS) begin
                                confirmed<=1;done<=1;busy<=0;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule

// Bundled-data mailbox: source holds payload until destination commits at SOF.
module sticker_config_tx(input clk,rst_n,input [171:0] config_bus,input ack,
                         output reg [171:0] payload,output reg request);
    (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin payload<=0;request<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[1:0],ack};
            if(ack_sync[2]==request && config_bus!=payload) begin payload<=config_bus;request<=~request;end
        end
    end
endmodule

module sticker_config_rx(input clk,rst_n,tick,input [171:0] payload,input request,
                         output reg ack,output reg [171:0] config_bus);
    (* ASYNC_REG="TRUE" *) reg [2:0] req_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin req_sync<=0;ack<=0;config_bus<=0;end
        else begin
            req_sync<={req_sync[1:0],request};
            if(tick && req_sync[2]!=ack) begin config_bus<=payload;ack<=req_sync[2];end
        end
    end
endmodule
