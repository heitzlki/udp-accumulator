`default_nettype none

//-- Register block on the Zynq M_AXI_GP0 port (AXI3 slave), base 0x4000_0000.
//--   0x00  CTRL     bit0 enable (reset 1), bit1 clear-total (write-1, pulses)
//--   0x04  TOTAL    RO  running total
//--   0x08  RX_CNT   RO  datagrams accepted
//--   0x0C  TX_CNT   RO  replies sent
//--   0x10  GMII     RO  frames GEM presented on the GMII
//--   0x14  MAC_RX   RO  frames whose preamble/SFD the MAC accepted
//--   0x18  ERR      RO  {bad_frame[15:0], bad_fcs[15:0]}
//--   0x1C  STAGE    RO  {sticky handshake bits[15:0], frames sent to GEM}
//-- The Zynq GP master tags transactions with IDs that must be reflected
//-- (AWID->BID, ARID->RID). CPU /dev/mem accesses are single-beat, but INCR
//-- bursts are handled anyway by stepping the address each beat.
module axil_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] awaddr,
    input  wire        awvalid,
    output wire        awready,
    input  wire [11:0] awid,
    input  wire [31:0] wdata,
    input  wire [ 3:0] wstrb,
    input  wire        wvalid,
    input  wire        wlast,
    output wire        wready,
    output reg  [11:0] bid,
    output wire [ 1:0] bresp,
    output reg         bvalid,
    input  wire        bready,
    input  wire [31:0] araddr,
    input  wire        arvalid,
    output wire        arready,
    input  wire [11:0] arid,
    input  wire [ 3:0] arlen,
    output wire [31:0] rdata,
    output reg  [11:0] rid,
    output wire [ 1:0] rresp,
    output wire        rlast,
    output reg         rvalid,
    input  wire        rready,

    output reg         enable,
    output reg         clear_total,
    input  wire [31:0] total,
    input  wire [31:0] rx_count,
    input  wire [31:0] tx_count,

    //-- telemetry (0x10..0x1C): where do frames die on the way in?
    input  wire [31:0] dbg_gmii,
    input  wire [31:0] dbg_macrx,
    input  wire [31:0] dbg_err,
    input  wire [31:0] dbg_stage
);

  assign bresp = 2'b00;  // OKAY
  assign rresp = 2'b00;

  initial begin
    enable = 1'b1;
  end

  //-- read channel
  reg [3:0] raddr_word;  // araddr[5:2]
  reg [3:0] rbeats_left;

  assign arready = !rvalid || (rready && rlast);
  assign rlast   = (rbeats_left == 0);
  assign rdata   = (raddr_word[2:0] == 3'd0) ? {30'd0, 1'b0, enable} :
                   (raddr_word[2:0] == 3'd1) ? total :
                   (raddr_word[2:0] == 3'd2) ? rx_count :
                   (raddr_word[2:0] == 3'd3) ? tx_count :
                   (raddr_word[2:0] == 3'd4) ? dbg_gmii :
                   (raddr_word[2:0] == 3'd5) ? dbg_macrx :
                   (raddr_word[2:0] == 3'd6) ? dbg_err : dbg_stage;

  always @(posedge clk) begin
    if (arvalid && arready) begin
      raddr_word  <= araddr[5:2];
      rbeats_left <= arlen;
      rid         <= arid;
      rvalid      <= 1'b1;
    end else if (rvalid && rready) begin
      if (rlast) rvalid <= 1'b0;
      else begin
        raddr_word  <= raddr_word + 1;
        rbeats_left <= rbeats_left - 1;
      end
    end
    if (rst) rvalid <= 1'b0;
  end

  //-- write channel
  reg [3:0] waddr_word;
  reg       w_active;

  assign awready = !w_active && !bvalid;
  assign wready  = w_active;

  always @(posedge clk) begin
    clear_total <= 1'b0;

    if (awvalid && awready) begin
      waddr_word <= awaddr[5:2];
      bid        <= awid;
      w_active   <= 1'b1;
    end

    if (w_active && wvalid) begin
      if (waddr_word == 4'd0 && wstrb[0]) begin
        enable      <= wdata[0];
        clear_total <= wdata[1];
      end
      waddr_word <= waddr_word + 1;
      if (wlast) begin
        w_active <= 1'b0;
        bvalid   <= 1'b1;
      end
    end

    if (bvalid && bready) bvalid <= 1'b0;

    if (rst) begin
      w_active    <= 1'b0;
      bvalid      <= 1'b0;
      enable      <= 1'b1;
      clear_total <= 1'b0;
    end
  end

endmodule
