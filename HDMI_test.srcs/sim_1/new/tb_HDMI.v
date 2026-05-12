`timescale 1ns/1ps

module tb_HDMI;

  // -------------------------
  // DUT ports
  // -------------------------
  tri  DDC_scl_io;
  tri  DDC_sda_io;

  wire TMDS_OUT_clk_p, TMDS_OUT_clk_n;
  wire [2:0] TMDS_OUT_data_p, TMDS_OUT_data_n;

  reg  TMDS_in_clk_p, TMDS_in_clk_n;
  wire [2:0] TMDS_in_data_p, TMDS_in_data_n;

  reg  clk_in;   // 100MHz
  reg  reset_n;

  // DDC pull-ups
  pullup(DDC_scl_io);
  pullup(DDC_sda_io);

  // -------------------------
  // clk_in = 100MHz
  // -------------------------
  initial begin
    clk_in = 1'b0;
    forever #5 clk_in = ~clk_in;
  end

  // reset
  initial begin
    reset_n = 1'b0;
    #200;
    reset_n = 1'b1;
  end

  // -------------------------
  // TMDS pixel clock = 148.5MHz (1080p60) => period 6.734006734ns
  // half period = 3.367003367ns
  // -------------------------
  real PIX_HALF;
  initial begin
    PIX_HALF = 3.367003367; // ns
    TMDS_in_clk_p = 1'b0;
    TMDS_in_clk_n = 1'b1;
    wait(reset_n);
    forever begin
      #(PIX_HALF);
      TMDS_in_clk_p = ~TMDS_in_clk_p;
      TMDS_in_clk_n = ~TMDS_in_clk_n;
    end
  end

  // -------------------------
  // TMDS source -> drives TMDS_in_data_p/n
  // -------------------------
  tmds_video_src_v u_src (
    .reset_n(reset_n),
    .pixclk(TMDS_in_clk_p),
    .tmds_d_p(TMDS_in_data_p),
    .tmds_d_n(TMDS_in_data_n)
  );

  // -------------------------
  // DUT
  // -------------------------
  wire [23:0]pData;
  wire pHSync;
  wire pVDE;
  wire pVSync;
  wire wiz_locked;
  design_2_wrapper dut (
    .DDC_scl_io(DDC_scl_io),
    .DDC_sda_io(DDC_sda_io),
    .TMDS_OUT_clk_n(TMDS_OUT_clk_n),
    .TMDS_OUT_clk_p(TMDS_OUT_clk_p),
    .TMDS_OUT_data_n(TMDS_OUT_data_n),
    .TMDS_OUT_data_p(TMDS_OUT_data_p),
    .TMDS_in_clk_n(TMDS_in_clk_n),
    .TMDS_in_clk_p(TMDS_in_clk_p),
    .TMDS_in_data_n(TMDS_in_data_n),
    .TMDS_in_data_p(TMDS_in_data_p),
    .clk_in(clk_in),
    .reset_n(reset_n),
    .pData(pData),
    .pHSync(pHSync),
    .pVDE(pVDE),
    .pVSync(pVSync),
    .wiz_locked(wiz_locked)
  );

  // -------------------------
  // Run time
  // -------------------------
  initial begin
    wait(reset_n);
    // 建议跑 >= 40ms（>2帧），给 dvi2rgb 对齐/锁定
    #40000000;
    $finish;
  end

endmodule