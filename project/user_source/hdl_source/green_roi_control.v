// Camera-frame gestures. All positions use the unfiltered camera raster.
module green_roi_tracker(
 input clk,rst_n,frame_end,candidate_valid,input [2:0] candidate_color,
 input [11:0] left,right,top,bottom,
 output reg sample, present,output reg [11:0] x,y);
 reg pending;reg [11:0] px,py;reg [12:0] best,best_size;
 reg [31:0] frame_pipe;reg [6:0] missed;
 wire [12:0] sx={1'b0,left}+right,sy={1'b0,top}+bottom;
 wire [11:0] cx=sx[12:1],cy=sy[12:1];
 wire [11:0] dx=cx>x?cx-x:x-cx,dy=cy>y?cy-y:y-cy;
 wire [12:0] distance={1'b0,dx}+dy;
 wire [12:0] extent=({1'b0,right}-{1'b0,left})+({1'b0,bottom}-{1'b0,top});
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sample<=0;present<=0;x<=0;y<=0;pending<=0;px<=0;py<=0;best<=8191;best_size<=0;frame_pipe<=0;missed<=127;end
  else begin
   sample<=frame_pipe[31];frame_pipe<={frame_pipe[30:0],frame_end};
   if(candidate_valid && candidate_color==2 && right>=left && bottom>=top && right<1280 && bottom<720 &&
      (missed>=20 || distance<=160) && (!pending || (missed>=20 ? extent>best_size:distance<best)))begin
    pending<=1;px<=cx;py<=cy;best<=distance;best_size<=extent;
   end
   if(frame_pipe[30])begin
    present<=pending;
    if(pending)begin x<=px;y<=py;missed<=0;end
    else if(missed<127)missed<=missed+1'b1;
    pending<=0;best<=8191;best_size<=0;
   end
  end
 end
endmodule

// GREEN1 = long ON, OFF, short ON, OFF, short ON, OFF, final ON.
// Ordinary GREEN (two OFF symbols) and steady light never confirm. A long
// initial ON is accepted so code B can start without first removing the pen.
module green_roi_confirm(input clk,rst_n,enable,sample,present,
 input [11:0] x,y,output wire busy,output reg pulse);
 reg [2:0] state;reg [3:0] run;
 reg [11:0] ax,ay;
 wire [11:0] dx=x>ax?x-ax:ax-x,dy=y>ay?y-ay:ay-y;
 wire on_sample=present && (state==0 || (dx<=32 && dy<=32));
 assign busy=enable && state!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;run<=0;pulse<=0;ax<=0;ay<=0;end
  else begin
   pulse<=0;
   if(!enable)begin state<=0;run<=0;end
   else if(sample)begin
    if(state==0)begin
     if(present)begin if(run<15)run<=run+1'b1;ax<=x;ay<=y;end
     else if(run>=4)begin state<=1;run<=1;end
     else run<=0;
    end else if(state==6)begin
     if(on_sample)begin
      if(run>=2)begin pulse<=1;state<=0;run<=3;end else run<=run+1'b1;
     end else begin state<=0;run<=0;end
    end else if(on_sample==(state==2 || state==4))begin
     if(run>=4)begin state<=0;run<=on_sample?1:0;end else run<=run+1'b1;
    end else if(run>=2 && run<=4 && (!present || dx<=32 && dy<=32))begin state<=state+1'b1;run<=1;end
    else begin state<=0;run<=present?1:0;end
   end
  end
 end
endmodule

module green_roi_control #(
 parameter ACQUIRE_FRAMES=3,HOLD_FRAMES=12,STEP_FRAMES=6,RETURN_FRAMES=12,LOST_FRAMES=90
)(input clk,rst_n,sample,present,acquire_allowed,input [11:0] x,y,
 input confirm,busy_confirm,input switch_update,input [3:0] switch_mode,input store_ready,store_busy,store_done,
 input [2:0] store_error,input used,
 output reg start_draw,add_point,close_draw,create_region,delete_region,cancel_draw,
 output reg edit_id,output reg [8:0] point_x,output reg [7:0] point_y,
 output reg [3:0] state,output reg selected,
 output reg [11:0] menu_x,menu_y,op_x,op_y,
 output wire [6:0] display_progress,output reg [7:0] progress,output reg [3:0] notice,
 output wire [7:0] modes,output reg [3:0] preview_index,
 output reg signed [12:0] exposure_offset,output reg exposure_begin,exposure_toggle,input exposure_ack);
 localparam IDLE=0,MENU=1,LIGHT=2,DRAW=3,CLOSED=4,FILTER=5,SELECT=6,DELETE=7,RETURN=8,BUILD=9;
 reg [3:0] saved_mode[0:1];reg saved_selection;
 reg [7:0] hold_count,missed;reg [2:0] direction;
 reg [11:0] hold_x,hold_y;reg armed,left_origin;reg [7:0] point_count;
 reg [8:0] last_px;reg [7:0] last_py;
 reg [1:0] ack_sync;reg dirty,begin_request;
 reg signed [12:0] wanted_offset;
 wire [11:0] mdx=x>menu_x?x-menu_x:menu_x-x,mdy=y>menu_y?y-menu_y:menu_y-y;
 wire [11:0] odx=x>op_x?x-op_x:op_x-x,ody=y>op_y?y-op_y:op_y-y;
 wire [11:0] hdx=x>hold_x?x-hold_x:hold_x-x,hdy=y>hold_y?y-hold_y:hold_y-y;
 wire at_menu=mdx<=24 && mdy<=24,at_op=odx<=20 && ody<=20;
 wire [2:0] md=mdx>=64 && {1'b0,mdx}>={1'b0,mdy}+16 ? (x<menu_x?1:2):
                   mdy>=64 && {1'b0,mdy}>={1'b0,mdx}+16 ? (y<menu_y?3:4):0;
 wire [2:0] od=odx>=48 && {1'b0,odx}>={1'b0,ody}+12 ? (x<op_x?1:2):
                   ody>=48 && {1'b0,ody}>={1'b0,odx}+12 ? (y<op_y?3:4):0;
 wire [8:0] gx=x[10:2];wire [7:0] gy=y[9:2];
 wire [8:0] pdx=gx>last_px?gx-last_px:last_px-gx;
 wire [7:0] pdy=gy>last_py?gy-last_py:last_py-gy;
 function [3:0] index_mode;input [3:0] i;begin case(i)
  1:index_mode=4;2:index_mode=5;3:index_mode=8;4:index_mode=13;5:index_mode=1;6:index_mode=2;default:index_mode=0;endcase end endfunction
 function [3:0] mode_index;input [3:0] m;begin case(m)
  4,6:mode_index=1;5,7:mode_index=2;8,10:mode_index=3;13,15:mode_index=4;1:mode_index=5;2:mode_index=6;default:mode_index=0;endcase end endfunction
 assign modes={state==FILTER && selected?index_mode(preview_index):saved_mode[1],
               state==FILTER && !selected?index_mode(preview_index):saved_mode[0]};
 assign display_progress=state==IDLE?(hold_count>=3?7'd12:hold_count[6:0]<<2):
 (state==DRAW || state==FILTER || state==SELECT)?(hold_count>=6?7'd12:hold_count[6:0]<<1):
 (hold_count>=12?7'd12:hold_count[6:0]);
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;selected<=0;saved_selection<=0;menu_x<=0;menu_y<=0;op_x<=0;op_y<=0;
   progress<=0;notice<=0;preview_index<=0;hold_count<=0;missed<=0;direction<=0;
   hold_x<=0;hold_y<=0;armed<=0;left_origin<=0;point_count<=0;last_px<=0;last_py<=0;
   start_draw<=0;add_point<=0;close_draw<=0;create_region<=0;delete_region<=0;cancel_draw<=0;
   edit_id<=0;point_x<=0;point_y<=0;ack_sync<=0;dirty<=0;begin_request<=0;wanted_offset<=0;
   exposure_offset<=0;exposure_begin<=0;exposure_toggle<=0;
   for(i=0;i<2;i=i+1)saved_mode[i]<=0;
  end else begin
   ack_sync<={ack_sync[0],exposure_ack};
   start_draw<=0;add_point<=0;close_draw<=0;create_region<=0;delete_region<=0;cancel_draw<=0;
   if(dirty && ack_sync[1]==exposure_toggle)begin
    exposure_offset<=wanted_offset;exposure_begin<=begin_request;exposure_toggle<=~exposure_toggle;dirty<=0;
   end
   if(state==BUILD && store_done)begin
    if(store_error!=0)begin notice<={1'b0,store_error};state<=RETURN;end
    else begin
     if(edit_id!=0 && !used)begin selected<=0;saved_selection<=0;saved_mode[edit_id]<=saved_mode[0];end
     else begin selected<=edit_id;saved_selection<=edit_id;saved_mode[edit_id]<=saved_mode[0];end
     notice<=0;state<=RETURN;
    end
   end
   if(switch_update && !store_busy)begin
    saved_mode[selected]<=switch_mode;state<=IDLE;cancel_draw<=1;hold_count<=0;progress<=0;notice<=0;
   end else if(confirm && !store_busy)begin
    hold_count<=0;progress<=0;
    case(state)
     LIGHT:state<=RETURN;
     FILTER:begin saved_mode[selected]<=index_mode(preview_index);state<=RETURN;end
     SELECT:begin saved_selection<=selected;state<=RETURN;end
     CLOSED:if(store_ready)begin create_region<=1;state<=BUILD;end
     DELETE:if(selected!=0 && store_ready)begin edit_id<=selected;delete_region<=1;state<=BUILD;end
     default:begin end
    endcase
   end else if(sample && state!=BUILD)begin
    if(!present || busy_confirm)begin
     hold_count<=0;progress<=0;direction<=0;
     if(!present && missed<255)missed<=missed+1'b1;
     if(missed>=LOST_FRAMES-1 && !busy_confirm)begin
      state<=IDLE;selected<=saved_selection;cancel_draw<=1;notice<=0;
     end
    end else begin
     missed<=0;
     case(state)
      IDLE:begin
       // A raw steady green candidate must never open the menu.
       if(!acquire_allowed)begin hold_count<=0;progress<=0;end
       else if(hold_count==0 || hdx>20 || hdy>20)begin hold_x<=x;hold_y<=y;hold_count<=1;end
       else if(hold_count>=ACQUIRE_FRAMES-1)begin menu_x<=x;menu_y<=y;state<=MENU;hold_count<=0;armed<=1;notice<=0;end
       else begin hold_count<=hold_count+1'b1;progress<=hold_count+1'b1;end
      end
      MENU:begin
       if(!armed)begin if(at_menu)armed<=1;hold_count<=0;end
       else if(md==0)begin hold_count<=0;direction<=0;progress<=0;end
       else if(direction!=md || hdx>12 || hdy>12)begin direction<=md;hold_x<=x;hold_y<=y;hold_count<=1;progress<=1;end
       else if(hold_count>=HOLD_FRAMES-1)begin
        hold_count<=0;progress<=0;op_x<=x;op_y<=y;armed<=1;notice<=0;
        case(md)
         1:begin state<=LIGHT;wanted_offset<=0;begin_request<=1;dirty<=1;end
         2:begin state<=FILTER;preview_index<=mode_index(saved_mode[selected]);end
         3:if(used)begin notice<=4;armed<=0;end else if(store_ready)begin
            state<=DRAW;edit_id<=1;start_draw<=1;point_x<=gx;point_y<=gy;
            saved_mode[1]<=saved_mode[0];
            last_px<=gx;last_py<=gy;point_count<=1;left_origin<=0;end
         4:begin state<=SELECT;saved_selection<=selected;end
        endcase
       end else begin hold_count<=hold_count+1'b1;progress<=hold_count+1'b1;end
      end
      LIGHT:begin
       wanted_offset<=$signed({1'b0,op_y})-$signed({1'b0,y});begin_request<=0;dirty<=1;
      end
      DRAW:if(store_ready)begin
       if(odx>=40 || ody>=40)left_origin<=1;
       if(left_origin && point_count>=4 && at_op)begin
        if(hold_count>=STEP_FRAMES-1)begin close_draw<=1;state<=CLOSED;hold_count<=0;end
        else begin hold_count<=hold_count+1'b1;progress<=hold_count+1'b1;end
       end else begin
        hold_count<=0;
        if(pdx>=2 || pdy>=2)begin
         if(point_count>=127)begin notice<=3;cancel_draw<=1;state<=RETURN;end
         else if(pdx>40 || pdy>40)begin notice<=5;cancel_draw<=1;state<=RETURN;end
         else begin add_point<=1;point_x<=gx;point_y<=gy;last_px<=gx;last_py<=gy;point_count<=point_count+1'b1;end
        end
       end
      end
      FILTER,SELECT:begin
       if(at_op)begin armed<=1;hold_count<=0;direction<=0;end
       else if(armed && ((state==FILTER && (od==3 || od==4)) || (state==SELECT && od!=0)))begin
        if(direction!=od || hdx>12 || hdy>12)begin direction<=od;hold_x<=x;hold_y<=y;hold_count<=1;end
        else if(hold_count>=STEP_FRAMES-1)begin
         hold_count<=0;armed<=0;
         if(state==FILTER)preview_index<=od==3?(preview_index==6?0:preview_index+1'b1):(preview_index==0?6:preview_index-1'b1);
         else if(od==1 || od==2)selected<=used?!selected:1'b0;
         else if(od==4)begin if(selected!=0)state<=DELETE;else notice<=6;end
        end else begin hold_count<=hold_count+1'b1;progress<=hold_count+1'b1;end
       end else begin hold_count<=0;direction<=0;end
      end
      RETURN:begin
       if(at_menu)begin
        if(hold_count>=RETURN_FRAMES-1)begin state<=MENU;hold_count<=0;notice<=0;armed<=1;end
        else begin hold_count<=hold_count+1'b1;progress<=hold_count+1'b1;end
       end else hold_count<=0;
      end
      default:begin end
     endcase
    end
   end
  end
 end
endmodule
