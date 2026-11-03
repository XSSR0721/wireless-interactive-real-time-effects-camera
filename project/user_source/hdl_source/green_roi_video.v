module green_roi_system #(
 parameter EXTERNAL_SWITCHES=0,IMG_WIDTH=1280,IMG_HEIGHT=720,W=IMG_WIDTH/4,H=IMG_HEIGHT/4,AW=$clog2(W*H)
) (input clk,rst_n,input [3:0] switch_mode,input [95:0] data,input valid,user,last,
 input auth_valid,auth_variant,input [2:0] auth_color,
 input frame_end,candidate_valid,input [2:0] candidate_color,
 input [11:0] candidate_left,candidate_right,candidate_top,candidate_bottom,
 input lamp_valid,input [2:0] lamp_color,input [11:0] lamp_left,lamp_right,lamp_top,lamp_bottom,
 output reg [171:0] ui_payload,output reg ui_request,input ui_ack,
 output [95:0] out_data,output out_valid,out_user,out_last,
 output signed [12:0] exposure_offset,output exposure_begin,exposure_toggle,input exposure_ack);
 wire sample,present;wire [11:0] pen_x,pen_y;
 reg [3:0] sw_meta,sw_sync,sw_candidate,sw_accepted;
 reg [2:0] sw_count;
 wire [3:0] safe_switch=(sw_candidate==9 || sw_candidate==11)?4'd0:sw_candidate;
 wire switch_update=EXTERNAL_SWITCHES && sample && sw_count==3 && sw_candidate!=sw_accepted;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sw_meta<=0;sw_sync<=0;sw_candidate<=0;sw_accepted<=0;sw_count<=0;end
  else begin
   sw_meta<=switch_mode;sw_sync<=sw_meta;
   if(sample)begin
    if(sw_sync!=sw_candidate)begin sw_candidate<=sw_sync;sw_count<=0;end
    else if(sw_count<3)sw_count<=sw_count+1'b1;
    if(switch_update)sw_accepted<=sw_candidate;
   end
  end
 end
 green_roi_tracker tracker(.clk(clk),.rst_n(rst_n),.frame_end(frame_end),.candidate_valid(candidate_valid),
  .candidate_color(candidate_color),.left(candidate_left),.right(candidate_right),.top(candidate_top),.bottom(candidate_bottom),
  .sample(sample),.present(present),.x(pen_x),.y(pen_y));
 wire confirm_busy,confirm_pulse;wire [3:0] state;
 green_roi_confirm confirm_decoder(.clk(clk),.rst_n(rst_n),.enable(state>=2 && state<=7),
  .sample(sample),.present(present),.x(pen_x),.y(pen_y),.busy(confirm_busy),.pulse(confirm_pulse));
 wire start_draw,add_point,close_draw,create_region,delete_region,cancel_draw;
 wire edit_id,selected,used;wire [8:0] point_x;wire [7:0] point_y;
 wire store_ready,store_busy,store_done;wire [2:0] store_error;
 wire [11:0] menu_x,menu_y,op_x,op_y;wire [7:0] modes;wire [7:0] progress;
 wire [3:0] notice,preview;wire [6:0] display_progress;
 wire acquire_allowed=auth_valid && auth_color==3'd2 && !auth_variant;
 // Raw observations still feed the GREEN1 decoder, but only authenticated
 // normal GREEN may drive gestures after opening the menu as well as before.
 wire gesture_present=present && acquire_allowed;
 green_roi_control control(.clk(clk),.rst_n(rst_n),.sample(sample),.present(gesture_present),.x(pen_x),.y(pen_y),
  .acquire_allowed(acquire_allowed),
  .switch_update(switch_update),.switch_mode(safe_switch),.confirm(confirm_pulse),.busy_confirm(confirm_busy),.store_ready(store_ready),.store_busy(store_busy),.store_done(store_done),
  .store_error(store_error),.used(used),.start_draw(start_draw),.add_point(add_point),.close_draw(close_draw),
  .create_region(create_region),.delete_region(delete_region),.cancel_draw(cancel_draw),.edit_id(edit_id),.point_x(point_x),.point_y(point_y),
  .state(state),.selected(selected),.menu_x(menu_x),.menu_y(menu_y),.op_x(op_x),.op_y(op_y),.display_progress(display_progress),.progress(progress),.notice(notice),
  .modes(modes),.preview_index(preview),.exposure_offset(exposure_offset),.exposure_begin(exposure_begin),
  .exposure_toggle(exposure_toggle),.exposure_ack(exposure_ack));
 reg [11:0] x,y;
 wire [11:0] px=user?12'd0:x,py=user?12'd0:y;
 wire [AW-1:0] query_addr=(px<IMG_WIDTH && py<IMG_HEIGHT)?(py>>2)*W+(px>>2):0;
 wire label;wire trail;
 roi_region_store #(.W(W),.H(H)) regions(.clk(clk),.rst_n(rst_n),.frame_start(user),.query_addr(query_addr),
  .query_label(label),.query_trail(trail),.start_draw(start_draw),.add_point(add_point),.close_draw(close_draw),
  .create_region(create_region),.delete_region(delete_region),.cancel_draw(cancel_draw),.edit_id(edit_id),.point_x(point_x),.point_y(point_y),
  .ready(store_ready),.busy(store_busy),.done(store_done),.error(store_error),.used(used));
 reg [95:0] data_q;reg valid_q,user_q,last_q;
 reg [7:0] modes_frame,modes_q;reg [11:0] x_q,y_q;
 wire [3:0] region_mode=label?modes_q[7:4]:modes_q[3:0];
 reg [11:0] x_d0,y_d0,x_d1,y_d1;
 reg trail_d0,trail_d1;reg label_d0,label_d1;
 reg [3:0] ui_state;reg ui_selected;
 reg [1:0] ack_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ack_sync<=0;ui_payload<=0;ui_request<=0;end
  else begin
   ack_sync<={ack_sync[0],ui_ack};
   if(user && ack_sync[1]==ui_request)begin
    ui_payload<={99'd0,selected?modes[7:4]:modes[3:0],display_progress,state,notice,preview,selected,used,menu_x,menu_y,op_x,op_y};
    ui_request<=~ui_request;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;data_q<=0;valid_q<=0;user_q<=0;last_q<=0;modes_frame<=0;modes_q<=0;x_q<=0;y_q<=0;
   x_d0<=0;y_d0<=0;x_d1<=0;y_d1<=0;trail_d0<=0;trail_d1<=0;label_d0<=0;label_d1<=0;
   ui_state<=0;ui_selected<=0;
  end else begin
   if(user)begin x<=0;y<=0;end
   if(valid)begin
    if(last || px==IMG_WIDTH-4)begin x<=0;y<=py+1'b1;end
    else begin x<=px+4;y<=py;end
   end
   data_q<=data;valid_q<=valid;user_q<=user;last_q<=last;x_q<=px;y_q<=py;
   modes_q<=user?modes:modes_frame;
   x_d0<=x_q;y_d0<=y_q;x_d1<=x_d0;y_d1<=y_d0;
   trail_d0<=trail;trail_d1<=trail_d0;label_d0<=label;label_d1<=label_d0;
   if(user)begin
    modes_frame<=modes;ui_state<=state;ui_selected<=selected;
   end
  end
 end
 wire [95:0] filtered;
 edge_detect_4pixel #(.IMG_WIDTH(IMG_WIDTH)) filter(.I_clk(clk),.I_rst_n(rst_n),.I_mode(region_mode),
  .I_tdata(data_q),.I_tvalid(valid_q),.I_tuser(user_q),.I_tlast(last_q),
  .O_tdata(filtered),.O_tvalid(out_valid),.O_tuser(out_user),.O_tlast(out_last),
  .O_detect_valid(),.O_detect_left(),.O_detect_right(),.O_detect_top(),.O_detect_bottom());
 genvar i;
 generate for(i=0;i<4;i=i+1)begin:overlay_lane
  wire [23:0] p=filtered[i*24+:24];
  assign out_data[i*24+:24]=!out_valid?24'd0:
   ((ui_state==3 || ui_state==4) && trail_d1)?24'hffffff:
   (ui_state==6 && label_d1==ui_selected)?{1'b0,p[23:17],1'b1,p[15:9],1'b0,p[7:1]}:p;
 end endgenerate
endmodule


// Pixel-resolution OSD. Panel geometry, glyphs and colors match the main project.
module green_roi_osd #(parameter PHOTO_ENABLE=0,IMG_WIDTH=1280,PIPELINED=0)(input clk,rst_n,input [11:0] x,y,
 input [2:0] photo_state,input [6:0] photo_progress,input [1:0] photo_seconds,input snapshot_view,input [1:0] auth_status,
 input [3:0] state,notice,preview,mode,input selected,used,input [6:0] progress,gain,
 input speed_valid,input [15:0] speed_bcd,
 input [29:0] history,input [11:0] latency_bcd,input latency_valid,input [11:0] menu_x,menu_y,op_x,op_y,
 input lamp_valid,lamp_variant,input [2:0] lamp_color,input [11:0] left,right,top,bottom,
 output reg overlay,output reg [23:0] pixel);
 function [34:0] glyph;
 input [7:0] c;
 begin case(c)
 8'd65:glyph=35'b01110100011000111111100011000110001;
 8'd66:glyph=35'b11110100011000111110100011000111110;
 8'd67:glyph=35'b01111100001000010000100001000001111;
 8'd68:glyph=35'b11110100011000110001100011000111110;
 8'd69:glyph=35'b11111100001000011110100001000011111;
 8'd70:glyph=35'b11111100001000011110100001000010000;
 8'd71:glyph=35'b01110100011000010111100011000101110;
 8'd72:glyph=35'b10001100011000111111100011000110001;
 8'd73:glyph=35'b11111001000010000100001000010011111;
 8'd74:glyph=35'b00111000100001000010100101001001100;
 8'd75:glyph=35'b10001100101010011000101001001010001;
 8'd76:glyph=35'b10000100001000010000100001000011111;
 8'd77:glyph=35'b10001110111010110101100011000110001;
 8'd78:glyph=35'b10001110011100110101100111001110001;
 8'd79:glyph=35'b01110100011000110001100011000101110;
 8'd80:glyph=35'b11110100011000111110100001000010000;
 8'd81:glyph=35'b01110100011000110001101011001001101;
 8'd82:glyph=35'b11110100011000111110101001001010001;
 8'd83:glyph=35'b01111100001000001110000010000111110;
 8'd84:glyph=35'b11111001000010000100001000010000100;
 8'd85:glyph=35'b10001100011000110001100011000101110;
 8'd86:glyph=35'b10001100011000110001100010101000100;
 8'd87:glyph=35'b10001100011000110101101011010101010;
 8'd88:glyph=35'b10001100010101000100010101000110001;
 8'd89:glyph=35'b10001100010101000100001000010000100;
 8'd90:glyph=35'b11111000010001000100010001000011111;
 8'd49:glyph=35'b00100011000010000100001000010001110;
  8'd48:glyph=35'b01110100011001110101110011000101110;
 8'd50:glyph=35'b01110100010000100010001000100011111;
 8'd51:glyph=35'b11110000010000101110000010000111110;
 8'd52:glyph=35'b00010001100101010010111110001000010;
 8'd53:glyph=35'b11111100001000011110000010000111110;
 8'd54:glyph=35'b01110100001000011110100011000101110;
 8'd55:glyph=35'b11111000010001000100010000100001000;
 8'd56:glyph=35'b01110100011000101110100011000101110;
 8'd57:glyph=35'b01110100011000101111000010000101110;
 8'd45:glyph=35'b00000_00000_00000_11111_00000_00000_00000;
 8'd46:glyph=35'b00000_00000_00000_00000_00000_00110_00110;
 8'd47:glyph=35'b00001000100001000100010000100010000;
 8'd43:glyph=35'b00000001000010011111001000010000000;
 default:glyph=0;
 endcase end endfunction function [127:0] filter_name;
 input [3:0] m;
 begin case(m)
 4'd0:filter_name="1/7 NORMAL      ";
 4'd4:filter_name="2/7 COOL        ";
 4'd5:filter_name="3/7 WARM        ";
 4'd8:filter_name="4/7 VINTAGE     ";
 4'd13:filter_name="5/7 ENHANCE     ";
 4'd1:filter_name="6/7 BW EDGE     ";
 4'd2:filter_name="7/7 CARTOON     ";
 4'd3:filter_name="NORMAL          ";
 4'd6:filter_name="COOL            ";
 4'd7:filter_name="WARM            ";
 4'd10:filter_name="VINTAGE         ";
 4'd12,4'd14:filter_name="NORMAL          ";
 4'd15:filter_name="ENHANCE         ";
 default:filter_name="NORMAL          ";
 endcase end endfunction function ring;input [11:0] px,py,cx,cy;reg [11:0] dx,dy;begin
  dx=px>cx?px-cx:cx-px;dy=py>cy?py-cy:cy-py;
  ring=dx<=16 && dy<=16 && {1'b0,dx}+dy<=24 && !(dx<=11 && dy<=11 && {1'b0,dx}+dy<=16);
 end endfunction

 wire [11:0] hx=x-(IMG_WIDTH-272),hy=y-18;
 wire [11:0] htx=hx-8,hty=hy-8;
 wire history_panel=hx<264 && hy<80;
 wire [11:0] dx=x-(IMG_WIDTH-272),dy=y-110,tx=dx-8,ty=dy-8;
 wire photo_active=PHOTO_ENABLE && (photo_state!=0 || snapshot_view);
 wire expanded=photo_active || state!=0 || progress!=0 || notice!=0;
 wire [8:0] panel_height=expanded?160:64;
 wire panel=dx<264 && dy<panel_height;
 wire [3:0] line_index=ty[6:5];
 wire [3:0] hindex=htx[7:4];
 // Three 24-pixel rows fit the existing 80-pixel panel; menus stay in place.
 wire [1:0] hline=hty<24?0:hty<48?1:2;
 wire [11:0] hrow_y=hline==0?hty:hline==1?hty-24:hty-48;
 wire [6:0] reduced=gain>=100?gain-100:gain;
 reg [3:0] tens;
 always @*begin
  if(reduced>=90)tens=9;else if(reduced>=80)tens=8;else if(reduced>=70)tens=7;
  else if(reduced>=60)tens=6;else if(reduced>=50)tens=5;else if(reduced>=40)tens=4;
  else if(reduced>=30)tens=3;else if(reduced>=20)tens=2;else if(reduced>=10)tens=1;else tens=0;
 end
 wire [6:0] tens10=({3'd0,tens}<<3)+({3'd0,tens}<<1);
 wire [3:0] ones=reduced-tens10;
 reg [127:0] text_line;reg [7:0] hc;
 always @*begin
  text_line="                ";
  case(line_index)
   0:case(state)
    0:text_line="FILTER          ";1:text_line="GREEN PEN MENU  ";2:text_line="GLOBAL LIGHT    ";
    3:text_line="DRAW REGION A   ";4:text_line="REGION CLOSED   ";5:text_line=selected?"REGION A FILTER ":"BG FILTER       ";
    6:text_line=selected?"SELECT REGION A ":"SELECT BG       ";7:text_line="DELETE REGION A ";8:text_line="APPLIED         ";9:text_line="BUILD REGION A  ";
   endcase
   1:text_line=filter_name(mode);
   2:case(state)
    0:text_line="HOLD TO OPEN    ";1:text_line="L LIGHT U NEW   ";2:text_line="UP DOWN BRIGHT  ";
    3:text_line="DRAW BACK ORIGIN";4,5,6,7:text_line="GREEN1 CONFIRM  ";
    8:text_line="BACK MENU ORIGIN";9:text_line="PLEASE WAIT     ";
   endcase
   3:case(state)
    1:text_line="R FILTER D PICK ";
    2:text_line="GREEN1 CONFIRM  ";
    3:text_line="WHITE LINE PATH ";
    5:text_line="UP DOWN FILTER  ";
    6:text_line="LR PICK DN DEL  ";
    default:text_line=selected?"SELECT REGION A ":"SELECT BG       ";
   endcase
  endcase
  if(notice!=0 && line_index==0)case(notice)
   1:text_line="REGION TOO SMALL";3:text_line="TOO MANY POINTS ";4:text_line="REGION A FULL   ";
   5:text_line="PEN GAP TOO FAR ";6:text_line="BACKGROUND ONLY ";default:text_line="REGION ERROR    ";endcase
 if(photo_active) begin
 case(line_index)
 0:text_line=(photo_state==6 || photo_state==7 || snapshot_view) ? "YELLOW1 ALBUM   ":"YELLOW PHOTO    ";
 1:case(photo_state)
    2:case(photo_seconds)
      3:text_line="CAPTURE IN 3    ";
      2:text_line="CAPTURE IN 2    ";
      1:text_line="CAPTURE IN 1    ";
      default:text_line="CAPTURING       ";
      endcase
    3:text_line="CAPTURED        ";
    6:text_line=snapshot_view ? "PHOTO DISPLAY   ":"OPENING PHOTO   ";
    7:text_line="NO PHOTO        ";
    4:text_line="CANCELLED       ";
    default:text_line=snapshot_view ? "PHOTO DISPLAY   ":"LIVE VIDEO      ";
   endcase
 2:text_line=photo_state==2 ? "REMOVE PEN NOW  ":
             photo_state==6 ? "PEN OFF TO LIVE ":
             photo_state==7 ? "USE YELLOW FIRST":
             snapshot_view ? "KEY4 FOR LIVE   ":"YELLOW CAPTURE  ";
 3:text_line=photo_state==2 ? "AUTO CAPTURE    ":"YEL1 SHOW PHOTO ";
 endcase
 end
  hc=" ";
  if(hline==0)case(hindex)
   0:hc="L";1:hc="A";2:hc="T";3:hc="E";4:hc="N";5:hc="C";6:hc="Y";
   8:hc=latency_valid ? "0"+latency_bcd[11:8]:"-";
   9:hc=latency_valid ? "0"+latency_bcd[7:4]:"-";
   10:hc=latency_valid ? "0"+latency_bcd[3:0]:"-";
   12:hc="M";13:hc="S";endcase
  else if(hline==1)case(hindex)
   0:hc="B";1:hc="R";2:hc="I";3:hc="G";4:hc="H";5:hc="T";6:hc="N";7:hc="E";8:hc="S";9:hc="S";
   11:hc=gain>=100?"1":"0";12:hc="0"+tens;13:hc="0"+ones;endcase
  else if(hline==2)case(hindex)
   0:hc="S";1:hc="P";2:hc="E";3:hc="E";4:hc="D";
   6:hc=speed_valid ? "0"+speed_bcd[15:12]:"-";
   7:hc=speed_valid ? "0"+speed_bcd[11:8]:"-";
   8:hc=speed_valid ? "0"+speed_bcd[7:4]:"-";
   9:hc=".";10:hc=speed_valid ? "0"+speed_bcd[3:0]:"-";
   12:hc="C";13:hc="M";14:hc="/";15:hc="S";endcase
 end
 wire [7:0] character=text_line[127-tx[7:4]*8-:8];
 // The two disjoint panels share one glyph decoder and bit selector.
 wire [34:0] text_bits=glyph(history_panel?hc:character);
 wire [11:0] text_x=history_panel?htx:tx,text_y=history_panel?hrow_y:ty;
 wire text_ink=text_x[3:1]<5 && text_y[4:1]<7 && text_bits[34-text_y[4:1]*5-text_x[3:1]];
 wire ink=tx<256 && ty<128 && text_ink;
 wire hink=htx<256 && hty<72 && hindex<16 && hrow_y<14 && text_ink;
 wire border=dx==0 || dx==263 || dy==0 || dy==panel_height-1;
 wire hborder=hx==0 || hx==263 || hy==0 || hy==79;
 wire bar=expanded && (!photo_active || photo_state==1 || photo_state==5 || (photo_state==0 && auth_status==2)) && dx>=8 && dx<128 && dy>=144 && dy<150;
 wire [8:0] bar_width=photo_active ? (photo_state==0 ? 9'd0:photo_state==5 ? (({2'd0,photo_progress}<<1)+({2'd0,photo_progress}>>1)):({2'd0,photo_progress}<<1)) : progress>=12?120:({2'd0,progress}<<3)+({2'd0,progress}<<1);
    function lamp_label_pixel;
        input [2:0] lamp_color;
        input lamp_variant;
        input [6:0] dx;
        input [3:0] dy;
        reg [55:0] letters;
        reg [7:0] ch;
        reg [34:0] bits;
        integer index;
        integer column;
        integer row;
        begin
            case(lamp_color)
                2: letters=lamp_variant ? "GREEN1 ":"GREEN  ";
                3: letters=lamp_variant ? "BLUE1  ":"BLUE   ";
                4: letters=lamp_variant ? "YELLOW1":"YELLOW ";
                5: letters=lamp_variant ? "PURPLE1":"PURPLE ";
                default: letters="UNKNOWN";
            endcase
            index=dx/12; column=(dx%12)/2; row=dy/2;
            ch=8'd32; bits=0;
            if(index<7) ch=letters >> ((6-index)*8);
            case(ch)
                8'd82: bits=35'b11110_10001_10001_11110_10100_10010_10001;
                8'd69: bits=35'b11111_10000_10000_11110_10000_10000_11111;
                8'd68: bits=35'b11110_10001_10001_10001_10001_10001_11110;
                8'd71: bits=35'b01110_10001_10000_10111_10001_10001_01110;
                8'd78: bits=35'b10001_11001_11001_10101_10011_10011_10001;
                8'd66: bits=35'b11110_10001_10001_11110_10001_10001_11110;
                8'd76: bits=35'b10000_10000_10000_10000_10000_10000_11111;
                8'd85: bits=35'b10001_10001_10001_10001_10001_10001_01110;
                8'd75: bits=35'b10001_10010_10100_11000_10100_10010_10001;
                8'd79: bits=35'b01110_10001_10001_10001_10001_10001_01110;
                8'd87: bits=35'b10001_10001_10001_10101_10101_10101_01010;
                8'd89: bits=35'b10001_10001_01010_00100_00100_00100_00100;
                8'd80: bits=35'b11110_10001_10001_11110_10000_10000_10000;
                8'd49: bits=35'b00100_01100_00100_00100_00100_00100_01110;
                default: bits=0;
            endcase
            lamp_label_pixel=0;
            if(column<5 && row<7 && index<7)
                lamp_label_pixel=bits[34-row*5-column];
        end
    endfunction
 wire [11:0] lx=x-left,ly=y-(bottom<698?bottom+4:top-18);
 wire lamp_ink=lamp_valid && lamp_color==2 && lx<84 && ly<14 && lamp_label_pixel(lamp_color,lamp_variant,lx[6:0],ly[3:0]);
 wire box=lamp_valid && x>=left && x<=right && y>=top && y<=bottom &&
           (x<left+2 || x+2>right || y<top+2 || y+2>bottom);
 generate if(PIPELINED)begin:pipelined_text
    reg pre_overlay;reg[23:0]pre_pixel;
 always @*begin
  pre_overlay=0;pre_pixel=24'hffffff;
  if(state!=0 && !photo_active && ((x+12>=menu_x && x<=menu_x+12 && y+2>=menu_y && y<=menu_y+2) ||
     (y+12>=menu_y && y<=menu_y+12 && x+2>=menu_x && x<=menu_x+2)))begin pre_overlay=1;pre_pixel=24'h00ffff;end
  if(!photo_active && state!=0 && state!=1 && state!=8 && ring(x,y,op_x,op_y))pre_overlay=1;
  if(box || lamp_ink)begin pre_overlay=1;pre_pixel=lamp_color==2?24'h00ff40:24'h909090;end
  if(history_panel)begin pre_overlay=1;pre_pixel=hborder?24'h607080:24'h101820;end
  if(panel)begin pre_overlay=1;pre_pixel=border?(lamp_valid && lamp_color==2?24'h40ff80:24'h607080):bar?(dx-8<bar_width?24'h40ff80:24'h405060):24'h101820;end
 end
    // Register the character address and all non-text geometry together.
    (* ram_style="block" *) reg font[0:4095];
    integer fi;
    initial begin
      for(fi=0;fi<4096;fi=fi+1)font[fi]=0;
      font[2986]=1'b1;
      font[2987]=1'b1;
      font[2994]=1'b1;
      font[2995]=1'b1;
      font[2904]=1'b1;
      font[2905]=1'b1;
      font[2906]=1'b1;
      font[2907]=1'b1;
      font[2908]=1'b1;
      font[65]=1'b1;
      font[66]=1'b1;
      font[67]=1'b1;
      font[72]=1'b1;
      font[76]=1'b1;
      font[80]=1'b1;
      font[84]=1'b1;
      font[88]=1'b1;
      font[89]=1'b1;
      font[90]=1'b1;
      font[91]=1'b1;
      font[92]=1'b1;
      font[96]=1'b1;
      font[100]=1'b1;
      font[104]=1'b1;
      font[108]=1'b1;
      font[112]=1'b1;
      font[116]=1'b1;
      font[128]=1'b1;
      font[129]=1'b1;
      font[130]=1'b1;
      font[131]=1'b1;
      font[136]=1'b1;
      font[140]=1'b1;
      font[144]=1'b1;
      font[148]=1'b1;
      font[152]=1'b1;
      font[153]=1'b1;
      font[154]=1'b1;
      font[155]=1'b1;
      font[160]=1'b1;
      font[164]=1'b1;
      font[168]=1'b1;
      font[172]=1'b1;
      font[176]=1'b1;
      font[177]=1'b1;
      font[178]=1'b1;
      font[179]=1'b1;
      font[193]=1'b1;
      font[194]=1'b1;
      font[195]=1'b1;
      font[196]=1'b1;
      font[200]=1'b1;
      font[208]=1'b1;
      font[216]=1'b1;
      font[224]=1'b1;
      font[232]=1'b1;
      font[241]=1'b1;
      font[242]=1'b1;
      font[243]=1'b1;
      font[244]=1'b1;
      font[256]=1'b1;
      font[257]=1'b1;
      font[258]=1'b1;
      font[259]=1'b1;
      font[264]=1'b1;
      font[268]=1'b1;
      font[272]=1'b1;
      font[276]=1'b1;
      font[280]=1'b1;
      font[284]=1'b1;
      font[288]=1'b1;
      font[292]=1'b1;
      font[296]=1'b1;
      font[300]=1'b1;
      font[304]=1'b1;
      font[305]=1'b1;
      font[306]=1'b1;
      font[307]=1'b1;
      font[320]=1'b1;
      font[321]=1'b1;
      font[322]=1'b1;
      font[323]=1'b1;
      font[324]=1'b1;
      font[328]=1'b1;
      font[336]=1'b1;
      font[344]=1'b1;
      font[345]=1'b1;
      font[346]=1'b1;
      font[347]=1'b1;
      font[352]=1'b1;
      font[360]=1'b1;
      font[368]=1'b1;
      font[369]=1'b1;
      font[370]=1'b1;
      font[371]=1'b1;
      font[372]=1'b1;
      font[384]=1'b1;
      font[385]=1'b1;
      font[386]=1'b1;
      font[387]=1'b1;
      font[388]=1'b1;
      font[392]=1'b1;
      font[400]=1'b1;
      font[408]=1'b1;
      font[409]=1'b1;
      font[410]=1'b1;
      font[411]=1'b1;
      font[416]=1'b1;
      font[424]=1'b1;
      font[432]=1'b1;
      font[449]=1'b1;
      font[450]=1'b1;
      font[451]=1'b1;
      font[456]=1'b1;
      font[460]=1'b1;
      font[464]=1'b1;
      font[472]=1'b1;
      font[474]=1'b1;
      font[475]=1'b1;
      font[476]=1'b1;
      font[480]=1'b1;
      font[484]=1'b1;
      font[488]=1'b1;
      font[492]=1'b1;
      font[497]=1'b1;
      font[498]=1'b1;
      font[499]=1'b1;
      font[512]=1'b1;
      font[516]=1'b1;
      font[520]=1'b1;
      font[524]=1'b1;
      font[528]=1'b1;
      font[532]=1'b1;
      font[536]=1'b1;
      font[537]=1'b1;
      font[538]=1'b1;
      font[539]=1'b1;
      font[540]=1'b1;
      font[544]=1'b1;
      font[548]=1'b1;
      font[552]=1'b1;
      font[556]=1'b1;
      font[560]=1'b1;
      font[564]=1'b1;
      font[576]=1'b1;
      font[577]=1'b1;
      font[578]=1'b1;
      font[579]=1'b1;
      font[580]=1'b1;
      font[586]=1'b1;
      font[594]=1'b1;
      font[602]=1'b1;
      font[610]=1'b1;
      font[618]=1'b1;
      font[624]=1'b1;
      font[625]=1'b1;
      font[626]=1'b1;
      font[627]=1'b1;
      font[628]=1'b1;
      font[642]=1'b1;
      font[643]=1'b1;
      font[644]=1'b1;
      font[651]=1'b1;
      font[659]=1'b1;
      font[667]=1'b1;
      font[672]=1'b1;
      font[675]=1'b1;
      font[680]=1'b1;
      font[683]=1'b1;
      font[689]=1'b1;
      font[690]=1'b1;
      font[704]=1'b1;
      font[708]=1'b1;
      font[712]=1'b1;
      font[715]=1'b1;
      font[720]=1'b1;
      font[722]=1'b1;
      font[728]=1'b1;
      font[729]=1'b1;
      font[736]=1'b1;
      font[738]=1'b1;
      font[744]=1'b1;
      font[747]=1'b1;
      font[752]=1'b1;
      font[756]=1'b1;
      font[768]=1'b1;
      font[776]=1'b1;
      font[784]=1'b1;
      font[792]=1'b1;
      font[800]=1'b1;
      font[808]=1'b1;
      font[816]=1'b1;
      font[817]=1'b1;
      font[818]=1'b1;
      font[819]=1'b1;
      font[820]=1'b1;
      font[832]=1'b1;
      font[836]=1'b1;
      font[840]=1'b1;
      font[841]=1'b1;
      font[843]=1'b1;
      font[844]=1'b1;
      font[848]=1'b1;
      font[850]=1'b1;
      font[852]=1'b1;
      font[856]=1'b1;
      font[858]=1'b1;
      font[860]=1'b1;
      font[864]=1'b1;
      font[868]=1'b1;
      font[872]=1'b1;
      font[876]=1'b1;
      font[880]=1'b1;
      font[884]=1'b1;
      font[896]=1'b1;
      font[900]=1'b1;
      font[904]=1'b1;
      font[905]=1'b1;
      font[908]=1'b1;
      font[912]=1'b1;
      font[913]=1'b1;
      font[916]=1'b1;
      font[920]=1'b1;
      font[922]=1'b1;
      font[924]=1'b1;
      font[928]=1'b1;
      font[931]=1'b1;
      font[932]=1'b1;
      font[936]=1'b1;
      font[939]=1'b1;
      font[940]=1'b1;
      font[944]=1'b1;
      font[948]=1'b1;
      font[961]=1'b1;
      font[962]=1'b1;
      font[963]=1'b1;
      font[968]=1'b1;
      font[972]=1'b1;
      font[976]=1'b1;
      font[980]=1'b1;
      font[984]=1'b1;
      font[988]=1'b1;
      font[992]=1'b1;
      font[996]=1'b1;
      font[1000]=1'b1;
      font[1004]=1'b1;
      font[1009]=1'b1;
      font[1010]=1'b1;
      font[1011]=1'b1;
      font[1024]=1'b1;
      font[1025]=1'b1;
      font[1026]=1'b1;
      font[1027]=1'b1;
      font[1032]=1'b1;
      font[1036]=1'b1;
      font[1040]=1'b1;
      font[1044]=1'b1;
      font[1048]=1'b1;
      font[1049]=1'b1;
      font[1050]=1'b1;
      font[1051]=1'b1;
      font[1056]=1'b1;
      font[1064]=1'b1;
      font[1072]=1'b1;
      font[1089]=1'b1;
      font[1090]=1'b1;
      font[1091]=1'b1;
      font[1096]=1'b1;
      font[1100]=1'b1;
      font[1104]=1'b1;
      font[1108]=1'b1;
      font[1112]=1'b1;
      font[1116]=1'b1;
      font[1120]=1'b1;
      font[1122]=1'b1;
      font[1124]=1'b1;
      font[1128]=1'b1;
      font[1131]=1'b1;
      font[1137]=1'b1;
      font[1138]=1'b1;
      font[1140]=1'b1;
      font[1152]=1'b1;
      font[1153]=1'b1;
      font[1154]=1'b1;
      font[1155]=1'b1;
      font[1160]=1'b1;
      font[1164]=1'b1;
      font[1168]=1'b1;
      font[1172]=1'b1;
      font[1176]=1'b1;
      font[1177]=1'b1;
      font[1178]=1'b1;
      font[1179]=1'b1;
      font[1184]=1'b1;
      font[1186]=1'b1;
      font[1192]=1'b1;
      font[1195]=1'b1;
      font[1200]=1'b1;
      font[1204]=1'b1;
      font[1217]=1'b1;
      font[1218]=1'b1;
      font[1219]=1'b1;
      font[1220]=1'b1;
      font[1224]=1'b1;
      font[1232]=1'b1;
      font[1241]=1'b1;
      font[1242]=1'b1;
      font[1243]=1'b1;
      font[1252]=1'b1;
      font[1260]=1'b1;
      font[1264]=1'b1;
      font[1265]=1'b1;
      font[1266]=1'b1;
      font[1267]=1'b1;
      font[1280]=1'b1;
      font[1281]=1'b1;
      font[1282]=1'b1;
      font[1283]=1'b1;
      font[1284]=1'b1;
      font[1290]=1'b1;
      font[1298]=1'b1;
      font[1306]=1'b1;
      font[1314]=1'b1;
      font[1322]=1'b1;
      font[1330]=1'b1;
      font[1344]=1'b1;
      font[1348]=1'b1;
      font[1352]=1'b1;
      font[1356]=1'b1;
      font[1360]=1'b1;
      font[1364]=1'b1;
      font[1368]=1'b1;
      font[1372]=1'b1;
      font[1376]=1'b1;
      font[1380]=1'b1;
      font[1384]=1'b1;
      font[1388]=1'b1;
      font[1393]=1'b1;
      font[1394]=1'b1;
      font[1395]=1'b1;
      font[1408]=1'b1;
      font[1412]=1'b1;
      font[1416]=1'b1;
      font[1420]=1'b1;
      font[1424]=1'b1;
      font[1428]=1'b1;
      font[1432]=1'b1;
      font[1436]=1'b1;
      font[1440]=1'b1;
      font[1444]=1'b1;
      font[1449]=1'b1;
      font[1451]=1'b1;
      font[1458]=1'b1;
      font[1472]=1'b1;
      font[1476]=1'b1;
      font[1480]=1'b1;
      font[1484]=1'b1;
      font[1488]=1'b1;
      font[1492]=1'b1;
      font[1496]=1'b1;
      font[1498]=1'b1;
      font[1500]=1'b1;
      font[1504]=1'b1;
      font[1506]=1'b1;
      font[1508]=1'b1;
      font[1512]=1'b1;
      font[1514]=1'b1;
      font[1516]=1'b1;
      font[1521]=1'b1;
      font[1523]=1'b1;
      font[1536]=1'b1;
      font[1540]=1'b1;
      font[1544]=1'b1;
      font[1548]=1'b1;
      font[1553]=1'b1;
      font[1555]=1'b1;
      font[1562]=1'b1;
      font[1569]=1'b1;
      font[1571]=1'b1;
      font[1576]=1'b1;
      font[1580]=1'b1;
      font[1584]=1'b1;
      font[1588]=1'b1;
      font[1600]=1'b1;
      font[1604]=1'b1;
      font[1608]=1'b1;
      font[1612]=1'b1;
      font[1617]=1'b1;
      font[1619]=1'b1;
      font[1626]=1'b1;
      font[1634]=1'b1;
      font[1642]=1'b1;
      font[1650]=1'b1;
      font[1664]=1'b1;
      font[1665]=1'b1;
      font[1666]=1'b1;
      font[1667]=1'b1;
      font[1668]=1'b1;
      font[1676]=1'b1;
      font[1683]=1'b1;
      font[1690]=1'b1;
      font[1697]=1'b1;
      font[1704]=1'b1;
      font[1712]=1'b1;
      font[1713]=1'b1;
      font[1714]=1'b1;
      font[1715]=1'b1;
      font[1716]=1'b1;
      font[2762]=1'b1;
      font[2770]=1'b1;
      font[2776]=1'b1;
      font[2777]=1'b1;
      font[2778]=1'b1;
      font[2779]=1'b1;
      font[2780]=1'b1;
      font[2786]=1'b1;
      font[2794]=1'b1;
      font[3012]=1'b1;
      font[3019]=1'b1;
      font[3027]=1'b1;
      font[3034]=1'b1;
      font[3041]=1'b1;
      font[3049]=1'b1;
      font[3056]=1'b1;
      font[3073]=1'b1;
      font[3074]=1'b1;
      font[3075]=1'b1;
      font[3080]=1'b1;
      font[3084]=1'b1;
      font[3088]=1'b1;
      font[3091]=1'b1;
      font[3092]=1'b1;
      font[3096]=1'b1;
      font[3098]=1'b1;
      font[3100]=1'b1;
      font[3104]=1'b1;
      font[3105]=1'b1;
      font[3108]=1'b1;
      font[3112]=1'b1;
      font[3116]=1'b1;
      font[3121]=1'b1;
      font[3122]=1'b1;
      font[3123]=1'b1;
      font[3138]=1'b1;
      font[3145]=1'b1;
      font[3146]=1'b1;
      font[3154]=1'b1;
      font[3162]=1'b1;
      font[3170]=1'b1;
      font[3178]=1'b1;
      font[3185]=1'b1;
      font[3186]=1'b1;
      font[3187]=1'b1;
      font[3201]=1'b1;
      font[3202]=1'b1;
      font[3203]=1'b1;
      font[3208]=1'b1;
      font[3212]=1'b1;
      font[3220]=1'b1;
      font[3227]=1'b1;
      font[3234]=1'b1;
      font[3241]=1'b1;
      font[3248]=1'b1;
      font[3249]=1'b1;
      font[3250]=1'b1;
      font[3251]=1'b1;
      font[3252]=1'b1;
      font[3264]=1'b1;
      font[3265]=1'b1;
      font[3266]=1'b1;
      font[3267]=1'b1;
      font[3276]=1'b1;
      font[3284]=1'b1;
      font[3289]=1'b1;
      font[3290]=1'b1;
      font[3291]=1'b1;
      font[3300]=1'b1;
      font[3308]=1'b1;
      font[3312]=1'b1;
      font[3313]=1'b1;
      font[3314]=1'b1;
      font[3315]=1'b1;
      font[3331]=1'b1;
      font[3338]=1'b1;
      font[3339]=1'b1;
      font[3345]=1'b1;
      font[3347]=1'b1;
      font[3352]=1'b1;
      font[3355]=1'b1;
      font[3360]=1'b1;
      font[3361]=1'b1;
      font[3362]=1'b1;
      font[3363]=1'b1;
      font[3364]=1'b1;
      font[3371]=1'b1;
      font[3379]=1'b1;
      font[3392]=1'b1;
      font[3393]=1'b1;
      font[3394]=1'b1;
      font[3395]=1'b1;
      font[3396]=1'b1;
      font[3400]=1'b1;
      font[3408]=1'b1;
      font[3416]=1'b1;
      font[3417]=1'b1;
      font[3418]=1'b1;
      font[3419]=1'b1;
      font[3428]=1'b1;
      font[3436]=1'b1;
      font[3440]=1'b1;
      font[3441]=1'b1;
      font[3442]=1'b1;
      font[3443]=1'b1;
      font[3457]=1'b1;
      font[3458]=1'b1;
      font[3459]=1'b1;
      font[3464]=1'b1;
      font[3472]=1'b1;
      font[3480]=1'b1;
      font[3481]=1'b1;
      font[3482]=1'b1;
      font[3483]=1'b1;
      font[3488]=1'b1;
      font[3492]=1'b1;
      font[3496]=1'b1;
      font[3500]=1'b1;
      font[3505]=1'b1;
      font[3506]=1'b1;
      font[3507]=1'b1;
      font[3520]=1'b1;
      font[3521]=1'b1;
      font[3522]=1'b1;
      font[3523]=1'b1;
      font[3524]=1'b1;
      font[3532]=1'b1;
      font[3539]=1'b1;
      font[3546]=1'b1;
      font[3553]=1'b1;
      font[3561]=1'b1;
      font[3569]=1'b1;
      font[3585]=1'b1;
      font[3586]=1'b1;
      font[3587]=1'b1;
      font[3592]=1'b1;
      font[3596]=1'b1;
      font[3600]=1'b1;
      font[3604]=1'b1;
      font[3609]=1'b1;
      font[3610]=1'b1;
      font[3611]=1'b1;
      font[3616]=1'b1;
      font[3620]=1'b1;
      font[3624]=1'b1;
      font[3628]=1'b1;
      font[3633]=1'b1;
      font[3634]=1'b1;
      font[3635]=1'b1;
      font[3649]=1'b1;
      font[3650]=1'b1;
      font[3651]=1'b1;
      font[3656]=1'b1;
      font[3660]=1'b1;
      font[3664]=1'b1;
      font[3668]=1'b1;
      font[3673]=1'b1;
      font[3674]=1'b1;
      font[3675]=1'b1;
      font[3676]=1'b1;
      font[3684]=1'b1;
      font[3692]=1'b1;
      font[3697]=1'b1;
      font[3698]=1'b1;
      font[3699]=1'b1;
    end
    wire[7:0]font_char=history_panel?hc:character;
    wire font_allowed=text_x[3:1]<5 && text_y[4:1]<7 &&
       ((history_panel && htx<256 && hty<72 && hindex<16 && hrow_y<14) ||
        (!history_panel && panel && tx<256 && ty<128));
    wire[23:0]foreground=history_panel?24'hffffff:
       (!photo_active && notice!=0 && line_index==0)?24'hff6060:
       line_index==1?24'hffff60:24'hffffff;
    reg[11:0]font_address;reg overlay_q,allowed_q;
    reg[23:0]background_q,foreground_q;
    always @(posedge clk)font_address<={font_char[5:0],text_y[3:1],text_x[3:1]};
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin overlay_q<=0;allowed_q<=0;background_q<=0;foreground_q<=0;end
      else begin overlay_q<=pre_overlay;allowed_q<=font_allowed;
        background_q<=pre_pixel;foreground_q<=foreground;end
    end
    always @*begin overlay=overlay_q;pixel=allowed_q && font[font_address]?foreground_q:background_q;end
 end else begin:combinational_reference
 integer j;
 always @*begin
  overlay=0;pixel=24'hffffff;
  if(state!=0 && !photo_active && ((x+12>=menu_x && x<=menu_x+12 && y+2>=menu_y && y<=menu_y+2) ||
     (y+12>=menu_y && y<=menu_y+12 && x+2>=menu_x && x<=menu_x+2)))begin overlay=1;pixel=24'h00ffff;end
  if(!photo_active && state!=0 && state!=1 && state!=8 && ring(x,y,op_x,op_y))overlay=1;
  if(box || lamp_ink)begin overlay=1;pixel=lamp_color==2?24'h00ff40:24'h909090;end
  if(history_panel)begin overlay=1;pixel=hink?24'hffffff:hborder?24'h607080:24'h101820;end
  if(panel)begin overlay=1;pixel=ink?(!photo_active && notice!=0 && line_index==0?24'hff6060:line_index==1?24'hffff60:24'hffffff):
    border?(lamp_valid && lamp_color==2?24'h40ff80:24'h607080):bar?(dx-8<bar_width?24'h40ff80:24'h405060):24'h101820;end
 end
 end endgenerate
endmodule
