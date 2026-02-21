`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/19 10:51:04
// Design Name: 
// Module Name: ad7606_drive
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ad7606_drive #(
    parameter   FCLK    =   50_000_000     ,//系统时钟频率，单位Hz，默认100MHz；
    parameter   SMAPLE  =   200_000        ,  //AD7606采样频率，单位Hz，默认200KHz；
    parameter   CHANNEL_NUM = 4             // AD7606-4有4个通道
)(
    input                   clk             ,//系统时钟，100MHz；
    input                   rst_n           ,//系统复位，低电平有效；

    input                   busy            ,//转换完成指示信号，下降沿有效；
    input                   frstdata        ,//指示采集到的第一个数据；
    input       [15 : 0]    adc_din         ,//AD7606所采集到的十六位数据信号；

    output  reg             cs      = 1'b1  ,//AD7606片选信号，读数据时拉低；
    output  reg             rd      = 1'b1  ,//AD7606读使能信号，读数据时拉低，下降沿时AD7606将数据发送到数据线上，上升沿时可以读出数据；
    output  reg             reset   = 1'b0  ,//AD7606复位信号，高电平有效，每次复位至少拉高50ns；
//    output      [2 : 0]     os              ,//AD7606过采样模式信号，默认不使用过采样；
    output  reg             convst  = 1'b1   //AD7606采样启动信号，无效时高电平，采样计数器完成时拉低两个时钟；
    
//    output  reg [15 : 0]    data    = 'd0   ,//AD7606采集到的数据.数据均为补码；
//    output  reg [7 : 0]     data_vld= 'd0    //指示AD7606输出的数据来自哪个数据通道；
);
    reg [15:0] ch0_data = 16'd0;     // 通道0数据
    reg [15:0] ch1_data = 16'd0;     // 通道1数据  
    reg [15:0] ch2_data = 16'd0;     // 通道2数据
    reg [15:0] ch3_data = 16'd0;     // 通道3数据
    reg        data_valid = 1'b0;   // 数据有效信号
//    reg [15 : 0]    data    = 'd0   ;  // AD7606采集到的数据，数据均为补码
//    reg [7 : 0]     data_vld= 'd0   ;  // 指示AD7606输出的数据来自哪个数据通道
    
    localparam              IDLE    =  5'b00001 ;//空闲状态；
    localparam              CON     =  5'b00010 ;//采样状态；
    localparam              BUSY    =  5'b00100 ;//等待模数转换完成；
    localparam              DATA    =  5'b01000 ;//读数据状态；
    localparam              RST     =  5'b10000 ;//复位ADC状态；

    localparam  DIV_NUM     = FCLK / SMAPLE     ;//计算采样率对应时钟个数；
    localparam  DIV_NUM_W   = $clog2(DIV_NUM-1) ;//使用函数自动计算采样率对应位宽；

    reg         [4 : 0]     state_c             ;
    reg         [4 : 0]     state_n             ;
    reg         [3 : 0]     cnt                 ;
    reg         [3 : 0]     cnt_num             ;//
    reg                     busy_neg    = 1'b0  ;
    reg         [2 : 0]     busy_r      = 3'b111;
    reg         [2 : 0]     rdata_cnt           ;
    reg [DIV_NUM_W - 1 : 0] delay_cnt           ;
    reg                     end_delay_cnt = 'd0 ;
    reg                     rst_flag            ;
    
    wire                    add_cnt             ;
    wire                    end_cnt             ;

//    assign os = 3'b000;//默认不使用过采样；
    // 内部数据寄存器
    reg [15:0] data = 'd0;
    reg [7:0]  data_vld = 'd0;

    //状态机次态到现态的转换；
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            state_c <= IDLE;
        end
        else begin
            state_c <= state_n;
        end
    end

    //状态机次态的跳转；
    always@(*)begin
        case(state_c)
            IDLE : begin
                if(end_delay_cnt)begin//延时计数器计数结束时
                    state_n = rst_flag ? CON : RST;//如果上电复位过，则直接采样数据，否则先进行复位；
                end
                else begin
                    state_n = state_c;
                end
            end
            RST : begin//该状态高电平至少持续50ns；复位低电平到convst高电平至少持续25ns。
                if(end_cnt)begin
                    state_n = IDLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            CON : begin//该状态至少持续25ns；
                if(end_cnt)begin
                    state_n = BUSY;
                end
                else begin
                    state_n = state_c;
                end
            end
            BUSY : begin
                if(busy_neg)begin//检测到busy下降沿后，开始采集数据；
                    state_n = DATA;
                end
                else begin
                    state_n = state_c;
                end
            end
            DATA : begin//读数据状态的读使能高电平至少持续25ns，低电平至少持续32ns。
                if(end_cnt && (cnt == CHANNEL_NUM - 1))begin
                    state_n = IDLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            default : begin
                state_n = IDLE;
            end
        endcase
    end

    //复位状态指示信号，高电平表示上电后完成过复位；
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            rst_flag <= 'd0;
        end
        else if(state_c == RST && end_cnt)begin
            rst_flag <= 1'b1;//复位完成时拉高，之后保持不变；
        end
    end

    //延时计数器，初始值为0。
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            delay_cnt <= 'd0;
        end
        else if(end_delay_cnt)begin
            delay_cnt <= 'd0;
        end
        else begin
            delay_cnt <= delay_cnt + 'd1;
        end
    end

    //延时计数器计数到最大减2之后拉高，其余时间均拉低；
    always@(posedge clk)begin
        end_delay_cnt <= (delay_cnt == DIV_NUM - 'd2);
    end

    //计数器cnt，加一条件处于采样，读数据，复位三个阶段，结束条件为计数cnt_num个时钟；
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            cnt <= 'd0;
        end
        else if(add_cnt)begin
            if(end_cnt)
                cnt <= 'd0;
            else
                cnt <= cnt + 'd1;
        end
    end

    assign add_cnt = (state_c==CON) || ((state_c==DATA) && (rdata_cnt == 'd6)) || (state_c==RST);       
    assign end_cnt = add_cnt && (cnt == cnt_num - 'd1);

    //cnt_num的值，采样阶段为3，读数据阶段为8，复位阶段为5（复位这里也使用8个时钟）；
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            cnt_num <= 'd3;
        end
        else if(state_c == IDLE)begin
            cnt_num <= 'd3;
        end
        else if(state_c == BUSY)begin
            cnt_num <= CHANNEL_NUM;
        end
        else if(state_c == RST)begin
            cnt_num <= 'd8;
        end
    end
    
    always@(posedge clk)begin
        convst <= (state_c != CON);//采样触发信号，处于采样阶段时拉低，其余时间拉高；
        reset <= (state_c == RST);//复位电平最少持续50ns；
        busy_r <= {busy_r[1:0] , busy};//使用移位寄存器将采集的信号暂存；
        busy_neg <= busy_r[2] && (~busy_r[1]);//检测busy下降沿，表示数据是否完成采样；
    end

    //计数器rdata_cnt，计数读数据时每读一个数据所需要的时钟，加一条件为处于读数据阶段，结束条件为计数6个时钟；
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            rdata_cnt <= 'd0;
        end
        else if(state_c == DATA)begin
            if(rdata_cnt == 7 - 1)
                rdata_cnt <= 'd0;
            else
                rdata_cnt <= rdata_cnt + 'd1;
        end
        else begin
            rdata_cnt <= 'd0;
        end
    end

    //片选和读使能信号，当处于读数据阶段并且计数器cnt1计数大于2时拉低，其余时间拉高；
    always@(posedge clk)begin
        if(state_c == DATA)begin
            if(rdata_cnt == 6)begin//当计数器计数结束时拉高，高电平最少持续22ns；
                cs <= 1'b1;
                rd <= 1'b1;
            end
            else if(rdata_cnt == 2)begin//当计数器计数到2时拉低，低电平最好大于32ns；
                cs <= 1'b0;
                rd <= 1'b0;
            end
        end
        else begin//状态机处于其余状态时片选和读使能信号拉高；
            cs <= 1'b1;
            rd <= 1'b1;
        end
    end

    //当读数据计数器计数结束时，根据计数器的数值读取对应通道数据；
    always@(posedge clk)begin
        if((state_c == DATA) && (rdata_cnt == 6) && add_cnt)begin
            data <= adc_din;
            data_vld <= (8'h01 << cnt);
            
            // 根据通道号存储数据
            case(cnt)
                2'd0: ch0_data <= adc_din;
                2'd1: ch1_data <= adc_din;
                2'd2: ch2_data <= adc_din;
                2'd3: ch3_data <= adc_din;
            endcase
            
            // 当读取最后一个通道时产生数据有效信号
            if(cnt == CHANNEL_NUM - 1) begin
                data_valid <= 1'b1;
            end else begin
                data_valid <= 1'b0;
            end
        end else begin
            data_valid <= 1'b0;
        end
    end
    
ila_0 u_ila (
	.clk(clk), // input wire clk


	.probe0(ch0_data), // input wire [15:0]  probe0  
	.probe1(ch1_data), // input wire [15:0]  probe1 
	.probe2(ch2_data), // input wire [15:0]  probe2 
	.probe3(ch3_data), // input wire [15:0]  probe3 
	.probe4(data_valid), // input wire [0:0]  probe4
	.probe5(rst_n), // input wire [0:0]  probe5 
	.probe6(busy), // input wire [0:0]  probe6 
	.probe7(rd), // input wire [0:0]  probe7 
	.probe8(reset), // input wire [0:0]  probe8 
	.probe9(cs), // input wire [0:0]  probe9 
	.probe10(adc_din), // input wire [15:0]  probe10
	.probe11(convst) // input wire [0:0]  probe11
);    
    
    endmodule
