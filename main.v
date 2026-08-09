`default_nettype none

//-- Top level. The 125 MHz board clock is divided to the 25 MHz MII clock
//-- that runs everything: GEM1's EMIO GMII (both of its clocks are supplied
//-- by the fabric), the verilog-ethernet stack, and the M_AXI_GP0 register
//-- block. Crossover wiring: GEM1's transmit is our receive and vice versa.
//--
//-- Build variants: default = full design; --env loopback (ACC_LOOPBACK)
//-- wires GEM1 TX straight back to its RX with no MAC in between - a smoke
//-- test for the clock topology and the SLCR setup.
module main (
    input  wire       clk,
    output wire [3:0] leds
);

  wire clk25;
  clkgen #(
      .DIV(5)
  ) clkgen_inst (
      .clk125 (clk),
      .clk_mii(clk25)
  );

  //-- Power-on reset, released after 16 clean clk25 cycles. Built as a
  //-- count-up from zero rather than a preloaded shift register: FFs with
  //-- INIT=1 are not reliably honored through yosys+nextpnr-xilinx, and a
  //-- shift register preloaded with ones can silently yield no reset pulse.
  reg [4:0] por_cnt = 5'd0;
  always @(posedge clk25) if (!por_cnt[4]) por_cnt <= por_cnt + 1;
  wire rst = !por_cnt[4];

  //-- GEM1 EMIO GMII nets. gem_tx* come out of the PS (Linux transmitting),
  //-- gem_rx* go into the PS (Linux receiving).
  wire [7:0] gem_txd;
  wire       gem_tx_en;
  wire       gem_tx_er;
  wire [7:0] gem_rxd;
  wire       gem_rx_dv;
  wire       gem_rx_er;

`ifdef ACC_LOOPBACK

  //-- echo everything Linux sends straight back at it
  assign gem_rxd   = gem_txd;
  assign gem_rx_dv = gem_tx_en;
  assign gem_rx_er = gem_tx_er;

  reg [23:0] hb;
  always @(posedge clk25) hb <= hb + 1;
  reg [3:0] tx_seen;
  always @(posedge clk25) if (gem_tx_en) tx_seen <= 4'hf; else if (hb == 0) tx_seen <= 4'h0;
  assign leds = {2'b00, tx_seen[0], hb[23]};

`else

  //-- slow path: control/telemetry registers on M_AXI_GP0
  wire        reg_enable;
  wire        reg_clear_total;
  wire [31:0] total;
  wire [31:0] rx_count;
  wire [31:0] tx_count;

  wire [31:0] gp0_awaddr;
  wire        gp0_awvalid;
  wire        gp0_awready;
  wire [11:0] gp0_awid;
  wire [31:0] gp0_wdata;
  wire [ 3:0] gp0_wstrb;
  wire        gp0_wvalid;
  wire        gp0_wlast;
  wire        gp0_wready;
  wire [11:0] gp0_bid;
  wire [ 1:0] gp0_bresp;
  wire        gp0_bvalid;
  wire        gp0_bready;
  wire [31:0] gp0_araddr;
  wire        gp0_arvalid;
  wire        gp0_arready;
  wire [11:0] gp0_arid;
  wire [ 3:0] gp0_arlen;
  wire [31:0] gp0_rdata;
  wire [11:0] gp0_rid;
  wire [ 1:0] gp0_rresp;
  wire        gp0_rlast;
  wire        gp0_rvalid;
  wire        gp0_rready;

  wire        rx_start_packet;
  wire        tx_start_packet;
  wire        rx_error_bad_fcs;
  wire        rx_error_bad_frame;

  //-- telemetry: frame counters at each stage of the datapath. Cheap, and
  //-- they turn "no reply" into "frames die between X and Y" without a scope.
  reg  [31:0] dbg_gmii;      // frames GEM presented on the GMII
  reg  [31:0] dbg_macrx;     // frames whose preamble/SFD the MAC accepted
  reg  [15:0] dbg_bad_fcs, dbg_bad_frame;
  reg  [15:0] dbg_togem;     // frames we drove into GEM
  wire        dbg_eth_hdr_ack;
  wire [15:0] dbg_sticky;

  reg gem_tx_en_q, gem_rx_dv_q;
  always @(posedge clk25) begin
    gem_tx_en_q <= gem_tx_en;
    gem_rx_dv_q <= gem_rx_dv;
    if (gem_tx_en && !gem_tx_en_q) dbg_gmii <= dbg_gmii + 1;
    if (rx_start_packet) dbg_macrx <= dbg_macrx + 1;
    if (rx_error_bad_fcs) dbg_bad_fcs <= dbg_bad_fcs + 1;
    if (rx_error_bad_frame) dbg_bad_frame <= dbg_bad_frame + 1;
    if (gem_rx_dv && !gem_rx_dv_q) dbg_togem <= dbg_togem + 1;
    if (rst) begin
      dbg_gmii <= 0;
      dbg_macrx <= 0;
      dbg_bad_fcs <= 0;
      dbg_bad_frame <= 0;
      dbg_togem <= 0;
    end
  end

  acc_core acc_core_inst (
      .clk(clk25),
      .rst(rst),

      //-- crossover: GEM TX -> our RX, our TX -> GEM RX. rx_er is tied off:
      //-- with no PHY there is nothing to signal symbol errors, and the FCS
      //-- check guards data integrity anyway.
      .gmii_rxd  (gem_txd),
      .gmii_rx_dv(gem_tx_en),
      .gmii_rx_er(1'b0),
      .gmii_txd  (gem_rxd),
      .gmii_tx_en(gem_rx_dv),
      .gmii_tx_er(gem_rx_er),

      .enable(reg_enable),
      .clear_total(reg_clear_total),
      .total(total),
      .rx_count(rx_count),
      .tx_count(tx_count),

      .rx_start_packet(rx_start_packet),
      .tx_start_packet(tx_start_packet),
      .rx_error_bad_fcs(rx_error_bad_fcs),
      .rx_error_bad_frame(rx_error_bad_frame),
      .dbg_eth_hdr_ack(dbg_eth_hdr_ack),
      .dbg_sticky(dbg_sticky)
  );

  axil_regs axil_regs_inst (
      .clk(clk25),
      .rst(rst),

      .awaddr(gp0_awaddr),
      .awvalid(gp0_awvalid),
      .awready(gp0_awready),
      .awid(gp0_awid),
      .wdata(gp0_wdata),
      .wstrb(gp0_wstrb),
      .wvalid(gp0_wvalid),
      .wlast(gp0_wlast),
      .wready(gp0_wready),
      .bid(gp0_bid),
      .bresp(gp0_bresp),
      .bvalid(gp0_bvalid),
      .bready(gp0_bready),
      .araddr(gp0_araddr),
      .arvalid(gp0_arvalid),
      .arready(gp0_arready),
      .arid(gp0_arid),
      .arlen(gp0_arlen),
      .rdata(gp0_rdata),
      .rid(gp0_rid),
      .rresp(gp0_rresp),
      .rlast(gp0_rlast),
      .rvalid(gp0_rvalid),
      .rready(gp0_rready),

      .enable(reg_enable),
      .clear_total(reg_clear_total),
      .total(total),
      .rx_count(rx_count),
      .tx_count(tx_count),

      .dbg_gmii (dbg_gmii),
      .dbg_macrx(dbg_macrx),
      .dbg_err  ({dbg_bad_frame, dbg_bad_fcs}),
      .dbg_stage({dbg_sticky, dbg_togem})
  );

  //-- LEDs: heartbeat, rx blip, tx blip, sticky bad-FCS
  reg [23:0] hb;
  always @(posedge clk25) hb <= hb + 1;

  reg [20:0] rx_stretch, tx_stretch;
  reg bad_fcs_sticky;
  always @(posedge clk25) begin
    if (rx_start_packet) rx_stretch <= ~21'd0;
    else if (rx_stretch != 0) rx_stretch <= rx_stretch - 1;
    if (tx_start_packet) tx_stretch <= ~21'd0;
    else if (tx_stretch != 0) tx_stretch <= tx_stretch - 1;
    if (rx_error_bad_fcs) bad_fcs_sticky <= 1'b1;
    if (rst) bad_fcs_sticky <= 1'b0;
  end

  assign leds = {bad_fcs_sticky, tx_stretch != 0, rx_stretch != 0, hb[23]};

`endif

`ifdef SYNTHESIZE
  ps7_enet ps7 (
      .clk(clk25),

      .gem_txd  (gem_txd),
      .gem_tx_en(gem_tx_en),
      .gem_tx_er(gem_tx_er),
      .gem_rxd  (gem_rxd),
      .gem_rx_dv(gem_rx_dv),
      .gem_rx_er(gem_rx_er),

`ifdef ACC_LOOPBACK
      .gp0_awaddr(),
      .gp0_awvalid(),
      .gp0_awready(1'b0),
      .gp0_awid(),
      .gp0_wdata(),
      .gp0_wstrb(),
      .gp0_wvalid(),
      .gp0_wlast(),
      .gp0_wready(1'b0),
      .gp0_bid(12'd0),
      .gp0_bresp(2'd0),
      .gp0_bvalid(1'b0),
      .gp0_bready(),
      .gp0_araddr(),
      .gp0_arvalid(),
      .gp0_arready(1'b0),
      .gp0_arid(),
      .gp0_arlen(),
      .gp0_rdata(32'd0),
      .gp0_rid(12'd0),
      .gp0_rresp(2'd0),
      .gp0_rlast(1'b0),
      .gp0_rvalid(1'b0),
      .gp0_rready()
`else
      .gp0_awaddr(gp0_awaddr),
      .gp0_awvalid(gp0_awvalid),
      .gp0_awready(gp0_awready),
      .gp0_awid(gp0_awid),
      .gp0_wdata(gp0_wdata),
      .gp0_wstrb(gp0_wstrb),
      .gp0_wvalid(gp0_wvalid),
      .gp0_wlast(gp0_wlast),
      .gp0_wready(gp0_wready),
      .gp0_bid(gp0_bid),
      .gp0_bresp(gp0_bresp),
      .gp0_bvalid(gp0_bvalid),
      .gp0_bready(gp0_bready),
      .gp0_araddr(gp0_araddr),
      .gp0_arvalid(gp0_arvalid),
      .gp0_arready(gp0_arready),
      .gp0_arid(gp0_arid),
      .gp0_arlen(gp0_arlen),
      .gp0_rdata(gp0_rdata),
      .gp0_rid(gp0_rid),
      .gp0_rresp(gp0_rresp),
      .gp0_rlast(gp0_rlast),
      .gp0_rvalid(gp0_rvalid),
      .gp0_rready(gp0_rready)
`endif
  );
`endif

endmodule
