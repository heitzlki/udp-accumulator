//-------------------------------------------------------------------
//-- Testbench: plays the role of GEM1 + Linux on acc_core's GMII.
//-- Sends an ARP request, then UDP datagrams with one uint32 each, and
//-- checks the ARP reply and the {n, total} UDP replies, FCS included.
//-- MII nibble mode throughout: 4 bits per clock, low nibble first.
//-------------------------------------------------------------------
`default_nettype none `timescale 1 ns / 1 ps

module udp_accumulator_tb ();

  localparam [47:0] HOST_MAC = 48'h02_00_00_00_00_01;
  localparam [47:0] FPGA_MAC = 48'h02_00_00_00_00_02;
  localparam [31:0] HOST_IP = {8'd10, 8'd99, 8'd0, 8'd1};
  localparam [31:0] FPGA_IP = {8'd10, 8'd99, 8'd0, 8'd2};

  reg clk;
  reg rst;

  //-- TB -> core (GEM1 transmit side)
  reg  [7:0] core_rxd;
  reg        core_rx_dv;
  //-- core -> TB (GEM1 receive side)
  wire [7:0] core_txd;
  wire       core_tx_en;

  wire [31:0] total, rx_count, tx_count;

  acc_core UUT (
      .clk(clk),
      .rst(rst),
      .gmii_rxd(core_rxd),
      .gmii_rx_dv(core_rx_dv),
      .gmii_rx_er(1'b0),
      .gmii_txd(core_txd),
      .gmii_tx_en(core_tx_en),
      .gmii_tx_er(),
      .enable(1'b1),
      .clear_total(1'b0),
      .total(total),
      .rx_count(rx_count),
      .tx_count(tx_count),
      .rx_start_packet(),
      .tx_start_packet(),
      .rx_error_bad_fcs()
  );

  //-- 25 MHz clock (40 ns period)
  initial begin
    clk = 1;
    forever #20 clk = ~clk;
  end

  //-------------------------------------------------------------------
  //-- CRC32 (Ethernet FCS): reflected, poly 0xEDB88320, init 0xFFFFFFFF.
  //-- Residue after running over payload + FCS is 32'hDEBB20E3.
  //-------------------------------------------------------------------
  function [31:0] crc32_byte(input [31:0] crc, input [7:0] data);
    integer i;
    reg [31:0] c;
    begin
      c = crc ^ {24'd0, data};
      for (i = 0; i < 8; i = i + 1) c = (c >> 1) ^ (c[0] ? 32'hEDB88320 : 32'd0);
      crc32_byte = c;
    end
  endfunction

  //-------------------------------------------------------------------
  //-- TB -> core frame transmission
  //-------------------------------------------------------------------
  reg [7:0] txf[0:127];  // frame bytes, no preamble/FCS
  integer txlen;

  task send_frame;
    integer i;
    reg [31:0] crc;
    begin
      //-- pad to 60 bytes (min frame minus FCS)
      while (txlen < 60) begin
        txf[txlen] = 8'h00;
        txlen = txlen + 1;
      end
      crc = 32'hFFFFFFFF;
      for (i = 0; i < txlen; i = i + 1) crc = crc32_byte(crc, txf[i]);
      crc = ~crc;
      //-- preamble + SFD
      for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
      send_byte(8'hD5);
      for (i = 0; i < txlen; i = i + 1) send_byte(txf[i]);
      //-- FCS, least significant byte first
      send_byte(crc[7:0]);
      send_byte(crc[15:8]);
      send_byte(crc[23:16]);
      send_byte(crc[31:24]);
      core_rx_dv <= 0;
      core_rxd   <= 0;
      //-- interframe gap
      repeat (32) @(posedge clk);
    end
  endtask

  task send_byte(input [7:0] b);
    begin
      core_rxd   <= {4'd0, b[3:0]};
      core_rx_dv <= 1;
      @(posedge clk);
      core_rxd <= {4'd0, b[7:4]};
      @(posedge clk);
    end
  endtask

  //-- frame header builders --------------------------------------------
  task put_mac(input integer at, input [47:0] mac);
    integer i;
    begin
      for (i = 0; i < 6; i = i + 1) txf[at+i] = mac[8*(5-i)+:8];
    end
  endtask

  task put32(input integer at, input [31:0] v);
    begin
      txf[at]   = v[31:24];
      txf[at+1] = v[23:16];
      txf[at+2] = v[15:8];
      txf[at+3] = v[7:0];
    end
  endtask

  task put16(input integer at, input [15:0] v);
    begin
      txf[at]   = v[15:8];
      txf[at+1] = v[7:0];
    end
  endtask

  function [15:0] ip_checksum;  // over txf[14..33], checksum field zeroed
    input integer dummy;
    integer i;
    reg [31:0] sum;
    begin
      sum = 0;
      for (i = 0; i < 10; i = i + 1) sum = sum + {txf[14+2*i], txf[15+2*i]};
      sum = (sum & 32'hFFFF) + (sum >> 16);
      sum = (sum & 32'hFFFF) + (sum >> 16);
      ip_checksum = ~sum[15:0];
    end
  endfunction

  task send_arp_request;
    begin
      put_mac(0, 48'hFF_FF_FF_FF_FF_FF);
      put_mac(6, HOST_MAC);
      put16(12, 16'h0806);
      put16(14, 16'h0001);  // htype ethernet
      put16(16, 16'h0800);  // ptype ipv4
      txf[18] = 8'h06;
      txf[19] = 8'h04;
      put16(20, 16'h0001);  // oper: request
      put_mac(22, HOST_MAC);
      put32(28, HOST_IP);
      put_mac(32, 48'd0);
      put32(38, FPGA_IP);
      txlen = 42;
      send_frame;
    end
  endtask

  task send_arp_reply;  // answer a request the DUT sent us
    begin
      put_mac(0, FPGA_MAC);
      put_mac(6, HOST_MAC);
      put16(12, 16'h0806);
      put16(14, 16'h0001);
      put16(16, 16'h0800);
      txf[18] = 8'h06;
      txf[19] = 8'h04;
      put16(20, 16'h0002);  // oper: reply
      put_mac(22, HOST_MAC);
      put32(28, HOST_IP);
      put_mac(32, FPGA_MAC);
      put32(38, FPGA_IP);
      txlen = 42;
      send_frame;
    end
  endtask

  task send_udp_number(input [31:0] n, input [15:0] ip_id);
    begin
      put_mac(0, FPGA_MAC);
      put_mac(6, HOST_MAC);
      put16(12, 16'h0800);
      txf[14] = 8'h45;  // IPv4, IHL 5
      txf[15] = 8'h00;
      put16(16, 16'd32);  // total length: 20 IP + 8 UDP + 4 payload
      put16(18, ip_id);
      put16(20, 16'h0000);  // no flags/fragment
      txf[22] = 8'd64;  // ttl
      txf[23] = 8'd17;  // UDP
      put16(24, 16'h0000);  // checksum placeholder
      put32(26, HOST_IP);
      put32(30, FPGA_IP);
      put16(24, ip_checksum(0));
      put16(34, 16'd40000);  // source port
      put16(36, 16'd1234);  // dest port: LISTEN_PORT
      put16(38, 16'd12);  // UDP length
      put16(40, 16'h0000);  // UDP checksum 0 = none
      put32(42, n);
      txlen = 46;
      send_frame;
    end
  endtask

  //-------------------------------------------------------------------
  //-- core -> TB frame capture (nibbles -> bytes -> validated frame)
  //-------------------------------------------------------------------
  reg [7:0] cap[0:255];  // raw capture including preamble + FCS
  reg [7:0] rxf[0:255];  // payload after SFD, FCS stripped
  integer capn, rxlen;
  reg have_low;
  reg [3:0] low_nib;
  reg frame_ready;

  integer k, sfd;
  reg [31:0] mcrc;

  always @(posedge clk) begin
    if (core_tx_en) begin
      if (!have_low) begin
        low_nib  <= core_txd[3:0];
        have_low <= 1;
      end else begin
        cap[capn] <= {core_txd[3:0], low_nib};
        capn <= capn + 1;
        have_low <= 0;
      end
    end else if (capn > 0) begin
      //-- frame ended: locate SFD, check FCS residue, strip
      sfd = -1;
      for (k = 0; k < capn && sfd < 0; k = k + 1)
        if (cap[k] == 8'hD5) sfd = k;
        else if (cap[k] != 8'h55) begin
          $display("FAIL: bad preamble byte %02x at %0d", cap[k], k);
          $fatal;
        end
      if (sfd < 0 || capn - (sfd + 1) < 64) begin
        $display("FAIL: no SFD or runt frame (capn=%0d)", capn);
        $fatal;
      end
      mcrc = 32'hFFFFFFFF;
      for (k = sfd + 1; k < capn; k = k + 1) mcrc = crc32_byte(mcrc, cap[k]);
      if (mcrc != 32'hDEBB20E3) begin
        $display("FAIL: bad FCS on frame from DUT (residue %08x)", mcrc);
        $fatal;
      end
      rxlen = capn - (sfd + 1) - 4;
      for (k = 0; k < rxlen; k = k + 1) rxf[k] = cap[sfd+1+k];
      frame_ready <= 1;
      capn <= 0;
      have_low <= 0;
    end
  end

  task wait_frame;  // waits for the next validated frame in rxf/rxlen
    integer guard;
    begin
      guard = 0;
      while (!frame_ready) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 50000) begin
          $display("FAIL: timeout waiting for frame from DUT");
          $fatal;
        end
      end
      frame_ready <= 0;
      @(posedge clk);
    end
  endtask

  function [15:0] rx16(input integer at);
    rx16 = {rxf[at], rxf[at+1]};
  endfunction

  function [31:0] rx32(input integer at);
    rx32 = {rxf[at], rxf[at+1], rxf[at+2], rxf[at+3]};
  endfunction

  //-------------------------------------------------------------------
  //-- checks
  //-------------------------------------------------------------------
  task expect_udp_reply(input [31:0] n, input [31:0] expected_total);
    reg done;
    begin
      done = 0;
      while (!done) begin
        wait_frame;
        if (rx16(12) == 16'h0806 && rx16(20) == 16'h0001) begin
          //-- DUT is ARP-resolving us first: answer and keep waiting
          $display("  (answering ARP request from DUT)");
          send_arp_reply;
        end else begin
          if (rx16(12) != 16'h0800) begin
            $display("FAIL: expected IPv4 reply, ethertype %04x", rx16(12));
            $fatal;
          end
          if (rxf[23] != 8'd17) begin
            $display("FAIL: expected UDP, proto %02x", rxf[23]);
            $fatal;
          end
          if (rx32(30) != HOST_IP) begin
            $display("FAIL: reply dest ip %08x", rx32(30));
            $fatal;
          end
          if (rx16(34) != 16'd1234 || rx16(36) != 16'd5678) begin
            $display("FAIL: reply ports %0d -> %0d", rx16(34), rx16(36));
            $fatal;
          end
          if (rx16(38) != 16'd16) begin
            $display("FAIL: reply UDP length %0d", rx16(38));
            $fatal;
          end
          if (rx16(40) != 16'h0000) begin
            $display("FAIL: reply UDP checksum %04x, expected 0 (checksum-none)", rx16(40));
            $fatal;
          end
          if (rx32(42) != n || rx32(46) != expected_total) begin
            $display("FAIL: reply payload {%0d, %0d}, expected {%0d, %0d}", rx32(42), rx32(46), n,
                     expected_total);
            $fatal;
          end
          $display("  UDP reply ok: n=%0d total=%0d", rx32(42), rx32(46));
          done = 1;
        end
      end
    end
  endtask

  //-------------------------------------------------------------------
  //-- test sequence
  //-------------------------------------------------------------------
  initial begin
    $dumpvars(0, udp_accumulator_tb);

    rst = 1;
    core_rx_dv = 0;
    core_rxd = 0;
    have_low = 0;
    capn = 0;
    frame_ready = 0;
    repeat (32) @(posedge clk);
    @(negedge clk);  // release reset away from the sampling edge
    rst = 0;
    repeat (16) @(posedge clk);

    $display("1: ARP who-has %0d.%0d.%0d.%0d", FPGA_IP[31:24], FPGA_IP[23:16], FPGA_IP[15:8],
             FPGA_IP[7:0]);
    send_arp_request;
    wait_frame;
    if (rx16(12) != 16'h0806 || rx16(20) != 16'h0002) begin
      $display("FAIL: expected ARP reply, got ethertype %04x oper %04x", rx16(12), rx16(20));
      $fatal;
    end
    if ({rxf[22], rxf[23], rxf[24], rxf[25], rxf[26], rxf[27]} != FPGA_MAC) begin
      $display("FAIL: ARP reply sha mismatch");
      $fatal;
    end
    if (rx32(28) != FPGA_IP) begin
      $display("FAIL: ARP reply spa mismatch");
      $fatal;
    end
    $display("  ARP reply ok");

    $display("2: send 7, expect total 7");
    send_udp_number(32'd7, 16'd1);
    expect_udp_reply(32'd7, 32'd7);

    $display("3: send 35, expect total 42");
    send_udp_number(32'd35, 16'd2);
    expect_udp_reply(32'd35, 32'd42);

    $display("4: send 100, expect total 142");
    send_udp_number(32'd100, 16'd3);
    expect_udp_reply(32'd100, 32'd142);

    if (rx_count !== 32'd3 || tx_count !== 32'd3 || total !== 32'd142) begin
      $display("FAIL: telemetry total=%0d rx=%0d tx=%0d", total, rx_count, tx_count);
      $fatal;
    end
    $display("  telemetry ok: total=%0d rx_count=%0d tx_count=%0d", total, rx_count, tx_count);

    $display("PASS");
    $finish;
  end

  //-- global watchdog
  initial begin
    #10_000_000;
    $display("FAIL: global timeout");
    $fatal;
  end

  //-- Debug probes on stack internals (print rarely; cheap to keep).
  //-- Guarded so the same testbench can also run against a synthesized
  //-- netlist (define POSTSYNTH), where these hierarchical names are gone.
`ifndef POSTSYNTH
  always @(posedge clk) begin
    if (UUT.rx_eth_hdr_valid && UUT.rx_eth_hdr_ready)
      $display("  [dbg] eth rx frame, type %04x", UUT.rx_eth_type);
    if (UUT.rx_udp_hdr_valid && UUT.rx_udp_hdr_ready)
      $display("  [dbg] udp rx hdr, dest port %0d", UUT.rx_udp_dest_port);
    if (UUT.tx_udp_hdr_valid && UUT.tx_udp_hdr_ready) $display("  [dbg] udp tx hdr accepted");
    if (UUT.udp_complete_inst.ip_rx_error_invalid_checksum)
      $display("  [dbg] ip rx error: invalid checksum");
    if (UUT.udp_complete_inst.ip_rx_error_invalid_header)
      $display("  [dbg] ip rx error: invalid header");
    if (UUT.udp_complete_inst.ip_rx_error_header_early_termination)
      $display("  [dbg] ip rx error: header early termination");
    if (UUT.udp_complete_inst.ip_rx_error_payload_early_termination)
      $display("  [dbg] ip rx error: payload early termination");
    if (UUT.udp_complete_inst.udp_rx_error_header_early_termination)
      $display("  [dbg] udp rx error: header early termination");
    if (UUT.udp_complete_inst.ip_tx_error_arp_failed) $display("  [dbg] ip tx error: arp failed");
    if (UUT.eth_mac_inst.rx_error_bad_fcs) $display("  [dbg] mac rx: bad fcs");
    if (UUT.eth_mac_inst.rx_error_bad_frame) $display("  [dbg] mac rx: bad frame");
  end

  reg [2:0] app_state_prev;
  always @(posedge clk) begin
    app_state_prev <= UUT.acc_app_inst.state;
    if (UUT.acc_app_inst.state != app_state_prev)
      $display("  [dbg] acc_app state %0d -> %0d", app_state_prev, UUT.acc_app_inst.state);
    if (UUT.udp_complete_inst.ip_complete_inst.arp_request_valid
        && UUT.udp_complete_inst.ip_complete_inst.arp_request_ready)
      $display("  [dbg] arp lookup requested");
    if (UUT.udp_complete_inst.ip_complete_inst.arp_response_valid)
      $display("  [dbg] arp lookup response, error=%b",
               UUT.udp_complete_inst.ip_complete_inst.arp_response_error);
  end
`endif

endmodule
