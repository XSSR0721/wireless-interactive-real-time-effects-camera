// Restricted IPv4/UDP photo transport. Independent of video clocks.
// LAN profile: MTU<=1500, IPv4 without options/fragments, fixed endpoints.
// App sends finite datagrams; Ethernet FCS generated locally, UDP checksum 0.
module photo_udp_tx #(parameter LOCAL_IP=32'hc0a88902,REMOTE_IP=32'hc0a88901,
 parameter LOCAL_MAC=48'h020000000002,LOCAL_PORT=16'd6002,REMOTE_PORT=16'd6001)(
 input clk,rst_n,start,input[10:0]length,input[7:0]app_byte,
 output[10:0]app_address,output busy,output reg done,
 output reg[7:0]tx_data,output tx_valid);
 localparam IDLE=0,PRE=1,FRAME=2,FCS=3,GAP=4;
 reg[2:0]state;reg[10:0]pos,len;reg[15:0]ip_checksum;
 reg[31:0]crc;reg[3:0]gap;
 function[31:0]crc_byte;input[31:0]c;input[7:0]b;reg[31:0]v;integer j;begin
  v=c^{24'd0,b};for(j=0;j<8;j=j+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;
 end endfunction
 function[15:0]ip_sum;input[15:0]l;reg[19:0]v;begin
  v=20'h4500+l+20'h4000+20'h4011+LOCAL_IP[31:16]+LOCAL_IP[15:0]+REMOTE_IP[31:16]+REMOTE_IP[15:0];
  v={4'd0,v[15:0]}+v[19:16];v={4'd0,v[15:0]}+v[19:16];ip_sum=~v[15:0];
 end endfunction
 wire[15:0]ip_length={5'd0,len}+16'd28,udp_length={5'd0,len}+16'd8;
 assign app_address=pos-11'd42;
 assign busy=state!=IDLE;assign tx_valid=state==PRE || state==FRAME || state==FCS;
 always @*begin
  tx_data=0;
  if(state==PRE)tx_data=pos==7?8'hd5:8'h55;
  else if(state==FCS)tx_data=~crc[7:0];
  else if(state==FRAME)begin
   case(pos)
    0,1,2,3,4,5:tx_data=8'hff;
    6:tx_data=LOCAL_MAC[47:40];7:tx_data=LOCAL_MAC[39:32];8:tx_data=LOCAL_MAC[31:24];
    9:tx_data=LOCAL_MAC[23:16];10:tx_data=LOCAL_MAC[15:8];11:tx_data=LOCAL_MAC[7:0];
    12:tx_data=8'h08;13:tx_data=8'h00;14:tx_data=8'h45;15:tx_data=0;
    16:tx_data=ip_length[15:8];17:tx_data=ip_length[7:0];18,19:tx_data=0;
    20:tx_data=8'h40;21:tx_data=0;22:tx_data=64;23:tx_data=17;
    24:tx_data=ip_checksum[15:8];25:tx_data=ip_checksum[7:0];
    26:tx_data=LOCAL_IP[31:24];27:tx_data=LOCAL_IP[23:16];28:tx_data=LOCAL_IP[15:8];29:tx_data=LOCAL_IP[7:0];
    30:tx_data=REMOTE_IP[31:24];31:tx_data=REMOTE_IP[23:16];32:tx_data=REMOTE_IP[15:8];33:tx_data=REMOTE_IP[7:0];
    34:tx_data=LOCAL_PORT[15:8];35:tx_data=LOCAL_PORT[7:0];36:tx_data=REMOTE_PORT[15:8];37:tx_data=REMOTE_PORT[7:0];
    38:tx_data=udp_length[15:8];39:tx_data=udp_length[7:0];40,41:tx_data=0;
    default:tx_data=pos<42+len?app_byte:8'd0;
   endcase
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;pos<=0;len<=0;crc<=32'hffffffff;gap<=0;done<=0;ip_checksum<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start && length>=18 && length<=1456)begin len<=length;ip_checksum<=ip_sum({5'd0,length}+16'd28);pos<=0;state<=PRE;end
    PRE:if(pos==7)begin pos<=0;crc<=32'hffffffff;state<=FRAME;end else pos<=pos+1'b1;
    FRAME:begin
      crc<=crc_byte(crc,tx_data);
      if((pos==41+len && pos>=59) || (len<18 && pos==59))begin pos<=0;state<=FCS;end else pos<=pos+1'b1;
    end
    FCS:begin crc<={8'd0,crc[31:8]};if(pos==3)begin state<=GAP;gap<=0;end else pos<=pos+1'b1;end
    GAP:if(gap==11)begin state<=IDLE;done<=1;end else gap<=gap+1'b1;
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Accept only 16-byte PENP commands, validate Ethernet FCS before mailbox publish.
// No ARP/TCP/ICMP/cache: PC uses limited broadcast requests on the direct LAN.
module photo_udp_command #(parameter LOCAL_IP=32'hc0a88902,LOCAL_PORT=16'd6002)(
 input clk,rst_n,input[7:0]data,input valid,error,input ack,
 output reg request,output reg[127:0]command);
 reg framed,last_valid,bad;reg[10:0]pos;reg[31:0]crc;reg[47:0]pending;
 (* async_reg="true" *)reg[1:0]ack_sync;
 function[31:0]crc_byte;input[31:0]c;input[7:0]b;reg[31:0]v;integer j;begin
  v=c^{24'd0,b};for(j=0;j<8;j=j+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;
 end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin framed<=0;last_valid<=0;bad<=0;pos<=0;crc<=32'hffffffff;pending<=0;command<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};last_valid<=valid;
   if(valid)begin
    if(!framed)begin
      if(data==8'hd5)begin framed<=1;pos<=0;bad<=error;crc<=32'hffffffff;end
    end else begin
      if(pos<1535)pos<=pos+1'b1;else bad<=1;
      crc<=crc_byte(crc,data);if(error)bad<=1;
      case(pos)
       12:if(data!=8'h08)bad<=1;13:if(data!=0)bad<=1;
       14:if(data!=8'h45)bad<=1;
       16:if(data!=0)bad<=1;17:if(data!=44)bad<=1;
       20:if((data&8'hbf)!=0)bad<=1;21:if(data!=0)bad<=1;
       23:if(data!=17)bad<=1;
       30:if(data!=LOCAL_IP[31:24] && data!=255)bad<=1;
       31:if(data!=LOCAL_IP[23:16] && data!=255)bad<=1;
       32:if(data!=LOCAL_IP[15:8] && data!=255)bad<=1;
       33:if(data!=LOCAL_IP[7:0] && data!=255)bad<=1;
       36:if(data!=LOCAL_PORT[15:8])bad<=1;37:if(data!=LOCAL_PORT[7:0])bad<=1;
       38:if(data!=0)bad<=1;39:if(data!=24)bad<=1;
       42:if(data!="P")bad<=1;43:if(data!="E")bad<=1;44:if(data!="N")bad<=1;45:if(data!="P")bad<=1;
       46:if(data!=1)bad<=1;
       47:begin pending[47:40]<=data;if(data<1 || data>3)bad<=1;end
       48:pending[39:32]<=data;49:pending[31:24]<=data;
       50:if(data!=0)bad<=1;
       51:begin pending[23:16]<=data;if(data>=64)bad<=1;end
       52:pending[15:8]<=data;53:pending[7:0]<=data;
       54,55,56,57:if(data!=0)bad<=1;
       default:begin end
      endcase
    end
   end else if(last_valid)begin
    framed<=0;
    if(framed && !bad && pos>=64 && pos<=1518 && crc==32'hdebb20e3 &&
       ack_sync[1]==request)begin command<={32'h50454e50,8'd1,pending[47:40],pending[39:24],8'd0,pending[23:0],32'd0};request<=~request;end
   end
  end
 end
endmodule
