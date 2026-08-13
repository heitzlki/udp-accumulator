/*
 * Drop-in replacement for verilog-ethernet's lfsr.v, same interface, with the
 * mask constants precomputed instead of derived by the lfsr_mask constant
 * function. Reason: yosys's AST simplifier effectively hangs (>1h) evaluating
 * that function inside the generate loops. Masks were extracted bit-exactly
 * from the upstream module (kept next to this file as lfsr.v.upstream) by
 * one-hot probing in iverilog; the project testbench verifies real CRC32
 * values end to end. Only the two parameter sets used by this design are
 * supported; anything else fails elaboration on purpose.
 */

// language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

module lfsr #(
    parameter LFSR_WIDTH = 31,
    parameter LFSR_POLY = 31'h10000001,
    parameter LFSR_CONFIG = "FIBONACCI",
    parameter LFSR_FEED_FORWARD = 0,
    parameter REVERSE = 0,
    parameter DATA_WIDTH = 8,
    parameter STYLE = "AUTO"
) (
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire [LFSR_WIDTH-1:0] state_in,
    output wire [DATA_WIDTH-1:0] data_out,
    output wire [LFSR_WIDTH-1:0] state_out
);

generate

if (LFSR_WIDTH == 32 && LFSR_POLY == 32'h4c11db7 && LFSR_CONFIG == "GALOIS" &&
    LFSR_FEED_FORWARD == 0 && REVERSE == 1 && DATA_WIDTH == 8) begin : crc32_d8

    assign state_out[0] = ^({data_in, state_in} & 40'h0400000104);
    assign state_out[1] = ^({data_in, state_in} & 40'h0900000209);
    assign state_out[2] = ^({data_in, state_in} & 40'h1300000413);
    assign state_out[3] = ^({data_in, state_in} & 40'h2600000826);
    assign state_out[4] = ^({data_in, state_in} & 40'h4d0000104d);
    assign state_out[5] = ^({data_in, state_in} & 40'h9a0000209a);
    assign state_out[6] = ^({data_in, state_in} & 40'h3000004030);
    assign state_out[7] = ^({data_in, state_in} & 40'h6100008061);
    assign state_out[8] = ^({data_in, state_in} & 40'hc2000100c2);
    assign state_out[9] = ^({data_in, state_in} & 40'h8000020080);
    assign state_out[10] = ^({data_in, state_in} & 40'h0400040004);
    assign state_out[11] = ^({data_in, state_in} & 40'h0800080008);
    assign state_out[12] = ^({data_in, state_in} & 40'h1100100011);
    assign state_out[13] = ^({data_in, state_in} & 40'h2300200023);
    assign state_out[14] = ^({data_in, state_in} & 40'h4600400046);
    assign state_out[15] = ^({data_in, state_in} & 40'h8c0080008c);
    assign state_out[16] = ^({data_in, state_in} & 40'h1d0100001d);
    assign state_out[17] = ^({data_in, state_in} & 40'h3b0200003b);
    assign state_out[18] = ^({data_in, state_in} & 40'h7704000077);
    assign state_out[19] = ^({data_in, state_in} & 40'hee080000ee);
    assign state_out[20] = ^({data_in, state_in} & 40'hd8100000d8);
    assign state_out[21] = ^({data_in, state_in} & 40'hb4200000b4);
    assign state_out[22] = ^({data_in, state_in} & 40'h6c4000006c);
    assign state_out[23] = ^({data_in, state_in} & 40'hd8800000d8);
    assign state_out[24] = ^({data_in, state_in} & 40'hb5000000b5);
    assign state_out[25] = ^({data_in, state_in} & 40'h6f0000006f);
    assign state_out[26] = ^({data_in, state_in} & 40'hdf000000df);
    assign state_out[27] = ^({data_in, state_in} & 40'hba000000ba);
    assign state_out[28] = ^({data_in, state_in} & 40'h7100000071);
    assign state_out[29] = ^({data_in, state_in} & 40'he3000000e3);
    assign state_out[30] = ^({data_in, state_in} & 40'hc3000000c3);
    assign state_out[31] = ^({data_in, state_in} & 40'h8200000082);
    assign data_out[0]  = ^({data_in, state_in} & 40'h0100000001);
    assign data_out[1]  = ^({data_in, state_in} & 40'h0200000002);
    assign data_out[2]  = ^({data_in, state_in} & 40'h0400000004);
    assign data_out[3]  = ^({data_in, state_in} & 40'h0800000008);
    assign data_out[4]  = ^({data_in, state_in} & 40'h1000000010);
    assign data_out[5]  = ^({data_in, state_in} & 40'h2000000020);
    assign data_out[6]  = ^({data_in, state_in} & 40'h4100000041);
    assign data_out[7]  = ^({data_in, state_in} & 40'h8200000082);

end else if (LFSR_WIDTH == 32 && LFSR_POLY == 32'h4c11db7 && LFSR_CONFIG == "GALOIS" &&
    LFSR_FEED_FORWARD == 0 && REVERSE == 1 && DATA_WIDTH == 32) begin : crc32_d32

    assign state_out[0] = ^({data_in, state_in} & 64'h04d101df04d101df);
    assign state_out[1] = ^({data_in, state_in} & 64'h09a203be09a203be);
    assign state_out[2] = ^({data_in, state_in} & 64'h1344077d1344077d);
    assign state_out[3] = ^({data_in, state_in} & 64'h26880efa26880efa);
    assign state_out[4] = ^({data_in, state_in} & 64'h4d101df44d101df4);
    assign state_out[5] = ^({data_in, state_in} & 64'h9a203be99a203be9);
    assign state_out[6] = ^({data_in, state_in} & 64'h3091760d3091760d);
    assign state_out[7] = ^({data_in, state_in} & 64'h6122ec1a6122ec1a);
    assign state_out[8] = ^({data_in, state_in} & 64'hc245d835c245d835);
    assign state_out[9] = ^({data_in, state_in} & 64'h805ab1b5805ab1b5);
    assign state_out[10] = ^({data_in, state_in} & 64'h046462b5046462b5);
    assign state_out[11] = ^({data_in, state_in} & 64'h08c8c56a08c8c56a);
    assign state_out[12] = ^({data_in, state_in} & 64'h11918ad411918ad4);
    assign state_out[13] = ^({data_in, state_in} & 64'h232315a9232315a9);
    assign state_out[14] = ^({data_in, state_in} & 64'h46462b5346462b53);
    assign state_out[15] = ^({data_in, state_in} & 64'h8c8c56a68c8c56a6);
    assign state_out[16] = ^({data_in, state_in} & 64'h1dc9ac921dc9ac92);
    assign state_out[17] = ^({data_in, state_in} & 64'h3b9359243b935924);
    assign state_out[18] = ^({data_in, state_in} & 64'h7726b2497726b249);
    assign state_out[19] = ^({data_in, state_in} & 64'hee4d6493ee4d6493);
    assign state_out[20] = ^({data_in, state_in} & 64'hd84bc8f9d84bc8f9);
    assign state_out[21] = ^({data_in, state_in} & 64'hb446902db446902d);
    assign state_out[22] = ^({data_in, state_in} & 64'h6c5c21846c5c2184);
    assign state_out[23] = ^({data_in, state_in} & 64'hd8b84309d8b84309);
    assign state_out[24] = ^({data_in, state_in} & 64'hb5a187ccb5a187cc);
    assign state_out[25] = ^({data_in, state_in} & 64'h6f920e466f920e46);
    assign state_out[26] = ^({data_in, state_in} & 64'hdf241c8cdf241c8c);
    assign state_out[27] = ^({data_in, state_in} & 64'hba9938c7ba9938c7);
    assign state_out[28] = ^({data_in, state_in} & 64'h71e3705171e37051);
    assign state_out[29] = ^({data_in, state_in} & 64'he3c6e0a3e3c6e0a3);
    assign state_out[30] = ^({data_in, state_in} & 64'hc35cc098c35cc098);
    assign state_out[31] = ^({data_in, state_in} & 64'h826880ef826880ef);
    assign data_out[0]  = ^({data_in, state_in} & 64'h0000000100000001);
    assign data_out[1]  = ^({data_in, state_in} & 64'h0000000200000002);
    assign data_out[2]  = ^({data_in, state_in} & 64'h0000000400000004);
    assign data_out[3]  = ^({data_in, state_in} & 64'h0000000800000008);
    assign data_out[4]  = ^({data_in, state_in} & 64'h0000001000000010);
    assign data_out[5]  = ^({data_in, state_in} & 64'h0000002000000020);
    assign data_out[6]  = ^({data_in, state_in} & 64'h0000004100000041);
    assign data_out[7]  = ^({data_in, state_in} & 64'h0000008200000082);
    assign data_out[8]  = ^({data_in, state_in} & 64'h0000010400000104);
    assign data_out[9]  = ^({data_in, state_in} & 64'h0000020900000209);
    assign data_out[10]  = ^({data_in, state_in} & 64'h0000041300000413);
    assign data_out[11]  = ^({data_in, state_in} & 64'h0000082600000826);
    assign data_out[12]  = ^({data_in, state_in} & 64'h0000104d0000104d);
    assign data_out[13]  = ^({data_in, state_in} & 64'h0000209a0000209a);
    assign data_out[14]  = ^({data_in, state_in} & 64'h0000413400004134);
    assign data_out[15]  = ^({data_in, state_in} & 64'h0000826800008268);
    assign data_out[16]  = ^({data_in, state_in} & 64'h000104d1000104d1);
    assign data_out[17]  = ^({data_in, state_in} & 64'h000209a2000209a2);
    assign data_out[18]  = ^({data_in, state_in} & 64'h0004134400041344);
    assign data_out[19]  = ^({data_in, state_in} & 64'h0008268800082688);
    assign data_out[20]  = ^({data_in, state_in} & 64'h00104d1000104d10);
    assign data_out[21]  = ^({data_in, state_in} & 64'h00209a2000209a20);
    assign data_out[22]  = ^({data_in, state_in} & 64'h0041344000413440);
    assign data_out[23]  = ^({data_in, state_in} & 64'h0082688000826880);
    assign data_out[24]  = ^({data_in, state_in} & 64'h0104d1010104d101);
    assign data_out[25]  = ^({data_in, state_in} & 64'h0209a2030209a203);
    assign data_out[26]  = ^({data_in, state_in} & 64'h0413440704134407);
    assign data_out[27]  = ^({data_in, state_in} & 64'h0826880e0826880e);
    assign data_out[28]  = ^({data_in, state_in} & 64'h104d101d104d101d);
    assign data_out[29]  = ^({data_in, state_in} & 64'h209a203b209a203b);
    assign data_out[30]  = ^({data_in, state_in} & 64'h4134407741344077);
    assign data_out[31]  = ^({data_in, state_in} & 64'h826880ef826880ef);

end else begin : unsupported
    // deliberate elaboration failure: masks for this parameter set are not
    // precomputed; see lfsr.v.upstream for the generic implementation
    lfsr_unsupported_parameter_set not_precomputed ();
end

endgenerate

endmodule

`resetall
