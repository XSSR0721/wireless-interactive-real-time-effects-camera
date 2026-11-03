/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
module awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk  ,
    input                   I_rst_n,


    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                          RGB565תRGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];
    
    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};
    
    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;
    
  /*****************************************************************
                          中间信号                                        
*****************************************************************/


  reg         I_tvalid_r0,I_tvalid_r1;
  reg  [95:0] I_tdata_d0,I_tdata_d1;


  //累加RGB通道的�??
  // One of four parallel pixels contributes per valid beat. Include the
  // accumulator's initial 1; 1280x720 gives 58,752,001, requiring 26 bits.
  localparam AWB_SUM_BITS = $clog2((IMG_WIDTH/4)*IMG_HEIGHT*255+2);
  reg  [AWB_SUM_BITS-1:0] sum_r[0:3];
  reg  [AWB_SUM_BITS-1:0] sum_g[0:3];
  reg  [AWB_SUM_BITS-1:0] sum_b[0:3];

  
  wire  [95:0]        data_d0 ;
  wire                valid_d0;
  wire                I_tuser_r0;    

  reg                 I_tuser_r1;

  reg   [95:0]        data_d1 ;
  reg                 valid_d1;
  reg   [9:0]         rgb_sum[0:3];//每个像素点RGB的和
  /*****************************************************************
                            平均值计�??                                      
*****************************************************************/

// 对输入数据和有效信号进行寄存，形成流水线
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end

// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d[0:3];
wire [7:0] rgb888_g_d[0:3];
wire [7:0] rgb888_b_d[0:3];

assign  rgb888_r_d[0] = I_tdata[16+:8];
assign  rgb888_g_d[0] = I_tdata[8+:8];
assign  rgb888_b_d[0] = I_tdata[0+:8];


// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d0[0:3];
wire [7:0] rgb888_g_d0[0:3];
wire [7:0] rgb888_b_d0[0:3];

assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];


        ///削弱白色
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                rgb_sum[0] <= 0;
            end
            else if(I_tvalid)begin
                rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
            end
        end

        // 对每个通道的值进行累加，用于计算平均值
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                // 复位或行开始信号有效时，清零累加器
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end else if (I_tvalid_r0 && (rgb_sum[0] < 720)) begin
                // 当输入有效时，累加RGB分量的值
                sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
                sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
                sum_b[0] <= sum_b[0] + rgb888_b_d0[0];
            end
        end

  /*****************************************************************
                           计算增益                                       
*****************************************************************/

  wire [47:0] dout_R[3:0];
  wire [47:0] dout_B[3:0];

  wire done[3:0];

  wire [47:0] in_r_x1;
  wire [47:0] in_b_x1;
  assign in_r_x1 = dout_R[0][47:0];
  assign in_b_x1 = dout_B[0][47:0];



/*****************************************************************
                   IP 调用                                    
*****************************************************************/
    //为了保证合理的延迟，这里使用了除法器

      awb_gain_divider #(.SUM_BITS(AWB_SUM_BITS)) div_gen_G_R_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(I_tvalid_r1),
          .denominator(sum_r[0]),  // input wire [31 : 0] s_axis_divisor_tdata
          .green_sum(sum_g[0]),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_R[0]),  // output wire [79 : 0] m_axis_dout_tdata
          .done(done[0])
      );

      awb_gain_divider #(.SUM_BITS(AWB_SUM_BITS)) divide_G_B_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(I_tvalid_r1),
          .denominator(sum_b[0]),  // input wire [31 : 0] s_axis_divisor_tdata
          .green_sum(sum_g[0]),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_B[0]),  // output wire [79 : 0] m_axis_dout_tdata
          .done()
      );

     
    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    )signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );

    

/*****************************************************************
                            ��������                                      
*****************************************************************/

    reg  [19:0]   in_r_r1;
    reg  [19:0]   in_b_r1;
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n || I_tuser)begin
            in_r_r1 <= 20'h10000;
            in_b_r1 <= 20'h10000;
        end
        else if(done[0])begin
            if(|in_r_x1[47:20])
                in_r_r1 <= 20'hfffff;
            else 
                in_r_r1 <= in_r_x1[19:0];
            if(|in_b_x1[47:20])
                in_b_r1 <= 20'hfffff;
            else 
                in_b_r1 <= in_b_x1[19:0];
        end
    end


    ////信号同步
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ��������                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
        end
    end

