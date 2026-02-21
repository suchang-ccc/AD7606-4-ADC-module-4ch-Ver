`timescale 1ns / 1ps
module ad7606_top (
    input           clk,        // 系统时钟
    input           rst_n,      // 系统复位
    
    // AD7606硬件接口
    input           busy,
    input           frstdata, 
    input  [15:0]   adc_din,
    output          cs,
    output          rd,
    output          reset,
    output          convst
);

    // AD7606驱动信号
    wire [15:0] ch0_data, ch1_data, ch2_data, ch3_data;
    wire data_valid;
    
    // AD7606驱动实例
    ad7606_drive #(
        .FCLK(100_000_000),
        .SMAPLE(200_000),
        .CHANNEL_NUM(4)
    ) u_ad7606_drive (
        .clk(clk),
        .rst_n(rst_n),
        .busy(busy),
        .frstdata(frstdata),
        .adc_din(adc_din),
        .cs(cs),
        .rd(rd),
        .reset(reset),
        .convst(convst),
        .ch0_data(ch0_data),
        .ch1_data(ch1_data), 
        .ch2_data(ch2_data),
        .ch3_data(ch3_data),
        .data_valid(data_valid)
    );
    
ila_0 u_ila (
	.clk(clk), // input wire clk


	.probe0(ch0_data), // input wire [15:0]  probe0  
	.probe1(ch1_data), // input wire [15:0]  probe1 
	.probe2(ch2_data), // input wire [15:0]  probe2 
	.probe3(ch3_data), // input wire [15:0]  probe3 
	.probe4(data_valid) // input wire [0:0]  probe4
);

endmodule
