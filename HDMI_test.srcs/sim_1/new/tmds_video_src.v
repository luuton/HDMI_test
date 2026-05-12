`timescale 1ns/1ps

module tmds_video_src_v(
  input  reset_n,
  input  pixclk,
  output reg [2:0] tmds_d_p,
  output reg [2:0] tmds_d_n
);

  // 1080p60 timing constants
  localparam H_ACTIVE = 1920, H_FP = 88, H_SYNC = 44, H_BP = 148;
  localparam V_ACTIVE = 1080, V_FP = 4,  V_SYNC = 5,  V_BP = 36;
  localparam H_TOTAL  = H_ACTIVE+H_FP+H_SYNC+H_BP; // 2200
  localparam V_TOTAL  = V_ACTIVE+V_FP+V_SYNC+V_BP; // 1125

  integer hc, vc;
  reg de, hsync, vsync;
  reg [7:0] r,g,b;

  // ------------------------------------------------------------
  // Timing counters
  // ------------------------------------------------------------
  always @(posedge pixclk or negedge reset_n) begin
    if (!reset_n) begin
      hc <= 0; vc <= 0;
    end else begin
      if (hc == H_TOTAL-1) begin
        hc <= 0;
        if (vc == V_TOTAL-1) vc <= 0;
        else vc <= vc + 1;
      end else begin
        hc <= hc + 1;
      end
    end
  end

  // ------------------------------------------------------------
  // Video timing + simple color bars
  // ------------------------------------------------------------
  always @(*) begin
    de    = (hc < H_ACTIVE) && (vc < V_ACTIVE);
    hsync = (hc >= H_ACTIVE+H_FP) && (hc < H_ACTIVE+H_FP+H_SYNC);
    vsync = (vc >= V_ACTIVE+V_FP) && (vc < V_ACTIVE+V_FP+V_SYNC);

    if (de) begin
      case (hc / (H_ACTIVE/8))
        0: begin r=8'hFF; g=8'h00; b=8'h00; end
        1: begin r=8'hFF; g=8'h80; b=8'h00; end
        2: begin r=8'hFF; g=8'hFF; b=8'h00; end
        3: begin r=8'h00; g=8'hFF; b=8'h00; end
        4: begin r=8'h00; g=8'hFF; b=8'hFF; end
        5: begin r=8'h00; g=8'h00; b=8'hFF; end
        6: begin r=8'h80; g=8'h00; b=8'hFF; end
        default: begin r=8'hFF; g=8'hFF; b=8'hFF; end
      endcase
    end else begin
      r=8'h00; g=8'h00; b=8'h00;
    end
  end

  // ------------------------------------------------------------
  // TMDS control tokens
  // ------------------------------------------------------------
  function [9:0] ctl_token;
    input c0, c1;
    begin
      case ({c1,c0})
        2'b00: ctl_token = 10'b1101010100;
        2'b01: ctl_token = 10'b0010101011;
        2'b10: ctl_token = 10'b0101010100;
        2'b11: ctl_token = 10'b1010101011;
      endcase
    end
  endfunction

  function integer ones8;
    input [7:0] x;
    begin
      ones8 = x[0]+x[1]+x[2]+x[3]+x[4]+x[5]+x[6]+x[7];
    end
  endfunction

  // ------------------------------------------------------------
  // TMDS encode task
  // - blanking(DE=0): output control token; reset disparity
  // - active(DE=1): encode 8b -> 10b per DVI TMDS
  // ------------------------------------------------------------
  task tmds_encode;
    input  [7:0] din;
    input        de_i;
    input        c0;
    input        c1;
    inout integer rd;
    output [9:0] dout;
    reg [8:0] q_m;
    integer n1, n0, balance;
    reg invert;
    begin
      if (!de_i) begin
        rd = 0;
        dout = ctl_token(c0,c1);
      end else begin
        // transition minimization
        n1 = ones8(din);
        q_m[0] = din[0];
        if ((n1 > 4) || ((n1==4) && (din[0]==0))) begin
          q_m[1]=~(q_m[0]^din[1]);
          q_m[2]=~(q_m[1]^din[2]);
          q_m[3]=~(q_m[2]^din[3]);
          q_m[4]=~(q_m[3]^din[4]);
          q_m[5]=~(q_m[4]^din[5]);
          q_m[6]=~(q_m[5]^din[6]);
          q_m[7]=~(q_m[6]^din[7]);
          q_m[8]=1'b0;
        end else begin
          q_m[1]=(q_m[0]^din[1]);
          q_m[2]=(q_m[1]^din[2]);
          q_m[3]=(q_m[2]^din[3]);
          q_m[4]=(q_m[3]^din[4]);
          q_m[5]=(q_m[4]^din[5]);
          q_m[6]=(q_m[5]^din[6]);
          q_m[7]=(q_m[6]^din[7]);
          q_m[8]=1'b1;
        end

        // DC balance
        n1 = q_m[0]+q_m[1]+q_m[2]+q_m[3]+q_m[4]+q_m[5]+q_m[6]+q_m[7];
        n0 = 8 - n1;
        balance = n1 - n0;

        if ((rd==0) || (balance==0)) begin
          invert = ~q_m[8];
          if (invert) begin
            rd = rd + (-balance);
            dout = {1'b1, q_m[8], ~q_m[7:0]};
          end else begin
            rd = rd + (balance);
            dout = {1'b0, q_m[8], q_m[7:0]};
          end
        end else if ((rd>0 && balance>0) || (rd<0 && balance<0)) begin
          rd = rd + (q_m[8] ? -1 : +1) + (-balance);
          dout = {1'b1, q_m[8], ~q_m[7:0]};
        end else begin
          rd = rd + (q_m[8] ? +1 : -1) + (balance);
          dout = {1'b0, q_m[8], q_m[7:0]};
        end
      end
    end
  endtask

  integer rd_r, rd_g, rd_b;
  reg [9:0] sym_r, sym_g, sym_b;

  // per-pixel encode
  always @(posedge pixclk or negedge reset_n) begin
    if (!reset_n) begin
      rd_r <= 0; rd_g <= 0; rd_b <= 0;
      sym_r <= 10'h000; sym_g <= 10'h000; sym_b <= 10'h000;
    end else begin
      // blanking: R/G -> CTL0 ; B -> HS/VS control token
      tmds_encode(r, de, 1'b0, 1'b0, rd_r, sym_r);
      tmds_encode(g, de, 1'b0, 1'b0, rd_g, sym_g);
      tmds_encode(b, de, hsync, vsync, rd_b, sym_b);
    end
  end

  // ------------------------------------------------------------
  // 10x serializer clock (bit clock)
  // bit half-period = pixel_half/10 = 3.367003367/10 = 0.3367003367ns
  // ------------------------------------------------------------
  real BIT_HALF;
  reg bitclk;
  initial begin
    bitclk = 1'b0;
    BIT_HALF = 0.3367003367; // ns
    wait(reset_n);
    forever #(BIT_HALF) bitclk = ~bitclk;
  end

  reg [9:0] sh_r, sh_g, sh_b;
  integer bit_idx;

  always @(posedge bitclk or negedge reset_n) begin
    if (!reset_n) begin
      bit_idx <= 0;
      sh_r <= 10'h0; sh_g <= 10'h0; sh_b <= 10'h0;
      tmds_d_p <= 3'b000;
      tmds_d_n <= 3'b111;
    end else begin
      if (bit_idx == 0) begin
        sh_r <= sym_r;
        sh_g <= sym_g;
        sh_b <= sym_b;
      end

      // lane mapping: [0]=B, [1]=G, [2]=R
      tmds_d_p[0] <= sh_b[0];
      tmds_d_p[1] <= sh_g[0];
      tmds_d_p[2] <= sh_r[0];
      tmds_d_n    <= ~tmds_d_p;

      sh_r <= {1'b0, sh_r[9:1]};
      sh_g <= {1'b0, sh_g[9:1]};
      sh_b <= {1'b0, sh_b[9:1]};

      if (bit_idx == 9) bit_idx <= 0;
      else bit_idx <= bit_idx + 1;
    end
  end

endmodule