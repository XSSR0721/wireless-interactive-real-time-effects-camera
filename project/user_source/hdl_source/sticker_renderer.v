// Four read clients infer copies of the SAME asset; object metadata is independent.
// Width 32..256 in 2-pixel increments; constant reciprocal LUT, no pixel divider.
module sticker_renderer(input clk,rst_n,tick,input [171:0] config_bus,
    input [11:0] scan_x,scan_y,input scan_de,
    output wire alpha,output wire [23:0] pixel);
    wire [3:0] hit,opaque;
    wire [5:0] indices[0:3];
    wire [14:0] palette_addresses[0:3];
    wire [14:0] texture_addresses[0:3];
    genvar g;
    generate for(g=0;g<4;g=g+1) begin:layer
        wire [31:0] slot=config_bus[g*32+:32];
        wire [2:0] asset_id={slot[30],slot[1:0]};
        wire [11:0] lx=slot[22:12],ty=slot[11:2];
        wire [11:0] w=slot[29:23]>112 ? 12'd256:12'd32+{4'd0,slot[29:23],1'b0};
        reg [17:0] step;
        always @* begin
            case(slot[29:23])
                7'd0:step=18'd131072;
                7'd1:step=18'd123362;
                7'd2:step=18'd116509;
                7'd3:step=18'd110377;
                7'd4:step=18'd104858;
                7'd5:step=18'd99865;
                7'd6:step=18'd95326;
                7'd7:step=18'd91181;
                7'd8:step=18'd87382;
                7'd9:step=18'd83887;
                7'd10:step=18'd80660;
                7'd11:step=18'd77673;
                7'd12:step=18'd74899;
                7'd13:step=18'd72316;
                7'd14:step=18'd69906;
                7'd15:step=18'd67651;
                7'd16:step=18'd65536;
                7'd17:step=18'd63551;
                7'd18:step=18'd61681;
                7'd19:step=18'd59919;
                7'd20:step=18'd58255;
                7'd21:step=18'd56680;
                7'd22:step=18'd55189;
                7'd23:step=18'd53774;
                7'd24:step=18'd52429;
                7'd25:step=18'd51151;
                7'd26:step=18'd49933;
                7'd27:step=18'd48771;
                7'd28:step=18'd47663;
                7'd29:step=18'd46604;
                7'd30:step=18'd45591;
                7'd31:step=18'd44621;
                7'd32:step=18'd43691;
                7'd33:step=18'd42800;
                7'd34:step=18'd41944;
                7'd35:step=18'd41121;
                7'd36:step=18'd40330;
                7'd37:step=18'd39569;
                7'd38:step=18'd38837;
                7'd39:step=18'd38131;
                7'd40:step=18'd37450;
                7'd41:step=18'd36793;
                7'd42:step=18'd36158;
                7'd43:step=18'd35545;
                7'd44:step=18'd34953;
                7'd45:step=18'd34380;
                7'd46:step=18'd33826;
                7'd47:step=18'd33289;
                7'd48:step=18'd32768;
                7'd49:step=18'd32264;
                7'd50:step=18'd31776;
                7'd51:step=18'd31301;
                7'd52:step=18'd30841;
                7'd53:step=18'd30394;
                7'd54:step=18'd29960;
                7'd55:step=18'd29538;
                7'd56:step=18'd29128;
                7'd57:step=18'd28729;
                7'd58:step=18'd28340;
                7'd59:step=18'd27963;
                7'd60:step=18'd27595;
                7'd61:step=18'd27236;
                7'd62:step=18'd26887;
                7'd63:step=18'd26547;
                7'd64:step=18'd26215;
                7'd65:step=18'd25891;
                7'd66:step=18'd25576;
                7'd67:step=18'd25267;
                7'd68:step=18'd24967;
                7'd69:step=18'd24673;
                7'd70:step=18'd24386;
                7'd71:step=18'd24106;
                7'd72:step=18'd23832;
                7'd73:step=18'd23564;
                7'd74:step=18'd23302;
                7'd75:step=18'd23046;
                7'd76:step=18'd22796;
                7'd77:step=18'd22551;
                7'd78:step=18'd22311;
                7'd79:step=18'd22076;
                7'd80:step=18'd21846;
                7'd81:step=18'd21621;
                7'd82:step=18'd21400;
                7'd83:step=18'd21184;
                7'd84:step=18'd20972;
                7'd85:step=18'd20764;
                7'd86:step=18'd20561;
                7'd87:step=18'd20361;
                7'd88:step=18'd20165;
                7'd89:step=18'd19973;
                7'd90:step=18'd19785;
                7'd91:step=18'd19600;
                7'd92:step=18'd19419;
                7'd93:step=18'd19240;
                7'd94:step=18'd19066;
                7'd95:step=18'd18894;
                7'd96:step=18'd18725;
                7'd97:step=18'd18559;
                7'd98:step=18'd18397;
                7'd99:step=18'd18237;
                7'd100:step=18'd18079;
                7'd101:step=18'd17925;
                7'd102:step=18'd17773;
                7'd103:step=18'd17624;
                7'd104:step=18'd17477;
                7'd105:step=18'd17332;
                7'd106:step=18'd17190;
                7'd107:step=18'd17051;
                7'd108:step=18'd16913;
                7'd109:step=18'd16778;
                7'd110:step=18'd16645;
                7'd111:step=18'd16514;
                default:step=18'd16384;
            endcase
        end
        wire [11:0] h=asset_id<2 ? w:((asset_id==2 || asset_id==3) ? (w>>1):(w<<1));
        // Portrait 0/1, horizontal 2/3, square 4; IDs 5..7 transparent.
        assign hit[g]=slot[31] && asset_id<4 && scan_de &&
                      scan_x>=lx && scan_x<lx+w && scan_y>=ty && scan_y<ty+h;
        reg [22:0] px,py;
        wire [6:0] u=scan_x==lx ? 7'd0:(asset_id<2 ? px[21:15]:{1'b0,px[21:16]});
        wire [6:0] v=scan_y==ty ? 7'd0:(asset_id==0 ? py[21:15]:py[22:16]);
        wire [14:0] address= !hit[g] ? 15'd0:
            asset_id==0 ? {1'b0,v,u}:
            slot[1] ? (15'd24576+{3'd0,slot[0],v[4:0],u[5:0]}):(15'd16384+{2'd0,v[5:0],u});
        reg hit_q;
        assign texture_addresses[g]=address;
        assign opaque[g]=hit_q && indices[g]!=0;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin px<=0;py<=0;hit_q<=0;end
            else begin
                hit_q<=hit[g];
                if(tick || !slot[31]) begin px<=0;py<=0;end
                else if(hit[g]) begin
                    if(scan_x==lx+w-1'b1) begin
                        px<=0;py<=(scan_y==ty ? 23'd0:py)+step;
                    end else px<=(scan_x==lx ? 23'd0:px)+step;
                end else px<=0;
            end
        end
    end endgenerate
    genvar pair;
    generate for(pair=0;pair<2;pair=pair+1)begin:shared_assets
      sticker_asset_rom_dual asset(.clk(clk),
        .address_a(texture_addresses[pair*2]),.address_b(texture_addresses[pair*2+1]),
        .index_a(indices[pair*2]),.index_b(indices[pair*2+1]),
        .palette_a(palette_addresses[pair*2]),.palette_b(palette_addresses[pair*2+1]));
    end endgenerate
    assign alpha=|opaque;
    // Higher slot ID is in front. Choose the palette index before RGB decode.
    wire [1:0] visible_layer=opaque[3] ? 2'd3:opaque[2] ? 2'd2:opaque[1] ? 2'd1:2'd0;
    sticker_palette palette(.address(palette_addresses[visible_layer]),
        .index(indices[visible_layer]),.rgb(pixel));
endmodule

module sticker_osd(input [171:0] config_bus,input [11:0] x,y,
                   output overlay,output [23:0] pixel);
    wire [2:0] state=config_bus[130:128],notice=config_bus[171:169];
    wire [1:0] selected=config_bus[132:131];
    wire [31:0] item=config_bus[selected*32+:32];
    wire [2:0] selected_asset={item[30],item[1:0]};
    wire selected_valid=config_bus[133] && item[31];
    wire [11:0] mx=config_bus[145:134],my=config_bus[157:146];
    wire [9:0] progress=config_bus[167:158];
    wire busy=config_bus[168];
    wire [11:0] lx=item[22:12],ty=item[11:2];
    wire [11:0] w=item[29:23]>112 ? 12'd256:12'd32+{4'd0,item[29:23],1'b0};
    // Constant decimal labels keep the OSD free of variable /10 and %10.
    function [23:0] width_label;
        input [6:0] size;
        begin
            case(size)
                7'd0:width_label="032";
                7'd1:width_label="034";
                7'd2:width_label="036";
                7'd3:width_label="038";
                7'd4:width_label="040";
                7'd5:width_label="042";
                7'd6:width_label="044";
                7'd7:width_label="046";
                7'd8:width_label="048";
                7'd9:width_label="050";
                7'd10:width_label="052";
                7'd11:width_label="054";
                7'd12:width_label="056";
                7'd13:width_label="058";
                7'd14:width_label="060";
                7'd15:width_label="062";
                7'd16:width_label="064";
                7'd17:width_label="066";
                7'd18:width_label="068";
                7'd19:width_label="070";
                7'd20:width_label="072";
                7'd21:width_label="074";
                7'd22:width_label="076";
                7'd23:width_label="078";
                7'd24:width_label="080";
                7'd25:width_label="082";
                7'd26:width_label="084";
                7'd27:width_label="086";
                7'd28:width_label="088";
                7'd29:width_label="090";
                7'd30:width_label="092";
                7'd31:width_label="094";
                7'd32:width_label="096";
                7'd33:width_label="098";
                7'd34:width_label="100";
                7'd35:width_label="102";
                7'd36:width_label="104";
                7'd37:width_label="106";
                7'd38:width_label="108";
                7'd39:width_label="110";
                7'd40:width_label="112";
                7'd41:width_label="114";
                7'd42:width_label="116";
                7'd43:width_label="118";
                7'd44:width_label="120";
                7'd45:width_label="122";
                7'd46:width_label="124";
                7'd47:width_label="126";
                7'd48:width_label="128";
                7'd49:width_label="130";
                7'd50:width_label="132";
                7'd51:width_label="134";
                7'd52:width_label="136";
                7'd53:width_label="138";
                7'd54:width_label="140";
                7'd55:width_label="142";
                7'd56:width_label="144";
                7'd57:width_label="146";
                7'd58:width_label="148";
                7'd59:width_label="150";
                7'd60:width_label="152";
                7'd61:width_label="154";
                7'd62:width_label="156";
                7'd63:width_label="158";
                7'd64:width_label="160";
                7'd65:width_label="162";
                7'd66:width_label="164";
                7'd67:width_label="166";
                7'd68:width_label="168";
                7'd69:width_label="170";
                7'd70:width_label="172";
                7'd71:width_label="174";
                7'd72:width_label="176";
                7'd73:width_label="178";
                7'd74:width_label="180";
                7'd75:width_label="182";
                7'd76:width_label="184";
                7'd77:width_label="186";
                7'd78:width_label="188";
                7'd79:width_label="190";
                7'd80:width_label="192";
                7'd81:width_label="194";
                7'd82:width_label="196";
                7'd83:width_label="198";
                7'd84:width_label="200";
                7'd85:width_label="202";
                7'd86:width_label="204";
                7'd87:width_label="206";
                7'd88:width_label="208";
                7'd89:width_label="210";
                7'd90:width_label="212";
                7'd91:width_label="214";
                7'd92:width_label="216";
                7'd93:width_label="218";
                7'd94:width_label="220";
                7'd95:width_label="222";
                7'd96:width_label="224";
                7'd97:width_label="226";
                7'd98:width_label="228";
                7'd99:width_label="230";
                7'd100:width_label="232";
                7'd101:width_label="234";
                7'd102:width_label="236";
                7'd103:width_label="238";
                7'd104:width_label="240";
                7'd105:width_label="242";
                7'd106:width_label="244";
                7'd107:width_label="246";
                7'd108:width_label="248";
                7'd109:width_label="250";
                7'd110:width_label="252";
                7'd111:width_label="254";
                default:width_label="256";
            endcase
        end
    endfunction
    wire [11:0] h=selected_asset<2 ? w:((selected_asset==2 || selected_asset==3) ? (w>>1):(w<<1));
    wire frame=state==5 && selected_valid &&
        ((x>=lx && x<lx+w && (y==ty || y==ty+h-1'b1)) ||
         (y>=ty && y<ty+h && (x==lx || x==lx+w-1'b1)));
    wire origin=state!=0 && x+24>=mx && x<=mx+24 && y+24>=my && y<=my+24 &&
        ((x==mx && (y+6>=my && y<=my+6)) ||
         (y==my && (x+6>=mx && x<=mx+6)) ||
         ((x+24==mx || x==mx+24) && (y+24==my || y==my+24)));
    wire panel=x>=1008 && x<1264 && y>=110 && y<222;
    wire [11:0] dx=x-1016,dy=y-118;
    wire [1:0] line_id=dy[6:5];
    // Only dx<192 is visible; use the exact bounded character coordinates.
    wire [3:0] char_col=dx[7:0]/8'd12;
    wire [3:0] char_x=dx[7:0]%8'd12;
    wire [5:0] glyph_index=6'd34-({2'b0,dy[4:1]}+{dy[4:1],2'b0})-
                           {3'b0,char_x[3:1]};
    reg [127:0] text_line;
    reg [7:0] ch;
    reg [34:0] glyph;
    always @* begin
        case(state)
          0:text_line="BLUE HOLD CENTER";
          1:text_line="STICKER MENU    ";
          2:text_line="SIZE UP+ DOWN-  ";
          3:text_line="MOVE BLUE PEN   ";
          4:case(selected_asset)
              0:text_line="NEW BEAR 1 OF 4 ";
              1:text_line="NEW HAT 2 OF 4  ";
              2:text_line="NEW MUSTACHE 3/4";
              3:text_line="NEW GLASSES 4/4 ";
              default:text_line="UNKNOWN ASSET   ";
            endcase
          5:text_line="SELECT L/R DNDEL";
          default:text_line="SAVED RETURN    ";
        endcase
        if(line_id==1) begin
            case(state)
              0:text_line="KEEP STILL 0.3S ";
              1:text_line="L SIZE R MOVE   ";
              2,3,4,5:text_line=busy ? "BLUE1 CHECKING  ":"BLUE1 TO SAVE   ";
              default:text_line="ORIGIN HOLD 0.4S";
            endcase
        end
        if(line_id==2) begin
            if(state==1) text_line="UP NEW DN SELECT";
            else if(state==0) text_line="USE CENTER AREA ";
            else if(!selected_valid) text_line="NO OBJECT       ";
            else begin
                text_line="ID 1 W 064 ON   ";
                text_line[103:96]=8'd49+{6'd0,selected};
                text_line[71:48]=width_label(item[29:23]);
            end
            case(notice)
              1:text_line="CREATE ONE FIRST";
              2:text_line="FULL 4 OBJECTS  ";
              3:text_line="SAVE OK         ";
              4:text_line="CANCELLED       ";
              5:text_line="DELETE PENDING  ";
              default:begin end
            endcase
        end
        ch=8'd32;
        if(dx<192) ch=text_line[{(4'd15-char_col),3'b000} +: 8];
        case(ch)
          "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
          "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
          "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
          "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
          "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
          "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
          "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
          "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
          "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
          "J":glyph=35'b00111_00010_00010_00010_00010_10010_01100;
          "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
          "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
          "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
          "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
          "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
          "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
          "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
          "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
          "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
          "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
          "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
          "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
          "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
          "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
          "Z":glyph=35'b11111_00001_00010_00100_01000_10000_11111;
          "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
          "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
          "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
          "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
          "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
          "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
          "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
          "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
          "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
          "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
          "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
          "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
          "/":glyph=35'b00001_00010_00010_00100_01000_01000_10000;
          ".":glyph=35'b00000_00000_00000_00000_00000_00110_00110;
          default:glyph=0;
        endcase
    end
    wire ink=dx<192 && dy<96 && char_x<10 && dy[4:0]<14 &&
             glyph[glyph_index];
    wire bar=panel && y>=215 && y<219 && x>=1016 && x<1256;
    // Default 400ms hold: 5/8 maps it to a 250px meter without multipliers.
    wire [12:0] progress_times_five={3'b0,progress}+({3'b0,progress}<<2);
    wire [12:0] progress_pixels=state==5 ? ({3'b0,progress}>>1):(progress_times_five>>3);
    assign overlay=panel || frame || origin;
    assign pixel=frame ? 24'hffffff:origin ? ((state==2 || state==4 || state==5) ? 24'hffcc30:24'hff3030):
        ink ? 24'hffffff:bar ? ((x-1016)<progress_pixels ? 24'h40ff80:24'h405060):24'h101820;
endmodule
