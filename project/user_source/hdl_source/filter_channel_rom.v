// Exact channel mappings. Both read ports have the same one-clock latency
// as the existing filter input registers, so the video pipeline is unchanged.
module filter_channel_rom(input clk,input [10:0] a,b,output reg [7:0] qa,qb);
 (* rom_style="block" *) reg [7:0] mem[0:2047];
 function [7:0] value;
  input [10:0] address;integer x,v;
  begin
   x=address[7:0];
   case(address[10:8])
    1:v=x-(x>>2);
    2:v=x+(x>>2)+12;
    3:v=x+(x>>4)+2;
    4:v=x+(x>>4)+4;
    5:v=x+(x>>1)-64;
    default:v=x;
   endcase
   value=v<0?8'd0:v>255?8'd255:v[7:0];
  end
 endfunction
 integer i;
 initial for(i=0;i<2048;i=i+1)mem[i]=value(i);
 always @(posedge clk)begin qa<=mem[a];qb<=mem[b];end
endmodule
