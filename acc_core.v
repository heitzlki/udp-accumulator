`default_nettype none

//-- Accumulator datapath, entirely in one clock domain (clk = 25 MHz MII
//-- clock): GMII/MII <-> MAC <-> Ethernet framer <-> UDP/IP/ARP stack <->
//-- acc_app. The GMII side connects to GEM1's EMIO interface in synthesis and
//-- to the testbench in simulation, which is why this module (and not main)
//-- is the unit the testbench instantiates.
//--
//-- Naming note: this module's gmii_rx* is *our MAC's receive* - driven by
//-- GEM1's transmit side - and gmii_tx* drives GEM1's receive side (the
//-- "crossover cable" is wired in main.v).
module acc_core #(
    parameter [47:0] LOCAL_MAC   = 48'h02_00_00_00_00_02,
    parameter [31:0] LOCAL_IP    = {8'd10, 8'd99, 8'd0, 8'd2},
    parameter [31:0] GATEWAY_IP  = {8'd10, 8'd99, 8'd0, 8'd1},
    parameter [31:0] SUBNET_MASK = {8'd255, 8'd255, 8'd255, 8'd0},
    parameter [15:0] LISTEN_PORT = 16'd1234,
    parameter [15:0] REPLY_PORT  = 16'd5678
) (
    input  wire        clk,
    input  wire        rst,

    //-- GMII (MII nibble mode: data on [3:0])
    input  wire [ 7:0] gmii_rxd,
    input  wire        gmii_rx_dv,
    input  wire        gmii_rx_er,
    output wire [ 7:0] gmii_txd,
    output wire        gmii_tx_en,
    output wire        gmii_tx_er,

    //-- control / telemetry (axil_regs)
    input  wire        enable,
    input  wire        clear_total,
    output wire [31:0] total,
    output wire [31:0] rx_count,
    output wire [31:0] tx_count,

    //-- status (LEDs)
    output wire        rx_start_packet,
    output wire        tx_start_packet,
    output wire        rx_error_bad_fcs,
    output wire        rx_error_bad_frame,
    output wire        dbg_eth_hdr_ack,
    output wire [15:0] dbg_sticky
);

  //-- MAC <-> framer streams
  wire [7:0] mac_rx_axis_tdata;
  wire       mac_rx_axis_tvalid;
  wire       mac_rx_axis_tlast;
  wire       mac_rx_axis_tuser;

  wire [7:0] rx_axis_tdata;
  wire       rx_axis_tvalid;
  wire       rx_axis_tready;
  wire       rx_axis_tlast;
  wire       rx_axis_tuser;

  wire [7:0] tx_axis_tdata;
  wire       tx_axis_tvalid;
  wire       tx_axis_tready;
  wire       tx_axis_tlast;
  wire       tx_axis_tuser;

  //-- Ethernet frame interfaces (framer <-> udp_complete)
  wire        rx_eth_hdr_valid;
  wire        rx_eth_hdr_ready;
  wire [47:0] rx_eth_dest_mac;
  wire [47:0] rx_eth_src_mac;
  wire [15:0] rx_eth_type;
  wire [ 7:0] rx_eth_payload_axis_tdata;
  wire        rx_eth_payload_axis_tvalid;
  wire        rx_eth_payload_axis_tready;
  wire        rx_eth_payload_axis_tlast;
  wire        rx_eth_payload_axis_tuser;

  wire        tx_eth_hdr_valid;
  wire        tx_eth_hdr_ready;
  wire [47:0] tx_eth_dest_mac;
  wire [47:0] tx_eth_src_mac;
  wire [15:0] tx_eth_type;
  wire [ 7:0] tx_eth_payload_axis_tdata;
  wire        tx_eth_payload_axis_tvalid;
  wire        tx_eth_payload_axis_tready;
  wire        tx_eth_payload_axis_tlast;
  wire        tx_eth_payload_axis_tuser;

  //-- UDP interfaces (udp_complete <-> acc_app)
  wire        rx_udp_hdr_valid;
  wire        rx_udp_hdr_ready;
  wire [31:0] rx_udp_ip_source_ip;
  wire [15:0] rx_udp_dest_port;
  wire [ 7:0] rx_udp_payload_axis_tdata;
  wire        rx_udp_payload_axis_tvalid;
  wire        rx_udp_payload_axis_tready;
  wire        rx_udp_payload_axis_tlast;
  wire        rx_udp_payload_axis_tuser;

  wire        tx_udp_hdr_valid;
  wire        tx_udp_hdr_ready;
  wire [31:0] tx_udp_ip_source_ip;
  wire [31:0] tx_udp_ip_dest_ip;
  wire [15:0] tx_udp_source_port;
  wire [15:0] tx_udp_dest_port;
  wire [15:0] tx_udp_length;
  wire [ 7:0] tx_udp_payload_axis_tdata;
  wire        tx_udp_payload_axis_tvalid;
  wire        tx_udp_payload_axis_tready;
  wire        tx_udp_payload_axis_tlast;
  wire        tx_udp_payload_axis_tuser;

  eth_mac_1g #(
      .ENABLE_PADDING(1),
      .MIN_FRAME_LENGTH(64)
  ) eth_mac_inst (
      .rx_clk(clk),
      .rx_rst(rst),
      .tx_clk(clk),
      .tx_rst(rst),

      .tx_axis_tdata (tx_axis_tdata),
      .tx_axis_tvalid(tx_axis_tvalid),
      .tx_axis_tready(tx_axis_tready),
      .tx_axis_tlast (tx_axis_tlast),
      .tx_axis_tuser (tx_axis_tuser),

      .rx_axis_tdata (mac_rx_axis_tdata),
      .rx_axis_tvalid(mac_rx_axis_tvalid),
      .rx_axis_tlast (mac_rx_axis_tlast),
      .rx_axis_tuser (mac_rx_axis_tuser),

      .gmii_rxd  (gmii_rxd),
      .gmii_rx_dv(gmii_rx_dv),
      .gmii_rx_er(gmii_rx_er),
      .gmii_txd  (gmii_txd),
      .gmii_tx_en(gmii_tx_en),
      .gmii_tx_er(gmii_tx_er),

      .tx_ptp_ts(96'd0),
      .rx_ptp_ts(96'd0),
      .tx_axis_ptp_ts(),
      .tx_axis_ptp_ts_tag(),
      .tx_axis_ptp_ts_valid(),

      .tx_lfc_req(1'b0),
      .tx_lfc_resend(1'b0),
      .rx_lfc_en(1'b0),
      .rx_lfc_req(),
      .rx_lfc_ack(1'b0),
      .tx_pfc_req(8'd0),
      .tx_pfc_resend(1'b0),
      .rx_pfc_en(8'd0),
      .rx_pfc_req(),
      .rx_pfc_ack(8'd0),
      .tx_lfc_pause_en(1'b0),
      .tx_pause_req(1'b0),
      .tx_pause_ack(),

      //-- both clock enables high, both interfaces in MII nibble mode
      .rx_clk_enable(1'b1),
      .tx_clk_enable(1'b1),
      .rx_mii_select(1'b1),
      .tx_mii_select(1'b1),

      .tx_start_packet(tx_start_packet),
      .tx_error_underflow(),
      .rx_start_packet(rx_start_packet),
      .rx_error_bad_frame(rx_error_bad_frame),
      .rx_error_bad_fcs(rx_error_bad_fcs),
      .stat_tx_mcf(),
      .stat_rx_mcf(),
      .stat_tx_lfc_pkt(),
      .stat_tx_lfc_xon(),
      .stat_tx_lfc_xoff(),
      .stat_tx_lfc_paused(),
      .stat_tx_pfc_pkt(),
      .stat_tx_pfc_xon(),
      .stat_tx_pfc_xoff(),
      .stat_tx_pfc_paused(),
      .stat_rx_lfc_pkt(),
      .stat_rx_lfc_xon(),
      .stat_rx_lfc_xoff(),
      .stat_rx_lfc_paused(),
      .stat_rx_pfc_pkt(),
      .stat_rx_pfc_xon(),
      .stat_rx_pfc_xoff(),
      .stat_rx_pfc_paused(),

      .cfg_ifg(8'd12),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1),
      .cfg_mcf_rx_eth_dst_mcast(48'd0),
      .cfg_mcf_rx_check_eth_dst_mcast(1'b0),
      .cfg_mcf_rx_eth_dst_ucast(48'd0),
      .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
      .cfg_mcf_rx_eth_src(48'd0),
      .cfg_mcf_rx_check_eth_src(1'b0),
      .cfg_mcf_rx_eth_type(16'd0),
      .cfg_mcf_rx_opcode_lfc(16'd0),
      .cfg_mcf_rx_check_opcode_lfc(1'b0),
      .cfg_mcf_rx_opcode_pfc(16'd0),
      .cfg_mcf_rx_check_opcode_pfc(1'b0),
      .cfg_mcf_rx_forward(1'b0),
      .cfg_mcf_rx_enable(1'b0),
      .cfg_tx_lfc_eth_dst(48'd0),
      .cfg_tx_lfc_eth_src(48'd0),
      .cfg_tx_lfc_eth_type(16'd0),
      .cfg_tx_lfc_opcode(16'd0),
      .cfg_tx_lfc_en(1'b0),
      .cfg_tx_lfc_quanta(16'd0),
      .cfg_tx_lfc_refresh(16'd0),
      .cfg_tx_pfc_eth_dst(48'd0),
      .cfg_tx_pfc_eth_src(48'd0),
      .cfg_tx_pfc_eth_type(16'd0),
      .cfg_tx_pfc_opcode(16'd0),
      .cfg_tx_pfc_en(1'b0),
      .cfg_tx_pfc_quanta(128'd0),
      .cfg_tx_pfc_refresh(128'd0),
      .cfg_rx_lfc_opcode(16'd0),
      .cfg_rx_lfc_en(1'b0),
      .cfg_rx_pfc_opcode(16'd0),
      .cfg_rx_pfc_en(1'b0)
  );

  //-- The MAC's rx stream has no tready; this frame FIFO gives the parser
  //-- backpressure room and drops bad or overflowing frames whole.
  axis_fifo #(
      .DEPTH(4096),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(0),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(1),
      .USER_BAD_FRAME_VALUE(1'b1),
      .USER_BAD_FRAME_MASK(1'b1),
      .DROP_BAD_FRAME(1),
      .DROP_WHEN_FULL(1)
  ) rx_fifo (
      .clk(clk),
      .rst(rst),

      .s_axis_tdata(mac_rx_axis_tdata),
      .s_axis_tkeep(1'b0),
      .s_axis_tvalid(mac_rx_axis_tvalid),
      .s_axis_tready(),
      .s_axis_tlast(mac_rx_axis_tlast),
      .s_axis_tid(8'd0),
      .s_axis_tdest(8'd0),
      .s_axis_tuser(mac_rx_axis_tuser),

      .m_axis_tdata(rx_axis_tdata),
      .m_axis_tkeep(),
      .m_axis_tvalid(rx_axis_tvalid),
      .m_axis_tready(rx_axis_tready),
      .m_axis_tlast(rx_axis_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(rx_axis_tuser),

      .pause_req(1'b0),
      .pause_ack(),
      .status_depth(),
      .status_depth_commit(),
      .status_overflow(),
      .status_bad_frame(),
      .status_good_frame()
  );

  assign dbg_eth_hdr_ack = rx_eth_hdr_valid && rx_eth_hdr_ready;

  //-- Sticky handshake bits: which datapath signals have ever been high
  //-- since reset. Read back through the register block; each bit that
  //-- stays 0 narrows down where a frame got stuck.
  reg [15:0] sticky = 16'd0;
  assign dbg_sticky = sticky;
  always @(posedge clk) begin
    sticky <= sticky | {
      2'b00,
      tx_udp_hdr_valid,             // 13 app queued a reply
      rx_udp_hdr_valid,             // 12 UDP datagram reached the app
      mac_rx_axis_tuser,            // 11 MAC marked a frame bad
      mac_rx_axis_tlast,            // 10 MAC finished a frame
      mac_rx_axis_tvalid,           //  9 MAC produced payload bytes
      tx_axis_tready,               //  8 MAC accepting TX bytes
      tx_axis_tvalid,               //  7 framer pushed TX bytes
      tx_eth_hdr_valid,             //  6 stack queued a TX frame
      rx_eth_payload_axis_tready,   //  5 stack consumed eth payload
      rx_eth_payload_axis_tvalid,   //  4 framer produced eth payload
      rx_eth_hdr_ready,             //  3 stack ready for eth hdr
      rx_eth_hdr_valid,             //  2 framer parsed an eth hdr
      rx_axis_tready,               //  1 framer ready for FIFO data
      rx_axis_tvalid                //  0 FIFO presented data
    };
    if (rst) sticky <= 16'd0;
  end

  eth_axis_rx eth_axis_rx_inst (
      .clk(clk),
      .rst(rst),
      .s_axis_tdata(rx_axis_tdata),
      .s_axis_tvalid(rx_axis_tvalid),
      .s_axis_tready(rx_axis_tready),
      .s_axis_tlast(rx_axis_tlast),
      .s_axis_tuser(rx_axis_tuser),
      .m_eth_hdr_valid(rx_eth_hdr_valid),
      .m_eth_hdr_ready(rx_eth_hdr_ready),
      .m_eth_dest_mac(rx_eth_dest_mac),
      .m_eth_src_mac(rx_eth_src_mac),
      .m_eth_type(rx_eth_type),
      .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
      .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
      .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
      .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
      .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
      .busy(),
      .error_header_early_termination()
  );

  eth_axis_tx eth_axis_tx_inst (
      .clk(clk),
      .rst(rst),
      .s_eth_hdr_valid(tx_eth_hdr_valid),
      .s_eth_hdr_ready(tx_eth_hdr_ready),
      .s_eth_dest_mac(tx_eth_dest_mac),
      .s_eth_src_mac(tx_eth_src_mac),
      .s_eth_type(tx_eth_type),
      .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
      .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
      .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
      .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
      .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
      .m_axis_tdata(tx_axis_tdata),
      .m_axis_tvalid(tx_axis_tvalid),
      .m_axis_tready(tx_axis_tready),
      .m_axis_tlast(tx_axis_tlast),
      .m_axis_tuser(tx_axis_tuser),
      .busy()
  );

  udp_complete #(
      //-- time parameters are in clk cycles; scale for 25 MHz
      .ARP_CACHE_ADDR_WIDTH(2),
      .ARP_REQUEST_RETRY_INTERVAL(25000000 * 2),
      .ARP_REQUEST_TIMEOUT(25000000 * 30),
      //-- checksum 0 = "none", legal for IPv4 UDP and accepted by Linux.
      //-- The generator module also has a sim-only X-poisoning issue in
      //-- iverilog (its read-side always@* never evaluates at time zero
      //-- because every input holds its init value through reset).
      .UDP_CHECKSUM_GEN_ENABLE(0)
  ) udp_complete_inst (
      .clk(clk),
      .rst(rst),

      .s_eth_hdr_valid(rx_eth_hdr_valid),
      .s_eth_hdr_ready(rx_eth_hdr_ready),
      .s_eth_dest_mac(rx_eth_dest_mac),
      .s_eth_src_mac(rx_eth_src_mac),
      .s_eth_type(rx_eth_type),
      .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
      .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
      .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
      .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
      .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),

      .m_eth_hdr_valid(tx_eth_hdr_valid),
      .m_eth_hdr_ready(tx_eth_hdr_ready),
      .m_eth_dest_mac(tx_eth_dest_mac),
      .m_eth_src_mac(tx_eth_src_mac),
      .m_eth_type(tx_eth_type),
      .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
      .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
      .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
      .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
      .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),

      //-- raw IP interface unused: no ICMP, so ping won't answer (use arping)
      .s_ip_hdr_valid(1'b0),
      .s_ip_hdr_ready(),
      .s_ip_dscp(6'd0),
      .s_ip_ecn(2'd0),
      .s_ip_length(16'd0),
      .s_ip_ttl(8'd0),
      .s_ip_protocol(8'd0),
      .s_ip_source_ip(32'd0),
      .s_ip_dest_ip(32'd0),
      .s_ip_payload_axis_tdata(8'd0),
      .s_ip_payload_axis_tvalid(1'b0),
      .s_ip_payload_axis_tready(),
      .s_ip_payload_axis_tlast(1'b0),
      .s_ip_payload_axis_tuser(1'b0),

      .m_ip_hdr_valid(),
      .m_ip_hdr_ready(1'b1),
      .m_ip_eth_dest_mac(),
      .m_ip_eth_src_mac(),
      .m_ip_eth_type(),
      .m_ip_version(),
      .m_ip_ihl(),
      .m_ip_dscp(),
      .m_ip_ecn(),
      .m_ip_length(),
      .m_ip_identification(),
      .m_ip_flags(),
      .m_ip_fragment_offset(),
      .m_ip_ttl(),
      .m_ip_protocol(),
      .m_ip_header_checksum(),
      .m_ip_source_ip(),
      .m_ip_dest_ip(),
      .m_ip_payload_axis_tdata(),
      .m_ip_payload_axis_tvalid(),
      .m_ip_payload_axis_tready(1'b1),
      .m_ip_payload_axis_tlast(),
      .m_ip_payload_axis_tuser(),

      .s_udp_hdr_valid(tx_udp_hdr_valid),
      .s_udp_hdr_ready(tx_udp_hdr_ready),
      .s_udp_ip_dscp(6'd0),
      .s_udp_ip_ecn(2'd0),
      .s_udp_ip_ttl(8'd64),
      .s_udp_ip_source_ip(tx_udp_ip_source_ip),
      .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
      .s_udp_source_port(tx_udp_source_port),
      .s_udp_dest_port(tx_udp_dest_port),
      .s_udp_length(tx_udp_length),
      .s_udp_checksum(16'd0),
      .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
      .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
      .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
      .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
      .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),

      .m_udp_hdr_valid(rx_udp_hdr_valid),
      .m_udp_hdr_ready(rx_udp_hdr_ready),
      .m_udp_eth_dest_mac(),
      .m_udp_eth_src_mac(),
      .m_udp_eth_type(),
      .m_udp_ip_version(),
      .m_udp_ip_ihl(),
      .m_udp_ip_dscp(),
      .m_udp_ip_ecn(),
      .m_udp_ip_length(),
      .m_udp_ip_identification(),
      .m_udp_ip_flags(),
      .m_udp_ip_fragment_offset(),
      .m_udp_ip_ttl(),
      .m_udp_ip_protocol(),
      .m_udp_ip_header_checksum(),
      .m_udp_ip_source_ip(rx_udp_ip_source_ip),
      .m_udp_ip_dest_ip(),
      .m_udp_source_port(),
      .m_udp_dest_port(rx_udp_dest_port),
      .m_udp_length(),
      .m_udp_checksum(),
      .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
      .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
      .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
      .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
      .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),

      .ip_rx_busy(),
      .ip_tx_busy(),
      .udp_rx_busy(),
      .udp_tx_busy(),
      .ip_rx_error_header_early_termination(),
      .ip_rx_error_payload_early_termination(),
      .ip_rx_error_invalid_header(),
      .ip_rx_error_invalid_checksum(),
      .ip_tx_error_payload_early_termination(),
      .ip_tx_error_arp_failed(),
      .udp_rx_error_header_early_termination(),
      .udp_rx_error_payload_early_termination(),
      .udp_tx_error_payload_early_termination(),

      .local_mac(LOCAL_MAC),
      .local_ip(LOCAL_IP),
      .gateway_ip(GATEWAY_IP),
      .subnet_mask(SUBNET_MASK),
      .clear_arp_cache(1'b0)
  );

  acc_app #(
      .LOCAL_IP(LOCAL_IP),
      .LISTEN_PORT(LISTEN_PORT),
      .REPLY_PORT(REPLY_PORT)
  ) acc_app_inst (
      .clk(clk),
      .rst(rst),

      .rx_hdr_valid(rx_udp_hdr_valid),
      .rx_hdr_ready(rx_udp_hdr_ready),
      .rx_ip_source_ip(rx_udp_ip_source_ip),
      .rx_dest_port(rx_udp_dest_port),
      .rx_payload_tdata(rx_udp_payload_axis_tdata),
      .rx_payload_tvalid(rx_udp_payload_axis_tvalid),
      .rx_payload_tready(rx_udp_payload_axis_tready),
      .rx_payload_tlast(rx_udp_payload_axis_tlast),
      .rx_payload_tuser(rx_udp_payload_axis_tuser),

      .tx_hdr_valid(tx_udp_hdr_valid),
      .tx_hdr_ready(tx_udp_hdr_ready),
      .tx_ip_source_ip(tx_udp_ip_source_ip),
      .tx_ip_dest_ip(tx_udp_ip_dest_ip),
      .tx_source_port(tx_udp_source_port),
      .tx_dest_port(tx_udp_dest_port),
      .tx_length(tx_udp_length),
      .tx_payload_tdata(tx_udp_payload_axis_tdata),
      .tx_payload_tvalid(tx_udp_payload_axis_tvalid),
      .tx_payload_tready(tx_udp_payload_axis_tready),
      .tx_payload_tlast(tx_udp_payload_axis_tlast),
      .tx_payload_tuser(tx_udp_payload_axis_tuser),

      .enable(enable),
      .clear_total(clear_total),
      .total(total),
      .rx_count(rx_count),
      .tx_count(tx_count)
  );

endmodule
