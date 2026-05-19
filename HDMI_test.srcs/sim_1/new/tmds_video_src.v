`timescale 1ns/1ps

module tmds_video_src(
    input rest,            // 高电平有效复位 (active-high reset)
    input clk_pix,
    input [7:0] red,       // 保留接口（本模块内部生成色条，外部输入被忽略）
    input [7:0] green,
    input [7:0] blue,
    output [2:0] TMDS_Data_p,
    output [2:0] TMDS_Data_n,
    output TMDS_Clk_p,
    output TMDS_Clk_n
);

// 1920x1080@60Hz 时序参数 (根据VESA标准)
localparam H_ACTIVE   = 1920;  // 有效像素
localparam H_FP       = 88;    // 前沿
localparam H_SYNC     = 44;    // 同步脉冲
localparam H_BP       = 148;   // 后沿
localparam H_TOTAL    = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 2200

localparam V_ACTIVE   = 1080;  // 有效行数
localparam V_FP       = 4;     // 前沿
localparam V_SYNC     = 5;     // 同步脉冲
localparam V_BP       = 36;    // 后沿
localparam V_TOTAL    = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 1125

reg hsync, vsync, de;
reg [23:0] vid_pData;
// 使用定宽寄存器以便综合友好：
reg [11:0] h_count;            // 水平计数器，最大 2200 < 4096
reg [10:0] v_count;            // 垂直计数器，最大 1125 < 2048

// 色条生成的临时索引
reg [2:0] bar_idx;
localparam BAR_WIDTH = H_ACTIVE/8; // 8 条色条

rgb2dvi u_rgb2dvi (
    .TMDS_Clk_p(TMDS_Clk_p),
    .TMDS_Clk_n(TMDS_Clk_n),
    .TMDS_Data_p(TMDS_Data_p),
    .TMDS_Data_n(TMDS_Data_n),
    .aRst(rest),
    .PixelClk(clk_pix),
    .vid_pData(vid_pData),
    .vid_pVDE(de),
    .vid_pHSync(hsync),
    .vid_pVSync(vsync)
);

always @(posedge clk_pix) begin
    if (rest) begin
        // 复位：清除计数与信号
        h_count <= 0;
        v_count <= 0;
        hsync <= 1;     // 同步信号默认为高（本设计为低有效）
        vsync <= 1;
        de <= 0;
        vid_pData <= 24'h000000;
    end else begin
        // 生成数据有效信号：在水平/垂直有效区域时为 1
        de <= (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        $display("h_count=%d, v_count=%d, hsync=%b, vsync=%b, de=%b, bar_idx=%d", 
                 h_count, v_count, hsync, vsync, de, bar_idx);

        // 水平同步 (低有效)：在 ACTIVE + FP 到 ACTIVE + FP + SYNC - 1
        if (h_count >= (H_ACTIVE + H_FP) && h_count < (H_ACTIVE + H_FP + H_SYNC))
            hsync <= 0;
        else
            hsync <= 1;

        // 垂直同步 (低有效)：在 V_ACTIVE + V_FP 到 V_ACTIVE + V_FP + V_SYNC - 1
        if (v_count >= (V_ACTIVE + V_FP) && v_count < (V_ACTIVE + V_FP + V_SYNC))
            vsync <= 0;
        else
            vsync <= 1;

        // 在有效显示区生成 8 条色条（从左到右）：白/黄/青/绿/品红/红/蓝/黑
        if (de) begin
            // 计算当前像素所属色条索引
            bar_idx <= h_count / BAR_WIDTH;
            // 注意：`rgb2dvi` 要求 `vid_pData` 按 RBG 顺序打包（见 rgb2dvi 文档）:
            // vid_pData[23:16]=R, [15:8]=B, [7:0]=G
            case (bar_idx)
                3'd0: vid_pData <= {8'hFF,8'hFF,8'hFF}; // 白 (R=FF,B=FF,G=FF)
                3'd1: vid_pData <= {8'hFF,8'h00,8'hFF}; // 黄 (R=FF,G=FF,B=00) -> {R,B,G}
                3'd2: vid_pData <= {8'h00,8'hFF,8'hFF}; // 青 (R=00,G=FF,B=FF)
                3'd3: vid_pData <= {8'h00,8'h00,8'hFF}; // 绿 (R=00,G=FF,B=00)
                3'd4: vid_pData <= {8'hFF,8'hFF,8'h00}; // 品红 (R=FF,G=00,B=FF)
                3'd5: vid_pData <= {8'hFF,8'h00,8'h00}; // 红 (R=FF,G=00,B=00)
                3'd6: vid_pData <= {8'h00,8'h00,8'hFF}; // 蓝 (R=00,G=00,B=FF)
                default: vid_pData <= {8'h00,8'h00,8'h00}; // 黑
            endcase
        end else begin
            vid_pData <= 24'h000000;
        end

        // 水平计数器自增与回绕（注意先判断边界以便更新垂直计数）
        if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1;
        end else begin
            h_count <= h_count + 1;
        end
    end
end

endmodule