`timescale 1ns/1ps

module tb_HDMI;
reg dut_reset_n;       // active-low reset for DUT/top-level
reg clk_wiz_resetn;   // active-low reset for clk_wiz (keep released)
wire clk_pix;
reg clk_100M;
wire locked;
wire [2:0] TMDS_Data_p;
wire [2:0] TMDS_Data_n;
wire TMDS_Clk_p;
wire TMDS_Clk_n;

tmds_video_src u_tmds_video_src (
    .rest(~locked),
    .clk_pix(clk_pix),
    .red(8'h00),   // 输入色彩数据被忽略，模块内部生成色条
    .green(8'h00),
    .blue(8'h00),
    .TMDS_Data_p(TMDS_Data_p),
    .TMDS_Data_n(TMDS_Data_n),
    .TMDS_Clk_p(TMDS_Clk_p),
    .TMDS_Clk_n(TMDS_Clk_n)
);

wire [2:0] TMDS_Data_n_out, TMDS_Data_p_out;
wire TMDS_Clk_n_out, TMDS_Clk_p_out, wiz_locked, clk_out1, plocked, pVDE;
wire [23:0] pData_out;
design_2_wrapper u_design_2_wrapper (
    .TMDS_in_clk_n(TMDS_Clk_n),
    .TMDS_in_clk_p(TMDS_Clk_p),
    .TMDS_in_data_n(TMDS_Data_n),
    .TMDS_in_data_p(TMDS_Data_p),
    .TMDS_OUT_clk_n(TMDS_Clk_n_out),
    .TMDS_OUT_clk_p(TMDS_Clk_p_out),
    .TMDS_OUT_data_n(TMDS_Data_n_out),
    .TMDS_OUT_data_p(TMDS_Data_p_out),
    .wiz_locked(wiz_locked),
    .clk_out1(clk_out1),
    .pLocked(plocked),
    .pVDE(pVDE),
    .pData(pData_out),
    .reset_n(dut_reset_n),
    .clk_in(clk_100M)
);

parameter period = 10;                   // 100MHz 时钟周期为10ns
always #(period/2) clk_100M = ~clk_100M; // 生成100MHz时钟信号

// 1080p@60Hz像素时钟约为148.5MHz
clk_wiz_0 u_clk_wiz_0 (
    .clk_in1(clk_100M),
    .clk_out1(clk_pix),
    .resetn(clk_wiz_resetn),
    .locked(locked)
);


initial begin
    // 初始化信号：先让 clk_wiz 自由运行以便锁定，保持 DUT 复位
    clk_100M = 0;
    clk_wiz_resetn = 1; // release clk_wiz (active-low)
    dut_reset_n = 0;    // hold DUT in reset (active-low)

    // 等待 clk_wiz 锁定
    wait (locked == 1);
    // 额外等待以保证时钟稳定并让内部对齐逻辑启动
    #(200);
    dut_reset_n = 1; // 解除 DUT 复位

    // 继续运行一段时间以观察输出
    #(period*50000); // 等待5000us，足够观察多个帧的输出

    $finish; // 结束仿真
end

endmodule