/*****************************************************************
                            �������???                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (R_new_r1[27:24])?255:R_new_r1[23:16];
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24])?255:B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24])?255:R_new_r2[23:16];
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24])?255:B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24])?255:R_new_r3[23:16];
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24])?255:B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24])?255:R_new_r4[23:16];
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24])?255:B_new_r4[23:16];

    function [7:0] ccm_clip;
        input signed [19:0] value;
        begin
            if (value < 0)
                ccm_clip = 8'd0;
            else if (value > 20'sd255)
                ccm_clip = 8'd255;
            else
                ccm_clip = value[7:0];
        end
    endfunction

    function [7:0] ccm_r;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        reg signed [19:0] acc;
        begin
            acc = ($signed({2'b0,r}) * 10'sd288) -
                  ($signed({2'b0,g}) * 10'sd16 ) -
                  ($signed({2'b0,b}) * 10'sd16 ) + 20'sd128;
            ccm_r = ccm_clip(acc >>> 8);
        end
    endfunction

    function [7:0] ccm_g;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        reg signed [19:0] acc;
        begin
            acc = -($signed({2'b0,r}) * 10'sd12 ) +
                   ($signed({2'b0,g}) * 10'sd284) -
                   ($signed({2'b0,b}) * 10'sd16 ) + 20'sd128;
            ccm_g = ccm_clip(acc >>> 8);
        end
    endfunction

    function [7:0] ccm_b;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        reg signed [19:0] acc;
        begin
            acc = -($signed({2'b0,r}) * 10'sd12 ) -
                   ($signed({2'b0,g}) * 10'sd20 ) +
                   ($signed({2'b0,b}) * 10'sd288) + 20'sd128;
            ccm_b = ccm_clip(acc >>> 8);
        end
    endfunction

    reg [7:0] C_new_r1;
    reg [7:0] C_new_g1;
    reg [7:0] C_new_b1;

    reg [7:0] C_new_r2;
    reg [7:0] C_new_g2;
    reg [7:0] C_new_b2;

    reg [7:0] C_new_r3;
    reg [7:0] C_new_g3;
    reg [7:0] C_new_b3;

    reg [7:0] C_new_r4;
    reg [7:0] C_new_g4;
    reg [7:0] C_new_b4;

    // Pipeline CCM before saturation; preserve the arithmetic and stream alignment.
    reg ccm_valid, ccm_last, ccm_user;
    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ccm_valid<=0;ccm_last<=0;ccm_user<=0;
            C_new_r1<=0;C_new_g1<=0;C_new_b1<=0;
            C_new_r2<=0;C_new_g2<=0;C_new_b2<=0;
            C_new_r3<=0;C_new_g3<=0;C_new_b3<=0;
            C_new_r4<=0;C_new_g4<=0;C_new_b4<=0;
        end else begin
            ccm_valid<=valid_d2;
            ccm_last<=(!valid_d1 && valid_d2);
            ccm_user<=I_tuser;
            C_new_r1<=ccm_r(R_new_x1,G_new_x1,B_new_x1);
            C_new_g1<=ccm_g(R_new_x1,G_new_x1,B_new_x1);
            C_new_b1<=ccm_b(R_new_x1,G_new_x1,B_new_x1);
            C_new_r2<=ccm_r(R_new_x2,G_new_x2,B_new_x2);
            C_new_g2<=ccm_g(R_new_x2,G_new_x2,B_new_x2);
            C_new_b2<=ccm_b(R_new_x2,G_new_x2,B_new_x2);
            C_new_r3<=ccm_r(R_new_x3,G_new_x3,B_new_x3);
            C_new_g3<=ccm_g(R_new_x3,G_new_x3,B_new_x3);
            C_new_b3<=ccm_b(R_new_x3,G_new_x3,B_new_x3);
            C_new_r4<=ccm_r(R_new_x4,G_new_x4,B_new_x4);
            C_new_g4<=ccm_g(R_new_x4,G_new_x4,B_new_x4);
            C_new_b4<=ccm_b(R_new_x4,G_new_x4,B_new_x4);
        end
    end

    function [7:0] sat_clip;
        input signed [10:0] value;
        begin
            if (value < 0)
                sat_clip = 8'd0;
            else if (value > 11'sd255)
                sat_clip = 8'd255;
            else
                sat_clip = value[7:0];
        end
    endfunction

    function [7:0] sat_y;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        reg [9:0] y_sum;
        begin
            y_sum = {2'b0,r[7:2]} + {2'b0,r[7:5]} +
                    {2'b0,g[7:1]} + {2'b0,g[7:4]} +
                    {2'b0,b[7:4]} + {2'b0,b[7:5]};
            sat_y = (y_sum[9:8] != 2'b00) ? 8'd255 : y_sum[7:0];
        end
    endfunction

    function [7:0] sat_boost;
        input [7:0] c;
        input [7:0] y;
        reg signed [10:0] diff;
        reg signed [10:0] boosted;
        begin
            diff = $signed({3'b0,c}) - $signed({3'b0,y});
            boosted = $signed({3'b0,c}) + (diff >>> 2);
            sat_boost = sat_clip(boosted);
        end
    endfunction

    wire [7:0] Y_new_1 = sat_y(C_new_r1, C_new_g1, C_new_b1);
    wire [7:0] S_new_r1 = sat_boost(C_new_r1, Y_new_1);
    wire [7:0] S_new_g1 = sat_boost(C_new_g1, Y_new_1);
    wire [7:0] S_new_b1 = sat_boost(C_new_b1, Y_new_1);

    wire [7:0] Y_new_2 = sat_y(C_new_r2, C_new_g2, C_new_b2);
    wire [7:0] S_new_r2 = sat_boost(C_new_r2, Y_new_2);
    wire [7:0] S_new_g2 = sat_boost(C_new_g2, Y_new_2);
    wire [7:0] S_new_b2 = sat_boost(C_new_b2, Y_new_2);

    wire [7:0] Y_new_3 = sat_y(C_new_r3, C_new_g3, C_new_b3);
    wire [7:0] S_new_r3 = sat_boost(C_new_r3, Y_new_3);
    wire [7:0] S_new_g3 = sat_boost(C_new_g3, Y_new_3);
    wire [7:0] S_new_b3 = sat_boost(C_new_b3, Y_new_3);

    wire [7:0] Y_new_4 = sat_y(C_new_r4, C_new_g4, C_new_b4);
    wire [7:0] S_new_r4 = sat_boost(C_new_r4, Y_new_4);
    wire [7:0] S_new_g4 = sat_boost(C_new_g4, Y_new_4);
    wire [7:0] S_new_b4 = sat_boost(C_new_b4, Y_new_4);
/*****************************************************************
                           ͬ���ź�                                       
*****************************************************************/

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign  O_tlast  = ccm_last;
    assign  O_tuser  = ccm_user;
    assign  O_tvalid = ccm_valid;

    assign  O_tdata = O_tvalid?{S_new_r4,S_new_g4,S_new_b4,
                       S_new_r3,S_new_g3,S_new_b3,
                       S_new_r2,S_new_g2,S_new_b2,
                       S_new_r1,S_new_g1,S_new_b1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule




// AWB-specific saturated Q16 gain. One input per clock, 50 register stages.
// For D>0, floor((G<<16)/D) >= 2^20 iff (G>>4) >= D.
// Otherwise the upper quotient bits are zero: start with remainder G>>4
// and divide only the remaining 20 dividend bits {G[3:0],16'b0}.
// Output is exact below saturation; above it, all ones preserve the existing
// consumer's |quotient[47:20] saturation test. Not a general 48-bit divider.
module awb_gain_divider #(parameter SUM_BITS=26)(
    input clk,rst,start,
    input [SUM_BITS-1:0] denominator,green_sum,
    output reg [47:0] quotient,
    output reg done
);
    localparam GAIN_BITS=20;
    localparam ALIGN_STAGES=50-GAIN_BITS-2;
    reg [GAIN_BITS-1:0] q[0:GAIN_BITS];
    reg [SUM_BITS-1:0] remainder[0:GAIN_BITS];
    reg [SUM_BITS-1:0] den[0:GAIN_BITS];
    reg [48:0] valid_pipe=49'd0;
    reg [48:0] saturate_pipe;
    always @(posedge clk) begin
        valid_pipe<={valid_pipe[47:0],start};
        // This also saturates D==0, matching the old divide-by-zero result.
        saturate_pipe<={saturate_pipe[47:0],(green_sum >> 4)>=denominator};
        q[0]<={green_sum[3:0],16'b0};
        remainder[0]<=green_sum >> 4;
        den[0]<=denominator;
    end
    genvar i;
    generate for(i=0;i<GAIN_BITS;i=i+1) begin: divide_bit
        wire [SUM_BITS:0] trial={remainder[i],q[i][GAIN_BITS-1]};
        wire [SUM_BITS+1:0] difference={1'b0,trial}-{2'b0,den[i]};
        wire fits=~difference[SUM_BITS+1];
        always @(posedge clk) begin
            q[i+1]<={q[i][GAIN_BITS-2:0],fits};
            remainder[i+1]<=fits ? difference[SUM_BITS-1:0] : trial[SUM_BITS-1:0];
            den[i+1]<=den[i];
        end
    end endgenerate
    reg [GAIN_BITS-1:0] alignment[0:ALIGN_STAGES-1];
    integer j;
    always @(posedge clk) begin
        alignment[0]<=q[GAIN_BITS];
        for(j=1;j<ALIGN_STAGES;j=j+1) alignment[j]<=alignment[j-1];
    end
    // Keep the original final-register-only reset, including in-flight data.
    always @(posedge clk or posedge rst) begin
        if(rst) begin quotient<=0;done<=0;end
        else begin
            quotient<=saturate_pipe[48] ? 48'hffffffffffff :
                      {28'b0,alignment[ALIGN_STAGES-1]};
            done<=valid_pipe[48];
        end
    end
endmodule