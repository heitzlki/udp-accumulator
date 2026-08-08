`default_nettype none

//-- Accumulator application logic, one 32-bit big-endian number per UDP
//-- datagram on LISTEN_PORT: total <= total + n, then a UDP reply with
//-- {n, total} (8 bytes, big-endian) is sent back to the sender's IP on
//-- REPLY_PORT. One datagram in flight at a time; datagrams to other ports
//-- and payloads shorter than 4 bytes are drained and ignored.
module acc_app #(
    parameter [31:0] LOCAL_IP    = {8'd10, 8'd99, 8'd0, 8'd2},
    parameter [15:0] LISTEN_PORT = 16'd1234,
    parameter [15:0] REPLY_PORT  = 16'd5678
) (
    input  wire        clk,
    input  wire        rst,

    //-- UDP frame input (udp_complete m_udp_*)
    input  wire        rx_hdr_valid,
    output wire        rx_hdr_ready,
    input  wire [31:0] rx_ip_source_ip,
    input  wire [15:0] rx_dest_port,
    input  wire [ 7:0] rx_payload_tdata,
    input  wire        rx_payload_tvalid,
    output wire        rx_payload_tready,
    input  wire        rx_payload_tlast,
    input  wire        rx_payload_tuser,

    //-- UDP frame output (udp_complete s_udp_*)
    output wire        tx_hdr_valid,
    input  wire        tx_hdr_ready,
    output wire [31:0] tx_ip_source_ip,
    output reg  [31:0] tx_ip_dest_ip,
    output wire [15:0] tx_source_port,
    output wire [15:0] tx_dest_port,
    output wire [15:0] tx_length,
    output wire [ 7:0] tx_payload_tdata,
    output wire        tx_payload_tvalid,
    input  wire        tx_payload_tready,
    output wire        tx_payload_tlast,
    output wire        tx_payload_tuser,

    //-- control (from axil_regs)
    input  wire        enable,
    input  wire        clear_total,

    //-- telemetry (to axil_regs)
    output reg  [31:0] total,
    output reg  [31:0] rx_count,
    output reg  [31:0] tx_count
);

  localparam ST_IDLE = 3'd0;
  localparam ST_RECV = 3'd1;
  localparam ST_DRAIN = 3'd2;
  localparam ST_UPDATE = 3'd3;
  localparam ST_TX_HDR = 3'd4;
  localparam ST_TX_DATA = 3'd5;

  reg [ 2:0] state;
  reg [31:0] n;  // number parsed from the current datagram
  reg [ 2:0] byte_cnt;  // rx: payload bytes captured; tx: reply byte index
  reg [63:0] reply;  // {n, new total}, sent big-endian

  assign rx_hdr_ready = (state == ST_IDLE);
  assign rx_payload_tready = (state == ST_RECV) || (state == ST_DRAIN);
  assign tx_hdr_valid = (state == ST_TX_HDR);
  assign tx_ip_source_ip = LOCAL_IP;
  assign tx_source_port = LISTEN_PORT;
  assign tx_dest_port = REPLY_PORT;
  assign tx_length = 16'd16;  // 8 UDP header + 8 payload
  assign tx_payload_tvalid = (state == ST_TX_DATA);
  assign tx_payload_tdata = reply[8*(7-byte_cnt)+:8];
  assign tx_payload_tlast = (state == ST_TX_DATA) && (byte_cnt == 3'd7);
  assign tx_payload_tuser = 1'b0;

  always @(posedge clk) begin
    case (state)
      ST_IDLE: begin
        if (rx_hdr_valid) begin
          tx_ip_dest_ip <= rx_ip_source_ip;
          n             <= 0;
          byte_cnt      <= 0;
          state <= (enable && rx_dest_port == LISTEN_PORT) ? ST_RECV : ST_DRAIN;
        end
      end

      ST_RECV: begin
        if (rx_payload_tvalid) begin
          if (byte_cnt < 3'd4) begin
            n        <= {n[23:0], rx_payload_tdata};
            byte_cnt <= byte_cnt + 1;
          end
          if (rx_payload_tlast) begin
            //-- tuser marks a frame the stack flagged bad: drop it.
            //-- byte_cnt is pre-increment: >= 3 here means >= 4 bytes total.
            if (rx_payload_tuser || byte_cnt < 3'd3) state <= ST_IDLE;
            else state <= ST_UPDATE;
          end
        end
      end

      ST_DRAIN: begin
        if (rx_payload_tvalid && rx_payload_tlast) state <= ST_IDLE;
      end

      ST_UPDATE: begin
        total    <= total + n;
        reply    <= {n, total + n};
        rx_count <= rx_count + 1;
        state    <= ST_TX_HDR;
      end

      ST_TX_HDR: begin
        byte_cnt <= 0;
        if (tx_hdr_ready) state <= ST_TX_DATA;
      end

      ST_TX_DATA: begin
        if (tx_payload_tready) begin
          byte_cnt <= byte_cnt + 1;
          if (byte_cnt == 3'd7) begin
            tx_count <= tx_count + 1;
            state    <= ST_IDLE;
          end
        end
      end

      default: state <= ST_IDLE;
    endcase

    //-- slow-path controls win over everything above
    if (clear_total) total <= 0;

    if (rst) begin
      state    <= ST_IDLE;
      total    <= 0;
      rx_count <= 0;
      tx_count <= 0;
    end
  end

endmodule
