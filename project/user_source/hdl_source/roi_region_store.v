// One committed region mask (0=background, 1=A), with an inactive build bank.
// Rasterization is an OFFLINE serial even/odd test: two shared multipliers,
// bounded 128 vertices, no divider and no polygon arithmetic in the video path.
module roi_region_store #(
 parameter W=320,H=180,MAX_POINTS=128,MIN_AREA=16,
 parameter CELLS=W*H,AW=$clog2(CELLS)
)(input clk,rst_n,frame_start,input [AW-1:0] query_addr,
 output wire query_label,output wire query_trail,
 input start_draw,add_point,close_draw,create_region,delete_region,cancel_draw,
 input edit_id,input [8:0] point_x,input [7:0] point_y,
 output wire ready,busy,output reg done,output reg [2:0] error,
 output reg used);
 localparam INIT=0,IDLE=1,CLEAR=2,LINE=3,F_BEGIN=4,F_READ=5,F_CALC=6,F_TEST=7,F_WRITE=8,
            D_READ=9,D_WAIT=10,D_WRITE=11,COMMIT=12;
 reg [3:0] state;
 wire q0,q1;wire trail_q;reg query_bank,query_enabled;
 reg bank,initialized,drawing,closed,deleting;
 reg [AW-1:0] address;
 reg [8:0] cell_x;reg [7:0] cell_y;
 reg [7:0] vertex_count;reg [6:0] edge_index;wire [16:0] vertex_q;
 reg [8:0] first_x,last_x,prev_x,line_x,target_x;
 reg [7:0] first_y,last_y,prev_y,line_y,target_y;
 reg signed [11:0] line_dx,line_dy,line_err;
 reg signed [1:0] line_sx,line_sy;
 reg signed [11:0] line_next_err;
 reg [8:0] line_next_x;reg [7:0] line_next_y;
 wire signed [12:0] twice_err=$signed(line_err)<<<1;
 reg inside_polygon,hit,crossing,upwards;
 reg signed [23:0] product_a,product_b;
 reg [AW:0] area_count;
 
 wire inside_next=inside_polygon ^ (crossing && (upwards ? product_a>product_b:product_a<product_b));
 wire [AW-1:0] line_addr=line_y*W+line_x;
 wire bg_write=state==INIT || state==F_WRITE || state==D_WRITE;
 wire write_label=state==F_WRITE && hit;
 wire [AW-1:0] trail_addr=state==LINE?line_addr:address;
 wire signed [11:0] vx2=$signed({2'b0,vertex_q[16:8],1'b0});
 wire signed [11:0] vy2=$signed({3'b0,vertex_q[7:0],1'b0});
 wire signed [11:0] px2=$signed({2'b0,prev_x,1'b0});
 wire signed [11:0] py2=$signed({3'b0,prev_y,1'b0});
 wire signed [11:0] qx2=$signed({2'b0,cell_x,1'b1});
 wire signed [11:0] qy2=$signed({3'b0,cell_y,1'b1});
 assign ready=initialized && state==IDLE;
 assign busy=state!=IDLE;
 assign query_label=query_enabled?(query_bank?q1:q0):1'b0;
 assign query_trail=query_enabled && drawing && state!=CLEAR?trail_q:1'b0;
 // Each label RAM has a video-read port and one shared background read/write
 // port. Never clear committed data to edit a region.
 roi_eram_dp #(.DW(1),.AW(AW),.DEPTH(CELLS)) labels0(
  .clk(clk),.ra(query_addr),.qa(q0),.rb(address),.qb(),
  .we(bg_write && (state==INIT || bank)),.di(write_label));
 roi_eram_dp #(.DW(1),.AW(AW),.DEPTH(CELLS)) labels1(
  .clk(clk),.ra(query_addr),.qa(q1),.rb(address),.qb(),
  .we(bg_write && (state==INIT || !bank)),.di(write_label));
 roi_eram_dp #(.DW(1),.AW(AW),.DEPTH(CELLS)) trail_mem(
  .clk(clk),.ra(query_addr),.qa(trail_q),.rb(trail_addr),.qb(),
  .we(state==INIT || state==CLEAR || state==LINE),.di(state==LINE));
 wire vertex_we=state==IDLE && (start_draw || (drawing && add_point && vertex_count<MAX_POINTS));
 roi_eram_dp #(.DW(17),.AW(7),.DEPTH(MAX_POINTS)) vertices(
  .clk(clk),.ra(edge_index),.qa(vertex_q),.rb(start_draw?7'd0:vertex_count[6:0]),.qb(),
  .we(vertex_we),.di({point_x,point_y}));
 always @(posedge clk)begin
  query_bank<=(state==COMMIT && frame_start)?~bank:bank;
  query_enabled<=initialized;
 end
 always @*begin
  line_next_err=line_err;line_next_x=line_x;line_next_y=line_y;
  if(twice_err>=line_dy)begin line_next_err=line_next_err+line_dy;line_next_x=line_sx[1]?line_x-9'd1:line_x+9'd1;end
  if(twice_err<=line_dx)begin line_next_err=line_next_err+line_dx;line_next_y=line_sy[1]?line_y-8'd1:line_y+8'd1;end
 end
 task setup_line;
  input [8:0] ax,bx;input [7:0] ay,by;
  reg signed [11:0] dx,dy;
  begin
   dx=ax>bx?ax-bx:bx-ax;dy=-(ay>by?ay-by:by-ay);
   line_x<=ax;line_y<=ay;target_x<=bx;target_y<=by;
   line_dx<=dx;line_dy<=dy;line_err<=dx+dy;
   line_sx<=ax<bx?2'sd1:-2'sd1;line_sy<=ay<by?2'sd1:-2'sd1;state<=LINE;
  end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=INIT;bank<=0;initialized<=0;address<=0;used<=0;done<=0;error<=0;
   drawing<=0;closed<=0;deleting<=0;
   cell_x<=0;cell_y<=0;vertex_count<=0;edge_index<=0;
   first_x<=0;first_y<=0;last_x<=0;last_y<=0;prev_x<=0;prev_y<=0;
   line_x<=0;line_y<=0;target_x<=0;target_y<=0;line_dx<=0;line_dy<=0;line_err<=0;line_sx<=1;line_sy<=1;
   inside_polygon<=0;hit<=0;crossing<=0;upwards<=0;product_a<=0;product_b<=0;area_count<=0;
  end else begin
   done<=0;
   if(cancel_draw && initialized && state!=COMMIT)begin state<=IDLE;drawing<=0;closed<=0;end
   else case(state)
    INIT:if(address==CELLS-1)begin address<=0;initialized<=1;state<=IDLE;end else address<=address+1'b1;
    IDLE:begin
     if(start_draw && point_x<W && point_y<H)begin
      first_x<=point_x;last_x<=point_x;first_y<=point_y;last_y<=point_y;
      vertex_count<=1;drawing<=1;closed<=0;error<=0;address<=0;state<=CLEAR;
     end else if(add_point && drawing && !closed && vertex_count<MAX_POINTS && point_x<W && point_y<H)begin
      setup_line(last_x,point_x,last_y,point_y);last_x<=point_x;last_y<=point_y;vertex_count<=vertex_count+1'b1;
     end else if(close_draw && drawing)begin setup_line(last_x,first_x,last_y,first_y);closed<=1;end
     else if(create_region)begin
      if(!drawing || !closed || vertex_count<3 || !edit_id || used)begin error<=3;done<=1;end
      else begin deleting<=0;area_count<=0;address<=0;cell_x<=0;cell_y<=0;state<=F_BEGIN;end
     end else if(delete_region)begin
      if(!edit_id || !used)begin error<=3;done<=1;end
      else begin deleting<=1;error<=0;address<=0;state<=D_READ;end
     end
    end
    CLEAR:if(address==CELLS-1)begin address<=0;setup_line(first_x,first_x,first_y,first_y);end else address<=address+1'b1;
    LINE:if(line_x==target_x && line_y==target_y)state<=IDLE;
         else begin line_x<=line_next_x;line_y<=line_next_y;line_err<=line_next_err;end
    F_BEGIN:begin prev_x<=last_x;prev_y<=last_y;edge_index<=0;inside_polygon<=0;state<=F_READ;end
    F_READ:state<=F_CALC;
    F_CALC:begin
     product_a<=(vx2-px2)*(qy2-py2);product_b<=(qx2-px2)*(vy2-py2);
     crossing<=(vy2>qy2)!=(py2>qy2);upwards<=vy2>py2;state<=F_TEST;
    end
    F_TEST:begin
     inside_polygon<=inside_next;prev_x<=vertex_q[16:8];prev_y<=vertex_q[7:0];
     if({1'b0,edge_index}==vertex_count-1'b1)begin hit<=inside_next;state<=F_WRITE;end
     else begin edge_index<=edge_index+1'b1;state<=F_READ;end
    end
    F_WRITE:begin
     if(hit)area_count<=area_count+1'b1;
     if(address==CELLS-1)begin
      drawing<=0;closed<=0;
      if(area_count+hit<MIN_AREA)begin error<=1;done<=1;state<=IDLE;end
      else begin error<=0;state<=COMMIT;end
     end else begin
      address<=address+1'b1;
      if(cell_x==W-1)begin cell_x<=0;cell_y<=cell_y+1'b1;end else cell_x<=cell_x+1'b1;
      state<=F_BEGIN;
     end
    end
    D_READ:state<=D_WAIT;
    D_WAIT:state<=D_WRITE;
    D_WRITE:if(address==CELLS-1)state<=COMMIT;else begin address<=address+1'b1;state<=D_READ;end
    COMMIT:if(frame_start)begin bank<=~bank;used<=!deleting;done<=1;state<=IDLE;end
    default:state<=INIT;
   endcase
  end
 end
endmodule

// Use the same logical ERAM primitive as the existing Anlogic-generated IP.
// Portable simulation models its NOREG synchronous read/read-before-write
// interface; production synthesis always instantiates PH1P_LOGIC_ERAM.
module roi_eram_dp #(parameter DW=2,AW=16,DEPTH=57600)(
 input clk,input [AW-1:0] ra,rb,input we,input [DW-1:0] di,
 output [DW-1:0] qa,qb);
`ifdef ROI_PORTABLE_SIM
 reg [DW-1:0] mem[0:DEPTH-1];reg [DW-1:0] a,b;
 assign qa=a;assign qb=b;
 always @(posedge clk)begin a<=mem[ra];b<=mem[rb];if(we)mem[rb]<=di;end
`else
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(DW),.DATA_WIDTH_B(DW),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
  .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),.IMPLEMENT("20K(FAST)"),
  .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
  .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.INIT_FILE("NONE"),.FILL_ALL("NONE"))
 mem(.clka(clk),.clkb(clk),.cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),
  .wea(1'b0),.web(we),.dia({DW{1'b0}}),.dib(di),.addra(ra),.addrb(rb),.doa(qa),.dob(qb),
  .bea(1'b0),.beb(1'b0),.rsta(1'b0),.rstb(1'b0),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
`endif
endmodule
