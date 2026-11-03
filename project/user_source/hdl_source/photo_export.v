// Snapshot reader owns the shared DDR command stream only for one 1KiB block.
// Wait for all display read responses before tagging photo responses.
module photo_block_dma #(parameter TIMEOUT_BITS=19)(input clk,rst_n,request,input[21:0]offset,input[1:0]bank,
 output reg acknowledge,output reg failed,output busy,output rd_en,output[24:0]address,
 input ready,write_busy,display_busy,display_safe,read_idle,input[9:0]display_outstanding,
 input data_valid,input[127:0]data,
 input net_clk,input[9:0]net_address,output[7:0]net_byte,
 output photo_response);
 (* async_reg="true" *)reg[1:0]req_sync;
 reg[3:0]idle_guard;reg reserved;reg active,issuing,aborting;reg[TIMEOUT_BITS-1:0]watchdog;reg[6:0]sent,received;reg[24:0]addr;
 reg[127:0]memory[0:63]; // synthesis ram_style=bram
 reg[127:0]net_word;
 wire[9:0]next_address=net_address+10'd1;
 always @(posedge net_clk)net_word<=memory[next_address[9:4]];
 assign net_byte=net_word[127-{net_address[3:0],3'b000}-:8];
 assign busy=reserved || active;
 assign rd_en=active && issuing && ready;
 assign address=addr;
 assign photo_response=active;
 function[24:0]base;input[1:0]b;begin case(b)
  0:base=0;1:base=7000000;2:base=14000000;3:base=21000000;
 endcase end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin req_sync<=0;reserved<=0;idle_guard<=0;failed<=0;watchdog<=0;aborting<=0;active<=0;issuing<=0;sent<=0;received<=0;addr<=0;acknowledge<=0;end
  else begin
   req_sync<={req_sync[0],request};
   if(reserved && !active && req_sync[1]!=acknowledge && !write_busy && !display_busy && read_idle)begin
     if(!(&idle_guard))idle_guard<=idle_guard+1'b1;
   end else idle_guard<=0;
   if(!active && !reserved && req_sync[1]!=acknowledge && display_safe)begin reserved<=1;idle_guard<=0;end
   if((req_sync[1]==acknowledge && !active) || (active && data_valid))watchdog<=0;
   else if(!(&watchdog))watchdog<=watchdog+1'b1;
   if(!active && req_sync[1]!=acknowledge && (&watchdog))begin
     failed<=1;reserved<=0;acknowledge<=req_sync[1];watchdog<=0;
   end
   if(active && (&watchdog))begin issuing<=0;aborting<=1;failed<=1;end
   // Never retag late photo responses as display pixels. Abort releases only after drain.
   if(active && aborting && read_idle)begin
     active<=0;reserved<=0;aborting<=0;acknowledge<=req_sync[1];watchdog<=0;
   end
   if(reserved && !active && req_sync[1]!=acknowledge && !write_busy && !display_busy && read_idle && (&idle_guard) && !(&watchdog))begin
    active<=1;issuing<=1;failed<=0;aborting<=0;watchdog<=0;sent<=0;received<=0;addr<=base(bank)+{4'd0,offset[21:1]};
   end
   if(rd_en)begin
    addr<=addr+25'd8;
    if(sent==63)issuing<=0;
    sent<=sent+1'b1;
   end
   if(active && data_valid)begin
    received<=received+1'b1;
    if(received==63 && !aborting)begin active<=0;reserved<=0;acknowledge<=req_sync[1];end
   end
  end
 end
 always @(posedge clk)if(active && data_valid && !aborting)memory[received[5:0]]<=data;
endmodule

module photo_key4 #(parameter CLK_HZ=50000000,HOLD_MS=800)(input clk,rst_n,pressed,exposure_mode,
 output reg short_toggle,long_toggle);
 localparam DEBOUNCE_LAST=CLK_HZ/1000*20-1;
 reg[19:0]debounce;reg key_pressed;
 (* async_reg="true" *)reg[2:0]sync;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin debounce<=0;key_pressed<=0;end
   else if(sync[2]==key_pressed)debounce<=0;
   else if(debounce>=DEBOUNCE_LAST)begin key_pressed<=sync[2];debounce<=0;end
   else debounce<=debounce+1'b1;
 end
 localparam LAST=CLK_HZ/1000*HOLD_MS-1;
 reg[25:0]count;reg held;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count<=0;held<=0;short_toggle<=0;long_toggle<=0;sync<=0;end
  else begin
   sync<={sync[1:0],pressed};
   if(exposure_mode)begin count<=0;held<=0;end
   else if(key_pressed)begin
    if(!held)begin
     if(count==LAST)begin long_toggle<=~long_toggle;held<=1;end
     else count<=count+1'b1;
    end
   end else begin
    if(count>=CLK_HZ/1000*20 && !held)short_toggle<=~short_toggle;
    count<=0;held<=0;
   end
  end
 end
endmodule

module photo_export_control #(parameter SETTLE_BIT=22)(input clk,rst_n,input[127:0]command,input cmd_request,output reg cmd_ack,
 input trigger,input snapshot_valid,input[1:0]snapshot_bank,input[127:0]stickers,
 output reg locked,output reg[1:0]held_bank,
 output reg dma_request,output reg[21:0]dma_offset,input dma_ack,input dma_failed,
 output reg tx_start,output reg[10:0]tx_length,input tx_busy,tx_done,
 input[10:0]app_address,input[7:0]photo_byte,output reg[7:0]app_byte,
 output[9:0]photo_address);
 (* async_reg="true" *)reg[2:0]cmd_sync,trigger_sync;
 (* async_reg="true" *)reg[1:0]dma_sync,valid_sync;
 reg trigger_seen;reg[15:0]epoch;reg[30:0]idle;

 reg[7:0]response_type;reg[31:0]response_offset;
 reg[2:0]state;
 localparam IDLE=0,WAIT_DMA=1,TX_ARM=2,TX_WAIT=3,SETTLE=4;
 wire[7:0]op=command[87:80];wire[15:0]req_epoch=command[79:64];
 wire[31:0]req_offset=command[63:32];
 assign photo_address=app_address[9:0]-10'd16; // next TX byte prefetch; pixel body starts after16B app header
 function[7:0]header;input[3:0]a;begin case(a)
  0:header="P";1:header="E";2:header="N";3:header="P";4:header=1;5:header=response_type;
  6:header=epoch[15:8];7:header=epoch[7:0];
  8:header=response_offset[31:24];9:header=response_offset[23:16];10:header=response_offset[15:8];11:header=response_offset[7:0];
  12:header=response_type==8'h82 ? 8'd4:8'd0;13:header=response_type==8'h81 ? 8'd32:response_type==8'h80 ? 8'd2:8'd0;
  14:header=0;15:header=1;
 endcase end endfunction
 wire[10:0]body=app_address-11'd16;
 always @*begin
  app_byte=0;
  if(app_address<16)app_byte=header(app_address[3:0]);
  else if(response_type==8'h82)app_byte=photo_byte;
  else if(response_type==8'h81)begin
   case(body)
    0:app_byte=8'h05;1:app_byte=0;2:app_byte=8'h02;3:app_byte=8'hd0;
    4:app_byte=0;5:app_byte=8'h2a;6:app_byte=8'h30;7:app_byte=0;
    24:app_byte=8'h5f;25:app_byte=8'h43;26:app_byte=8'h8f;27:app_byte=8'hd0;
    default:if(body>=8 && body<24)app_byte=stickers[(body-8)*8+:8];
   endcase
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cmd_sync<=0;trigger_sync<=0;trigger_seen<=0;cmd_ack<=0;dma_sync<=0;valid_sync<=0;
   locked<=0;held_bank<=0;epoch<=0;idle<=0;dma_request<=0;dma_offset<=0;
   tx_start<=0;tx_length<=0;response_type<=0;response_offset<=0;state<=IDLE;end
  else begin
   cmd_sync<={cmd_sync[1:0],cmd_request};trigger_sync<={trigger_sync[1:0],trigger};
   dma_sync<={dma_sync[0],dma_ack};valid_sync<={valid_sync[0],snapshot_valid};tx_start<=0;
   if(locked)begin if(&idle && state==IDLE)locked<=0;else idle<=idle+1'b1;end
   if(trigger_sync[2]!=trigger_seen)begin
    trigger_seen<=trigger_sync[2];
    if(!locked && state==IDLE && valid_sync[1])begin
      locked<=1;epoch<=epoch+1'b1;idle<=0;state<=SETTLE;
    end
   end
   case(state)
    IDLE:if(cmd_sync[2]!=cmd_ack)begin
     cmd_ack<=cmd_sync[2];
     if(locked)begin
      idle<=0;
      if(op==1)begin response_type<=8'h81;response_offset<=0;tx_length<=48;state<=TX_ARM;end
      else if(op==3 && req_epoch==epoch)locked<=0;
      else if(op==2 && req_epoch==epoch && req_offset<2764800 && req_offset[9:0]==0)begin
       dma_offset<=req_offset[21:0];response_offset<=req_offset;dma_request<=~dma_request;
       response_type<=8'h82;tx_length<=1040;state<=WAIT_DMA;
      end
     end
    end
    SETTLE:if(idle[SETTLE_BIT])begin held_bank<=snapshot_bank;state<=IDLE;end
    WAIT_DMA:if(dma_sync[1]==dma_request)begin
      if(dma_failed)begin response_type<=8'h80;tx_length<=18;locked<=0;end
      state<=TX_ARM;
    end
    TX_ARM:if(!tx_busy)begin tx_start<=1;state<=TX_WAIT;end
    TX_WAIT:if(tx_done)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
